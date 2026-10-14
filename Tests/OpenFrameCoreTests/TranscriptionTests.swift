import AVFoundation
import Foundation
import Testing
@testable import OpenFrameCore

/// Fala sintética do `say` (voz pt_BR) para os testes de transcrição.
enum Speech {
    static let voice = "Luciana"

    /// Modelo dos testes, baixado à parte por `scripts/baixar-modelo-teste.sh` (os testes nunca baixam).
    static func modelURL(_ m: WhisperModel = .base) -> URL? {
        // OPENFRAME_TEST_MODELS_DIR troca a pasta (ex.: para conferir que os testes são pulados).
        let dir = ProcessInfo.processInfo.environment["OPENFRAME_TEST_MODELS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/OpenFrame-test-models")
        let url = dir.appendingPathComponent(m.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var hasModel: Bool { modelURL() != nil }
    static let skipMessage: Comment = "Modelo de teste ausente: rode scripts/baixar-modelo-teste.sh"

    /// Amostras mono do `say` a 16 kHz.
    static func say(_ text: String) throws -> [Float] {
        let url = TestMedia.tempURL("caf")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", url.path, "--file-format=caff", "--data-format=LEF32@16000", text]
        try p.run()
        p.waitUntilExit()
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// Trecho com som (sem o silêncio do começo e do fim).
    static func trimmed(_ s: [Float]) -> [Float] {
        let threshold: Float = 0.01
        guard let first = s.firstIndex(where: { abs($0) > threshold }),
              let last = s.lastIndex(where: { abs($0) > threshold }) else { return [] }
        return Array(s[first...last])
    }

    struct Truth {
        let text: String
        let start: Double
        let end: Double
    }

    /// Frase dita palavra por palavra, emendada com pausas conhecidas: os tempos de cada palavra
    /// são exatos. Depois de vírgula e ponto, a pausa é maior.
    static func wordByWord(_ sentence: String, lead: Double = 0.5) throws -> (samples: [Float], truth: [Truth]) {
        var samples = [Float](repeating: 0, count: Int(lead * 16_000))
        var truth: [Truth] = []
        for word in sentence.split(separator: " ").map(String.init) {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            let audio = trimmed(try say(clean))
            let start = Double(samples.count) / 16_000
            samples += audio
            truth.append(Truth(text: word, start: start, end: Double(samples.count) / 16_000))
            let gap = word.hasSuffix(".") ? 0.6 : word.hasSuffix(",") ? 0.35 : 0.12
            samples += [Float](repeating: 0, count: Int(gap * 16_000))
        }
        samples += [Float](repeating: 0, count: 8000)
        return (samples, truth)
    }

    /// Frase emendada (natural) do AVSpeechSynthesizer, com o início de cada palavra: o delegate
    /// avisa a palavra enquanto o áudio é gerado, e a contagem de amostras até ali dá o tempo
    /// (com a precisão de um bloco de áudio, ~25 ms).
    @MainActor
    static func natural(_ sentence: String) async throws -> (samples: [Float], rate: Double, truth: [Truth]) {
        final class Collector: NSObject, AVSpeechSynthesizerDelegate {
            var samples: [Float] = []
            var rate = 22_050.0
            var truth: [Truth] = []
            var text = ""
            func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance: AVSpeechUtterance) {
                let word = (text as NSString).substring(with: r)
                truth.append(Truth(text: word, start: Double(samples.count) / rate, end: 0))
            }
        }
        let synth = AVSpeechSynthesizer()
        let collector = Collector()
        collector.text = sentence
        synth.delegate = collector
        let u = AVSpeechUtterance(string: sentence)
        u.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.pt-BR.Luciana")
            ?? AVSpeechSynthesisVoice(language: "pt-BR")
        var finished = false
        synth.write(u) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                finished = true
                return
            }
            collector.rate = pcm.format.sampleRate
            if let data = pcm.floatChannelData {
                collector.samples += UnsafeBufferPointer(start: data[0], count: Int(pcm.frameLength))
            } else if let data = pcm.int16ChannelData {
                collector.samples += UnsafeBufferPointer(start: data[0], count: Int(pcm.frameLength)).map { Float($0) / 32768 }
            }
        }
        let deadline = Date().addingTimeInterval(30)
        while !finished, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        // Meio segundo de silêncio antes e depois.
        let pad = [Float](repeating: 0, count: Int(collector.rate / 2))
        let truth = collector.truth.map { Truth(text: $0.text, start: $0.start + 0.5, end: 0) }
        return (pad + collector.samples + pad, collector.rate, truth)
    }

