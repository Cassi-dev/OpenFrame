import CWhisper
import Foundation

/// Ponte para o whisper.cpp (alvo `CWhisper`). Um contexto por vez fica carregado (o modelo e os
/// shaders do Metal levam alguns segundos na primeira vez) e as transcrições são uma de cada vez.
final class WhisperEngine: @unchecked Sendable {
    static let shared = WhisperEngine()

    /// Palavra com tempos em segundos desde o início do áudio entregue.
    struct Word: Equatable {
        var text: String
        var start: Double
        var end: Double
        var probability: Double
    }

    /// Como os tempos das palavras são calculados (medidos contra o `say`: ver os testes).
    enum Timing: Sendable {
        /// `token_timestamps`: t0/t1 de cada token pelas probabilidades dos tokens de tempo.
        case tokens
        /// DTW sobre as cabeças de alinhamento do modelo: o início de cada token.
        case dtw
    }

    struct Options: Sendable {
        var language: String?
        var timing = Timing.dtw
        /// Ajusta as fronteiras pela energia do áudio (`WordAligner`).
        var refine = true
        var useGPU = ProcessInfo.processInfo.environment["OPENFRAME_WHISPER_CPU"] != "1"
        var threads = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    /// Sinaliza o cancelamento para o whisper (lido por outra thread).
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    private final class Callbacks {
        let progress: (Double) -> Void
        let cancelled: Flag
        let exiting: Flag
        init(progress: @escaping (Double) -> Void, cancelled: Flag, exiting: Flag) {
            self.progress = progress
            self.cancelled = cancelled
            self.exiting = exiting
        }
        var stop: Bool { cancelled.isSet || exiting.isSet }
    }

    private let lock = NSLock()
    private var context: OpaquePointer?
    private var contextKey: String?
    private var lastUse = Date()
    /// Ligado no `exit`: interrompe uma transcrição em andamento para o contexto ser liberado.
    private let exiting = Flag()

    private var exitHookInstalled = false

    private init() {
        Self.silenceLogs()
    }

    /// O ggml-metal confere, nos destrutores estáticos, que nenhum contexto ficou vivo: o modelo tem
    /// de ser liberado antes deles. O `atexit` roda na ordem inversa do registro, então ele é
    /// registrado depois do primeiro modelo carregado (quando os estáticos do ggml já existem).
    private func installExitHook() {
        guard !exitHookInstalled else { return }
        exitHookInstalled = true
        atexit {
            WhisperEngine.shared.exiting.set()
            WhisperEngine.shared.unload()
        }
    }

    /// Modelo parado há mais que isso é liberado (o turbo ocupa ~800 MB).
    static let idleUnload: TimeInterval = 180

