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

/// Como as palavras aparecem conforme são ditas (junto com o destaque).
public enum WordReveal: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Todas visíveis desde o início da legenda.
    case none
    /// Surgir: cada palavra aparece quando é dita (sobe um pouco, de desfocada e transparente a nítida e
    /// opaca). O espaço das que ainda não foram ditas fica reservado.
    case rise
    /// Leitura guiada: as não ditas ficam com `dimOpacity`; cada uma acende ao ser dita.
    case dim
    /// Preenchimento: a cor do destaque enche a palavra da esquerda para a direita, ao longo da duração dela.
    case fill
    /// Digitação: as letras aparecem distribuídas no tempo da palavra, com um cursor na cor do destaque.
    case type

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "Nenhuma"
        case .rise: "Surgir"
        case .dim: "Leitura guiada"
        case .fill: "Preenchimento"
        case .type: "Digitação"
        }
    }
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
    /// Revelação pela fala. No preenchimento e na digitação, a cor vai para o preenchimento e para o
    /// cursor; a escala e a pílula continuam valendo em todas.
    public var reveal = WordReveal.none
    /// Opacidade das palavras ainda não ditas na leitura guiada.
    public var dimOpacity: Double = 0.35

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
        reveal = (try? c.decodeIfPresent(WordReveal.self, forKey: .reveal)) ?? d.reveal
        dimOpacity = try c.decodeIfPresent(Double.self, forKey: .dimOpacity) ?? d.dimOpacity
    }
}

/// Palavra-chave (visual Editorial): algumas palavras em outra fonte, maiores e numa cor própria.
public struct WordEmphasis: Codable, Hashable, Sendable {
    /// Índices das palavras enfatizadas (a divisão de `TextContent.words(of:)`). Os fora do texto são ignorados.
    public var words: [Int] = []
    /// Serifa presente em todo macOS.
    public var fontName = "Didot"
    public var fontFace = "Italic"
    /// Relativo ao tamanho do texto.
    public var scale: Double = 1.3
    /// `nil` = a cor do texto.
    public var color: RGBA?

    public init(words: [Int] = []) {
        self.words = words
    }

    /// Campos ausentes ficam com o padrão.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WordEmphasis()
        words = try c.decodeIfPresent([Int].self, forKey: .words) ?? d.words
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        fontFace = try c.decodeIfPresent(String.self, forKey: .fontFace) ?? d.fontFace
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        color = try c.decodeIfPresent(RGBA.self, forKey: .color)
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