    /// Grava WAV mono.
    static func write(_ samples: [Float], rate: Double = 16_000) throws -> URL {
        let url = TestMedia.tempURL("wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        return url
    }

    static func normalize(_ s: String) -> [String] {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Taxa de erro de palavras (distância de edição / palavras da referência).
    static func wer(_ reference: String, _ hypothesis: String) -> Double {
        let r = normalize(reference)
        let h = normalize(hypothesis)
        var d = Array(0...h.count)
        for i in 1...max(r.count, 1) where !r.isEmpty {
            var prev = d[0]
            d[0] = i
            for j in stride(from: 1, through: h.count, by: 1) {
                let cur = d[j]
                d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] == h[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return Double(d[h.count]) / Double(max(r.count, 1))
    }

    /// Erro médio e máximo (s) do início e do fim das palavras que casam com a referência, na ordem.
    static func timingError(_ words: [TranscribedWord], truth: [Truth], offset: Double = 0, speed: Double = 1)
        -> (start: Double, end: Double, maxStart: Double, matched: Int) {
        var starts: [Double] = []
        var ends: [Double] = []
        var j = 0
        for t in truth {
            let key = normalize(t.text)
            guard let k = words[j...].firstIndex(where: { normalize($0.text) == key }) else { continue }
            let w = words[k]
            starts.append(abs(w.start.seconds - (offset + t.start / speed)))
            ends.append(abs(w.end.seconds - (offset + t.end / speed)))
            j = k + 1
        }
        let mean = { (xs: [Double]) in xs.isEmpty ? .infinity : xs.reduce(0, +) / Double(xs.count) }
        return (mean(starts), mean(ends), starts.max() ?? .infinity, starts.count)
    }

    /// Projeto com o áudio numa faixa de áudio.
    static func project(_ samples: [Float], rate: Double = 16_000, at start: Micros = 0,
                        speed: Double = 1) async throws -> (Project, UUID) {
        let m = try await MediaProbe.probe(write(samples, rate: rate))
        var p = Project()
        let id = TimelineEditor.addMedia(m, to: &p, at: start)
        if speed != 1 { TimelineEditor.setSpeed(&p, segment: id, speed: speed) }
        return (p, id)
    }

    static func transcribe(_ p: Project, source: TranscriptionSource = .timeline, language: String? = "pt",
                           timing: WhisperEngine.Timing = .dtw, refine: Bool = true, gpu: Bool = true,
                           model: WhisperModel = .base,
                           progress: @escaping @Sendable (TranscriptionProgress) -> Void = { _ in }) async throws -> [TranscribedWord] {
        var options = WhisperEngine.Options()
        options.language = language
        options.timing = timing
        options.refine = refine
        options.useGPU = gpu
        return try await Transcriber.transcribe(project: p, source: source, modelURL: modelURL(model)!, model: model,
                                                options: options, progress: progress)
    }
}

/// O whisper roda um de cada vez (um contexto só): a suíte é serial.
@Suite("Transcrição (whisper.cpp)", .serialized, .enabled(if: Speech.hasModel, Speech.skipMessage))
struct TranscriptionTests {
    let sentence = "Olá, pessoal. Hoje vamos testar as legendas automáticas do editor, direto no computador."

    @Test("Frase natural: texto parecido, tempos coerentes e progresso nas duas fases")
    func natural() async throws {
        let (p, _) = try await Speech.project(Speech.say(sentence), at: 2_000_000)
        let reports = Reports()
        let phases = PhaseLog()
        let words = try await Speech.transcribe(p) {
            reports.add($0.overall)
            phases.add($0.phase)
        }
        let text = words.map(\.text).joined(separator: " ")
        let wer = Speech.wer(sentence, text)
        print("Transcrição: \(text) | WER \(wer)")
        #expect(wer <= 0.25, "\(text)")
        #expect(words.first!.start >= 2_000_000)
        #expect(words.last!.end <= p.duration)
        for (a, b) in zip(words, words.dropFirst()) { #expect(a.start <= b.start) }
        #expect(words.allSatisfy { $0.end >= $0.start && (0...1).contains($0.probability) })
        #expect(phases.values == [.mixing, .transcribing])
        #expect(reports.values == reports.values.sorted() && reports.values.last == 1)
    }

    @Test("Tempos por palavra contra a referência do say (tokens e DTW)")
    func wordTiming() async throws {
        let (samples, truth) = try Speech.wordByWord(sentence)
        let (p, _) = try await Speech.project(samples)
        for (timing, refine) in [(WhisperEngine.Timing.tokens, false), (.dtw, false), (.tokens, true), (.dtw, true)] {
            let words = try await Speech.transcribe(p, timing: timing, refine: refine)
            if ProcessInfo.processInfo.environment["OPENFRAME_TIMING_DUMP"] == "1" {
                for w in words { print(timing, w.text, w.start.seconds, w.end.seconds) }
                for t in truth { print("truth", t.text, t.start, t.end) }
            }
            let e = Speech.timingError(words, truth: truth)
            print("Tempo \(timing)\(refine ? " + energia" : ""): início \(String(format: "%.3f", e.start)) s, fim \(String(format: "%.3f", e.end)) s, " +
                  "pior início \(String(format: "%.3f", e.maxStart)) s, \(e.matched)/\(truth.count) palavras")
            #expect(e.matched >= truth.count * 3 / 4)
            if timing == .dtw, refine {
                #expect(e.start < 0.2 && e.end < 0.3)
            }
        }
    }

    @Test("Fala emendada (AVSpeechSynthesizer): início das palavras")
    func naturalTiming() async throws {
        let text = "Olá, pessoal. Hoje vamos testar as legendas automáticas do editor, que rodam direto no computador."
        let (samples, rate, truth) = try await Speech.natural(text)
        #expect(truth.count >= 14)
        let (p, _) = try await Speech.project(samples, rate: rate)
        for refine in [false, true] {
            let words = try await Speech.transcribe(p, refine: refine, model: WhisperModel(rawValue: ProcessInfo.processInfo.environment["OPENFRAME_TEST_MODEL"] ?? "base")!)
            let e = Speech.timingError(words, truth: truth)
            print("Emendada\(refine ? " + energia" : ""): início \(String(format: "%.3f", e.start)) s, " +
                  "pior \(String(format: "%.3f", e.maxStart)) s, \(e.matched)/\(truth.count) palavras")
            if ProcessInfo.processInfo.environment["OPENFRAME_TIMING_DUMP"] == "1" {
                for w in words { print("emendada", refine, w.text, w.start.seconds, w.end.seconds) }
                for t in truth { print("truth", t.text, t.start) }
            }
            #expect(e.matched >= truth.count * 3 / 4)
            if refine { #expect(e.start < 0.18) }
        }
    }

    @Test("Com velocidade 2×, os tempos saem na timeline")
    func doubleSpeed() async throws {
        let (samples, truth) = try Speech.wordByWord(sentence)
        let (p, id) = try await Speech.project(samples, at: 1_000_000, speed: 2)
        #expect(p.segment(id)!.targetDuration < Micros(Double(samples.count) / 16_000 * 1_000_000 / 1.9))
        let words = try await Speech.transcribe(p)
        let e = Speech.timingError(words, truth: truth, offset: 1, speed: 2)
        print("2×: início \(e.start) s, \(e.matched)/\(truth.count) palavras")
        #expect(e.matched >= truth.count * 2 / 3)
        #expect(e.start < 0.2)
    }

    @Test("Fonte = clipe: só o áudio daquele segmento, com tempos da timeline")
    func clipSource() async throws {
        let (a, _) = try await Speech.project(Speech.say("Primeiro clipe com uma frase qualquer."))
        var p = a
        let other = try await MediaProbe.probe(Speech.write(Speech.say("Segundo trecho falando de bananas.")))
        // Numa faixa de áudio própria, muda: o clipe pedido é ouvido mesmo assim.
        var track = Track(kind: .audio)
        track.muted = true
        p.materials.append(other)
        var seg = Segment(materialId: other.id, source: TimeRange(start: 0, duration: other.duration), targetStart: 6_000_000)
        seg.volume = 0
        track.segments = [seg]
        p.tracks.append(track)
        let b = seg.id
        let words = try await Speech.transcribe(p, source: .segment(b))
        let text = words.map(\.text).joined(separator: " ")
        print("Clipe: \(text)")
        #expect(text.lowercased().contains("banana"))
        #expect(!text.lowercased().contains("primeiro"))
        #expect(words.allSatisfy { $0.start >= 6_000_000 })
        // A timeline inteira não ouve a faixa muda.
        let all = try await Speech.transcribe(p).map(\.text).joined(separator: " ").lowercased()
        #expect(all.contains("primeiro") && !all.contains("banana"))
    }

    @Test("Detecta o idioma e funciona só na CPU")
    func detectAndCPU() async throws {
        let (p, _) = try await Speech.project(Speech.say("Bom dia. Este teste roda sem a placa de vídeo."))
        let detected = try await Speech.transcribe(p, language: nil)
        #expect(Speech.wer("Bom dia. Este teste roda sem a placa de vídeo.", detected.map(\.text).joined(separator: " ")) <= 0.35)
        let cpu = try await Speech.transcribe(p, gpu: false)
        #expect(Speech.wer("Bom dia. Este teste roda sem a placa de vídeo.", cpu.map(\.text).joined(separator: " ")) <= 0.35)
    }

    @Test("Silêncio dá 'sem áudio'; o cancelamento para o whisper de verdade")
    func silenceAndCancel() async throws {
        let (silent, _) = try await Speech.project([Float](repeating: 0, count: 32_000))
        await #expect(throws: TranscriptionError.noAudio) { try await Speech.transcribe(silent) }

        var long: [Float] = []
        for _ in 0..<6 { long += try Speech.say(sentence) }
        let (p, _) = try await Speech.project(long)
        let started = Flag()
        let task = Task { try await Speech.transcribe(p) { if $0.phase == .transcribing { started.set() } } }
        while !started.isSet { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let clock = ContinuousClock()
        let t0 = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let waited = clock.now - t0
        print("Cancelamento em \(waited)")
        #expect(waited < .seconds(3))
    }
}

/// Medição (só com OPENFRAME_BENCH=1): 1 min de fala por modelo, GPU e CPU.
@Suite("Transcrição: medição", .serialized,
       .enabled(if: Speech.hasModel && ProcessInfo.processInfo.environment["OPENFRAME_BENCH"] == "1"))
struct TranscriptionBenchmark {
    @Test func oneMinutePerModel() async throws {
        let text = "Olá, pessoal. Hoje vamos testar as legendas automáticas do editor, que rodam direto no computador. " +
            "Você escolhe o idioma, a precisão e o estilo, e as legendas aparecem na timeline, prontas para editar."
        let (one, rate, truthOne) = try await Speech.natural(text)
        // Repete até passar de 60 s, com os tempos de referência deslocados.
        var samples: [Float] = []
        var truth: [Speech.Truth] = []
        var reference = ""
        while Double(samples.count) / rate < 60 {
            let offset = Double(samples.count) / rate
            truth += truthOne.map { Speech.Truth(text: $0.text, start: $0.start + offset, end: 0) }
            samples += one
            reference += text + " "
        }
        let (p, _) = try await Speech.project(samples, rate: rate)
        print("Áudio: \(String(format: "%.1f", Double(samples.count) / rate)) s")
        let only = ProcessInfo.processInfo.environment["OPENFRAME_TEST_MODEL"]
        for model in WhisperModel.allCases where Speech.modelURL(model) != nil && (only == nil || only == model.rawValue) {
            for gpu in [true, false] {
                WhisperEngine.shared.unload()
                let clock = ContinuousClock()
                var first: Duration = .zero
                var words: [TranscribedWord] = []
                for run in 0..<2 {
                    let t0 = clock.now
                    words = try await Speech.transcribe(p, gpu: gpu, model: model)
                    if run == 0 { first = clock.now - t0 } else { first = first + .zero }
                    if run == 1 {
                        let second = clock.now - t0
                        let wer = Speech.wer(reference, words.map(\.text).joined(separator: " "))
                        let e = Speech.timingError(words, truth: truth)
                        if ProcessInfo.processInfo.environment["OPENFRAME_TIMING_DUMP"] == "1" {
                            for w in words { print("bench", model.rawValue, w.text, w.start.seconds) }
                        }
                        print("MEDIÇÃO \(model.rawValue) \(gpu ? "GPU" : "CPU"): 1ª \(first), 2ª \(second), " +
                              "WER \(String(format: "%.3f", wer)), início \(String(format: "%.3f", e.start)) s")
                    }
                }
            }
        }
    }
}

final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [TranscriptionProgress.Phase] = []
    func add(_ p: TranscriptionProgress.Phase) {
        lock.lock()
        if list.last != p { list.append(p) }
        lock.unlock()
    }
    var values: [TranscriptionProgress.Phase] { lock.lock(); defer { lock.unlock() }; return list }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