    private func scheduleIdleUnload() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.idleUnload + 1) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard Date().timeIntervalSince(self.lastUse) >= Self.idleUnload, let context = self.context else { return }
            whisper_free(context)
            self.context = nil
            self.contextKey = nil
        }
    }

    /// Os logs do whisper e do ggml vão para o stderr; só com `OPENFRAME_WHISPER_LOG=1`.
    private static func silenceLogs() {
        guard ProcessInfo.processInfo.environment["OPENFRAME_WHISPER_LOG"] != "1" else { return }
        whisper_log_set({ _, _, _ in }, nil)
    }

    /// Libera o modelo carregado (ex.: depois de apagá-lo).
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        if let context { whisper_free(context) }
        context = nil
        contextKey = nil
    }

    /// Transcreve áudio mono de 16 kHz. Bloqueia a thread; o cancelamento chega por `cancelled`.
    func transcribe(_ samples: [Float], modelURL: URL, model: WhisperModel?, options: Options, cancelled: Flag,
                    progress: @escaping (Double) -> Void) throws -> [Word] {
        lock.lock()
        defer {
            lastUse = Date()
            lock.unlock()
            scheduleIdleUnload()
        }
        let ctx = try loadContext(modelURL: modelURL, model: model, options: options)
        guard !cancelled.isSet else { throw CancellationError() }

        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 5
        params.n_threads = Int32(options.threads)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        // Sem o texto anterior como contexto: com ele, fala repetitiva fazia o turbo pular trechos
        // inteiros (WER 0,14 → 0 na medição de 1 min), sem perda nos outros modelos.
        params.no_context = true
        params.suppress_nst = true
        params.token_timestamps = options.timing == .tokens

        let callbacks = Callbacks(progress: progress, cancelled: cancelled, exiting: exiting)
        let box = Unmanaged.passRetained(callbacks)
        defer { box.release() }
        params.progress_callback = { _, _, percent, user in
            guard let user else { return }
            Unmanaged<Callbacks>.fromOpaque(user).takeUnretainedValue().progress(Double(percent) / 100)
        }
        params.progress_callback_user_data = box.toOpaque()
        params.abort_callback = { user in
            guard let user else { return false }
            return Unmanaged<Callbacks>.fromOpaque(user).takeUnretainedValue().stop
        }
        params.abort_callback_user_data = box.toOpaque()
        params.encoder_begin_callback = { _, _, user in
            guard let user else { return true }
            return !Unmanaged<Callbacks>.fromOpaque(user).takeUnretainedValue().stop
        }
        params.encoder_begin_callback_user_data = box.toOpaque()

        let language = options.language.flatMap { $0.isEmpty ? nil : $0 } ?? "auto"
        let status = language.withCString { lang -> Int32 in
            params.language = lang
            params.detect_language = false
            return samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
        }
        if cancelled.isSet || exiting.isSet { throw CancellationError() }
        guard status == 0 else { throw TranscriptionError.failed("o whisper.cpp devolveu o código \(status)") }
        progress(1)
        let found = words(ctx, timing: options.timing)
        return options.refine ? WordAligner.refine(found, samples: samples, sampleRate: AudioMixdown.sampleRate) : found
    }

    private func loadContext(modelURL: URL, model: WhisperModel?, options: Options) throws -> OpaquePointer {
        let key = "\(modelURL.path)|\(options.useGPU)|\(options.timing)"
        if let context, contextKey == key { return context }
        if let context { whisper_free(context) }
        context = nil
        contextKey = nil

        var cparams = whisper_context_default_params()
        cparams.use_gpu = options.useGPU
        if options.timing == .dtw {
            // O DTW precisa das matrizes de atenção: sem flash attention.
            cparams.flash_attn = false
            cparams.dtw_token_timestamps = true
            cparams.dtw_aheads_preset = Self.alignmentHeads(model)
            if cparams.dtw_aheads_preset == WHISPER_AHEADS_N_TOP_MOST { cparams.dtw_n_top = 2 }
        } else {
            cparams.flash_attn = true
        }
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, cparams) else {
            throw TranscriptionError.failed("não foi possível abrir o modelo \(modelURL.lastPathComponent)")
        }
        context = ctx
        contextKey = key
        installExitHook()
        return ctx
    }

    static func alignmentHeads(_ model: WhisperModel?) -> whisper_alignment_heads_preset {
        switch model {
        case .base: WHISPER_AHEADS_BASE
        case .small: WHISPER_AHEADS_SMALL
        case .turbo: WHISPER_AHEADS_LARGE_V3_TURBO
        case nil: WHISPER_AHEADS_N_TOP_MOST
        }
    }

    /// Junta os tokens em palavras: um token que começa com espaço abre uma palavra nova; os outros
    /// (sub-palavras, pontuação grudada) continuam a anterior. Os bytes são juntados antes de virar
    /// texto, porque um caractere acentuado pode vir partido em dois tokens.
    private func words(_ ctx: OpaquePointer, timing: Timing) -> [Word] {
        let eot = whisper_token_eot(ctx)
        struct Piece {
            var bytes: [UInt8]
            var start: Double
            var end: Double
            var p: Double
        }
        var pieces: [[Piece]] = []
        for s in 0..<whisper_full_n_segments(ctx) {
            let segEnd = Double(whisper_full_get_segment_t1(ctx, s)) / 100
            var tokens: [Piece] = []
            for t in 0..<whisper_full_n_tokens(ctx, s) {
                let data = whisper_full_get_token_data(ctx, s, t)
                guard data.id < eot, let cText = whisper_full_get_token_text(ctx, s, t) else { continue }
                let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(cText).assumingMemoryBound(to: UInt8.self),
                                                      count: strlen(cText)))
                guard !bytes.isEmpty else { continue }
                let start: Double
                let end: Double
                switch timing {
                case .tokens:
                    start = Double(data.t0) / 100
                    end = Double(data.t1) / 100
                case .dtw:
                    start = Double(data.t_dtw) / 100
                    end = start
                }
                tokens.append(Piece(bytes: bytes, start: start, end: end, p: Double(data.p)))
            }
            // No DTW, o fim de cada token é o início do próximo (o último vai até o fim do segmento).
            if timing == .dtw {
                for i in tokens.indices {
                    tokens[i].end = i + 1 < tokens.count ? max(tokens[i].start, tokens[i + 1].start) : max(tokens[i].start, segEnd)
                }
            }
            pieces.append(tokens)
        }

        var result: [Word] = []
        for tokens in pieces {
            var current: (bytes: [UInt8], start: Double, end: Double, p: [Double])?
            func flush() {
                guard let c = current else { return }
                let text = String(decoding: c.bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append(Word(text: text, start: c.start, end: max(c.end, c.start),
                                       probability: c.p.reduce(0, +) / Double(max(c.p.count, 1))))
                }
                current = nil
            }
            for piece in tokens {
                if piece.bytes.first == UInt8(ascii: " ") || current == nil {
                    flush()
                    current = (piece.bytes, piece.start, piece.end, [piece.p])
                } else {
                    current!.bytes += piece.bytes
                    current!.end = max(current!.end, piece.end)
                    current!.p.append(piece.p)
                }
            }
            flush()
        }
        return result
    }
}
