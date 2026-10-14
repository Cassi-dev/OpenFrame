import Foundation

public enum CaptionPresetGroup: String, CaseIterable, Sendable, Identifiable {
    case classic, reveal, editorial

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: "Clássicos"
        case .reveal: "Revelação"
        case .editorial: "Editorial"
        }
    }
}

/// Visuais prontos das legendas automáticas: a segmentação, o estilo, o destaque, a palavra-chave e as
/// animações de cada um.
public enum CaptionPreset: String, CaseIterable, Sendable, Identifiable {
    // Clássicos (os três primeiros visuais, iguais).
    case phrases, highlight, punch
    // Revelação pela fala.
    case rise, guided, fill, typing
    // Editorial e cinema.
    case editorial, cinema, stacked

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .phrases: "Frases"
        case .highlight: "Destaque"
        case .punch: "Impacto"
        case .rise: "Surgir"
        case .guided: "Leitura guiada"
        case .fill: "Preenchimento"
        case .typing: "Digitação"
        case .editorial: "Editorial"
        case .cinema: "Cinema"
        case .stacked: "Empilhado"
        }
    }

    /// Uma linha para o cartão da janela.
    public var detail: String {
        switch self {
        case .phrases: "Até duas linhas embaixo, como no cinema."
        case .highlight: "Uma linha; a palavra falada acende."
        case .punch: "Poucas palavras grandes no centro."
        case .rise: "Cada palavra surge quando é dita."
        case .guided: "A frase inteira, acendendo palavra por palavra."
        case .fill: "A cor enche cada palavra no ritmo da fala."
        case .typing: "As letras são digitadas no tempo da fala."
        case .editorial: "Texto leve, com a palavra-chave em serifa itálica."
        case .cinema: "Discreta: fina, espaçada e pequena, embaixo."
        case .stacked: "Blocos em caixa alta, justificados, linha a linha."
        }
    }

    public var group: CaptionPresetGroup {
        switch self {
        case .phrases, .highlight, .punch: .classic
        case .rise, .guided, .fill, .typing: .reveal
        case .editorial, .cinema, .stacked: .editorial
        }
    }

    /// A segmentação usada.
    public var layout: CaptionLayout {
        switch self {
        case .phrases, .guided, .editorial: .phrases
        case .highlight, .rise, .fill, .typing, .cinema: .highlight
        case .punch: .punch
        case .stacked: .stacked
        }
    }

    /// Se a cor de destaque escolhida na janela é usada: na palavra atual (Destaque, Surgir, Leitura guiada),
    /// no preenchimento, no cursor da digitação ou na palavra-chave (Editorial, Empilhado).
    public var usesAccent: Bool {
        switch self {
        case .phrases, .punch, .cinema: false
        default: true
        }
    }

    /// O visual clássico de cada segmentação (a API antiga por `CaptionLayout`).
    public init(_ layout: CaptionLayout) {
        switch layout {
        case .phrases: self = .phrases
        case .highlight: self = .highlight
        case .punch: self = .punch
        case .stacked: self = .stacked
        }
    }
}
