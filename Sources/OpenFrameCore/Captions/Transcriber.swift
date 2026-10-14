import Foundation

/// Palavra reconhecida, com tempos da timeline.
public struct TranscribedWord: Hashable, Sendable {
    public var text: String
    public var start: Micros
    public var end: Micros
    public var probability: Double

    public init(text: String, start: Micros, end: Micros, probability: Double = 1) {
        self.text = text
        self.start = start
        self.end = end
        self.probability = probability
    }
}

/// Progresso da transcrição: a fase, quanto dela já foi e o total (mistura ~10%, transcrição ~90%).
public struct TranscriptionProgress: Sendable, Hashable {
    public enum Phase: Sendable, Hashable { case mixing, transcribing }
    public var phase: Phase
    /// 0...1 dentro da fase.
    public var fraction: Double
    /// 0...1 no total.
    public var overall: Double

    public init(phase: Phase, fraction: Double) {
        self.phase = phase
        self.fraction = min(max(fraction, 0), 1)
        overall = phase == .mixing ? Self.mixingWeight * self.fraction
            : Self.mixingWeight + (1 - Self.mixingWeight) * self.fraction
    }

    /// Peso da mistura no total.
    public static let mixingWeight = 0.1
}

public enum TranscriptionSource: Sendable, Hashable {
    case timeline
    case segment(UUID)
}

public enum TranscriptionError: LocalizedError, Equatable {
    case engineUnavailable
    case modelNotInstalled(WhisperModel)
    case noAudio
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable: "O motor de transcrição ainda não foi integrado a esta versão."
        case .modelNotInstalled(let m): "O modelo \(m.displayName) não está instalado. Baixe-o antes de gerar."
        case .noAudio: "Não há áudio para transcrever nesse trecho."
        case .failed(let message): "A transcrição falhou: \(message)"
        }
    }
}

public enum Transcriber {
    /// Mistura o áudio como a exportação ouve (volume, mudo, velocidade, fades, faixas de áudio), converte para
    /// 16 kHz mono, transcreve e devolve palavras com tempos na timeline. `language` nil = detectar.
    /// Progresso por fase (mistura e transcrição) e no total. Cancelável por Task.
    ///
    /// Com `OPENFRAME_FAKE_TRANSCRIPTION=1`, devolve palavras falsas espalhadas pelo trecho (capturas de tela).
    public static func transcribe(project: Project, source: TranscriptionSource, model: WhisperModel,
                                  language: String?, progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> [TranscribedWord] {
        let range = try sourceRange(project: project, source: source)
        if ProcessInfo.processInfo.environment["OPENFRAME_FAKE_TRANSCRIPTION"] == "1" {
            return try await fakeWords(in: range, progress: progress)
        }
        throw TranscriptionError.engineUnavailable
    }

    /// Idiomas oferecidos (códigos do Whisper), com os nomes em português.
    public static let languages: [(code: String, name: String)] = [
        ("pt", "Português"), ("en", "Inglês"), ("es", "Espanhol"), ("fr", "Francês"), ("de", "Alemão"),
        ("it", "Italiano"), ("ja", "Japonês"), ("ko", "Coreano"), ("zh", "Chinês"), ("ru", "Russo"),
        ("ar", "Árabe"), ("hi", "Hindi"), ("nl", "Holandês"), ("pl", "Polonês"), ("tr", "Turco"),
        ("uk", "Ucraniano"), ("sv", "Sueco"), ("he", "Hebraico"), ("id", "Indonésio"), ("vi", "Vietnamita"),
    ]

    /// Trecho da timeline a transcrever: o projeto inteiro ou o segmento (é o `range` do
    /// `CaptionBuilder.apply` ao substituir).
    public static func sourceRange(project: Project, source: TranscriptionSource) throws -> TimeRange {
        switch source {
        case .timeline:
            guard project.duration > 0 else { throw TranscriptionError.noAudio }
            return TimeRange(start: 0, duration: project.duration)
        case .segment(let id):
            guard let seg = project.segment(id), let m = project.material(seg.materialId), m.hasAudio else {
                throw TranscriptionError.noAudio
            }
            return seg.targetRange
        }
    }

    static let fakeText = """
    Olá, pessoal! Hoje eu vou mostrar como gerar legendas automáticas no OpenFrame. \
    É tudo feito no seu Mac, sem enviar nada para a internet. \
    Você escolhe o estilo, o idioma e a precisão, e pronto.
    """

    /// Palavras falsas a ~2,6 por segundo, com pausas nas pontuações, repetindo o texto até o fim do trecho.
    static func fakeWords(in range: TimeRange, progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> [TranscribedWord] {
        let tokens = fakeText.split(separator: " ").map(String.init)
        var words: [TranscribedWord] = []
        var t = range.start + 300_000
        var k = 0
        while t < range.end - 200_000 {
            let text = tokens[k % tokens.count]
            let length = Micros(180_000 + 45_000 * min(text.count, 10))
            let end = min(t + length, range.end)
            words.append(TranscribedWord(text: text, start: t, end: end, probability: 0.9))
            t = end + (CaptionBuilder.endsSentence(text) ? 450_000 : text.hasSuffix(",") ? 250_000 : 60_000)
            k += 1
        }
        for step in 1...3 {
            try await Task.sleep(nanoseconds: 60_000_000)
            progress(TranscriptionProgress(phase: .mixing, fraction: Double(step) / 3))
        }
        for step in 1...10 {
            try await Task.sleep(nanoseconds: 60_000_000)
            progress(TranscriptionProgress(phase: .transcribing, fraction: Double(step) / 10))
        }
        return words
    }
}
