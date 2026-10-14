import Foundation

/// Tempo de cada palavra de uma legenda, relativo ao início do segmento.
public struct CaptionWord: Codable, Hashable, Sendable {
    public var text: String
    public var start: Micros
    public var end: Micros

    public init(text: String, start: Micros, end: Micros) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public enum HighlightMode: String, Codable, CaseIterable, Sendable {
    /// Só a palavra falada agora.
    case current
    /// As palavras já faladas ficam destacadas.
    case progressive
}

/// Destaque da palavra falada ("karaokê") num texto com `words`.
public struct WordHighlight: Codable, Hashable, Sendable {
    /// Cor da palavra destacada.
    public var color = RGBA.yellow
    /// 1 = sem crescer.
    public var scale: Double = 1.12
    /// "Pílula" atrás da palavra.
    public var backgroundEnabled = false
    public var backgroundColor = RGBA(0.1, 0.45, 1, 1)
    public var mode = HighlightMode.current

    public init() {}

    /// Campos ausentes ficam com o padrão.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WordHighlight()
        color = try c.decodeIfPresent(RGBA.self, forKey: .color) ?? d.color
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        backgroundEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? d.backgroundEnabled
        backgroundColor = try c.decodeIfPresent(RGBA.self, forKey: .backgroundColor) ?? d.backgroundColor
        // Modo desconhecido (versão futura) vira o padrão em vez de impedir a abertura.
        mode = (try? c.decodeIfPresent(HighlightMode.self, forKey: .mode)) ?? d.mode
    }
}

extension TextContent {
    /// Palavras do texto, separadas por espaço ou quebra de linha (a mesma divisão do destaque).
    public static func words(of text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    /// O destaque vale quando há tempos para cada palavra do texto. Se o usuário editou o texto
    /// e a contagem não bate, o destaque é ignorado (sem erro).
    public var activeHighlight: (words: [CaptionWord], style: WordHighlight)? {
        guard let words, let highlight, !words.isEmpty, Self.words(of: text).count == words.count else { return nil }
        return (words, highlight)
    }
}
