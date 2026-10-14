import CoreGraphics
import CoreImage

public struct RGBA: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
    public static let yellow = RGBA(1, 0.85, 0.1)

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public var ciColor: CIColor {
        CIColor(red: r, green: g, blue: b, alpha: a, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }
}

/// Posição, escala e rotação do clipe no canvas. `x`/`y` são normalizados
/// em -1...1 (centro = 0, `y` positivo para cima); `rotation` em graus.
public struct Transform: Codable, Hashable, Sendable {
    public var scale: Double = 1
    public var x: Double = 0
    public var y: Double = 0
    public var rotation: Double = 0

    public init() {}
}

/// Painel "Ajustar" do CapCut. Valores bipolares em -1...1, unipolares em 0...1.
public struct Adjust: Codable, Hashable, Sendable {
    public var brightness: Double = 0
    public var contrast: Double = 0
    public var saturation: Double = 0
    public var exposure: Double = 0
    public var temperature: Double = 0
    public var tint: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var hue: Double = 0
    public var sharpen: Double = 0
    public var vignette: Double = 0
    public var fade: Double = 0
    public var grain: Double = 0

    public init() {}

    public var isIdentity: Bool { self == Adjust() }
}

public enum FilterPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, vivid, warm, cool, cinematic, vintage, mono, noir, chrome, fade, instant, process, tonal, transfer, sepia

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "Nenhum"
        case .vivid: "Vívido"
        case .warm: "Quente"
        case .cool: "Frio"
        case .cinematic: "Cinema"
        case .vintage: "Vintage"
        case .mono: "Mono"
        case .noir: "Noir"
        case .chrome: "Cromo"
        case .fade: "Desbotado"
        case .instant: "Instantânea"
        case .process: "Processo"
        case .tonal: "Tonal"
        case .transfer: "Transferência"
        case .sepia: "Sépia"
        }
    }
}

public struct FilterSetting: Codable, Hashable, Sendable {
    public var preset: FilterPreset
    public var intensity: Double = 1

    public init(preset: FilterPreset, intensity: Double = 1) {
        self.preset = preset
        self.intensity = intensity
    }
}

public enum VideoEffectKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case blur, pixelate, rgbSplit, mirror, shake, flash, zoomPulse, kaleidoscope, comic, edges

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blur: "Desfoque"
        case .pixelate: "Pixelizar"
        case .rgbSplit: "Glitch RGB"
        case .mirror: "Espelho"
        case .shake: "Tremor"
        case .flash: "Flash"
        case .zoomPulse: "Pulso de zoom"
        case .kaleidoscope: "Caleidoscópio"
        case .comic: "Quadrinhos"
        case .edges: "Contornos neon"
        }
    }
}

public struct VideoEffect: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var kind: VideoEffectKind
    public var intensity: Double = 0.5

    public init(kind: VideoEffectKind, intensity: Double = 0.5) {
        self.kind = kind
        self.intensity = intensity
    }
}

public enum AnimationKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fade, zoomIn, zoomOut, slideLeft, slideRight, slideUp, slideDown, spin, typewriter
    case focus, cascade, elastic, wave, wordByWord, maskReveal, tracking, decode

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fade: "Esmaecer"
        case .zoomIn: "Zoom de aproximação"
        case .zoomOut: "Zoom de afastamento"
        case .slideLeft: "Deslizar ←"
        case .slideRight: "Deslizar →"
        case .slideUp: "Deslizar ↑"
        case .slideDown: "Deslizar ↓"
        case .spin: "Girar"
        case .typewriter: "Máquina de escrever"
        case .focus: "Foco"
        case .cascade: "Cascata"
        case .elastic: "Elástico"
        case .wave: "Onda"
        case .wordByWord: "Palavra a palavra"
        case .maskReveal: "Revelar por máscara"
        case .tracking: "Espaçamento"
        case .decode: "Decodificar"
        }
    }

    /// Animações que só fazem sentido em texto.
    public var textOnly: Bool {
        switch self {
        case .typewriter, .cascade, .elastic, .wave, .wordByWord, .maskReveal, .tracking, .decode: true
        default: false
        }
    }
}

public struct SegmentAnimation: Codable, Hashable, Sendable {
    public var kind: AnimationKind
    public var duration: Micros = 500_000

    public init(kind: AnimationKind, duration: Micros = 500_000) {
        self.kind = kind
        self.duration = duration
    }
}

/// Animação contínua que roda o clipe inteiro, somada à entrada e à saída.
public enum LoopKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case float, pulse, glow, shine

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .float: "Flutuar"
        case .pulse: "Pulsar"
        case .glow: "Respirar brilho"
        case .shine: "Reflexo de luz"
        }
    }
}

public struct LoopAnimation: Codable, Hashable, Sendable {
    public var kind: LoopKind
    /// Duração de um ciclo.
    public var period: Micros = 2_000_000
    /// 0...1.
    public var intensity: Double = 0.5

    public init(kind: LoopKind, period: Micros = 2_000_000, intensity: Double = 0.5) {
        self.kind = kind
        self.period = period
        self.intensity = intensity
    }
}

public enum TransitionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dissolve, fadeBlack, fadeWhite, wipeLeft, wipeRight, slideLeft, slideRight, zoom, blur

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dissolve: "Dissolver"
        case .fadeBlack: "Escurecer"
        case .fadeWhite: "Clarear"
        case .wipeLeft: "Cortina ←"
        case .wipeRight: "Cortina →"
        case .slideLeft: "Empurrar ←"
        case .slideRight: "Empurrar →"
        case .zoom: "Zoom"
        case .blur: "Desfoque"
        }
    }
}

/// Transição entre este segmento e o próximo da mesma faixa.
public struct Transition: Codable, Hashable, Sendable {
    public var kind: TransitionKind
    public var duration: Micros = 500_000

    public init(kind: TransitionKind, duration: Micros = 500_000) {
        self.kind = kind
        self.duration = duration
    }
}

public enum TextAlignmentKind: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

/// Caixa das letras aplicada na hora de desenhar; o texto guardado não muda.
public enum TextCase: String, Codable, CaseIterable, Sendable {
    case none, upper, lower, title
}

/// Estilo de um texto. Medidas tipográficas (espaçamentos, sombra, margens e
/// raio do fundo) são frações do tamanho da fonte (em), como no CapCut, para
/// acompanhar o tamanho e a resolução.
public struct TextStyle: Codable, Hashable, Sendable {
    public var fontName = "Helvetica Neue"
    /// Estilo dentro da família ("Light", "Medium"…); vazio = estilo normal.
    public var fontFace = ""
    /// Tamanho como fração da altura do canvas, para independer da resolução.
    public var fontSize: Double = 0.07
    public var bold = true
    public var italic = false
    public var underline = false
    public var textCase = TextCase.none
    public var color = RGBA.white
    /// Opacidade do texto inteiro (letras, contorno, fundo e sombra).
    public var opacity: Double = 1
    public var strokeColor = RGBA.black
    /// Espessura do contorno em % do tamanho da fonte (0 = sem contorno).
    /// Metade dela fica para fora da letra, como no traço centrado anterior.
    public var strokeWidth: Double = 0
    /// Espaço extra entre letras, em em.
    public var letterSpacing: Double = 0
    /// Espaço extra entre linhas, em em (negativo aproxima as linhas).
    public var lineSpacing: Double = 0
    public var backgroundEnabled = false
    /// A opacidade do fundo é o alfa desta cor.
    public var backgroundColor = RGBA(0, 0, 0, 0.6)
    public var backgroundRadius: Double = 0.18
    public var backgroundPaddingX: Double = 0.21
    public var backgroundPaddingY: Double = 0.21
    public var shadow = true
    /// A opacidade da sombra é o alfa desta cor.
    public var shadowColor = RGBA(0, 0, 0, 0.65)
    public var shadowDistance: Double = 0.04
    /// Direção da sombra em graus: 0 = direita, 90 = cima, -90 = baixo.
    public var shadowAngle: Double = -90
    public var shadowBlur: Double = 0.15
    public var alignment = TextAlignmentKind.center
    public var x: Double = 0
    public var y: Double = -0.7
    public var scale: Double = 1
    public var rotation: Double = 0
    /// Largura máxima da caixa como fração da largura do canvas.
    public var maxWidth: Double = 0.9

    public init() {}

    /// Campos ausentes (projetos salvos por versões anteriores) ficam com o padrão.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TextStyle()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        fontName = try value(.fontName, d.fontName)
        fontFace = try value(.fontFace, d.fontFace)
        fontSize = try value(.fontSize, d.fontSize)
        bold = try value(.bold, d.bold)
        italic = try value(.italic, d.italic)
        underline = try value(.underline, d.underline)
        textCase = try value(.textCase, d.textCase)
        color = try value(.color, d.color)
        opacity = try value(.opacity, d.opacity)
        strokeColor = try value(.strokeColor, d.strokeColor)
        strokeWidth = try value(.strokeWidth, d.strokeWidth)
        letterSpacing = try value(.letterSpacing, d.letterSpacing)
        lineSpacing = try value(.lineSpacing, d.lineSpacing)
        backgroundEnabled = try value(.backgroundEnabled, d.backgroundEnabled)
        backgroundColor = try value(.backgroundColor, d.backgroundColor)
        backgroundRadius = try value(.backgroundRadius, d.backgroundRadius)
        backgroundPaddingX = try value(.backgroundPaddingX, d.backgroundPaddingX)
        backgroundPaddingY = try value(.backgroundPaddingY, d.backgroundPaddingY)
        shadow = try value(.shadow, d.shadow)
        shadowColor = try value(.shadowColor, d.shadowColor)
        shadowDistance = try value(.shadowDistance, d.shadowDistance)
        shadowAngle = try value(.shadowAngle, d.shadowAngle)
        shadowBlur = try value(.shadowBlur, d.shadowBlur)
        alignment = try value(.alignment, d.alignment)
        x = try value(.x, d.x)
        y = try value(.y, d.y)
        scale = try value(.scale, d.scale)
        rotation = try value(.rotation, d.rotation)
        maxWidth = try value(.maxWidth, d.maxWidth)
    }
}

public struct TextContent: Codable, Hashable, Sendable {
    public var text: String
    public var style: TextStyle

    public init(text: String, style: TextStyle = TextStyle()) {
        self.text = text
        self.style = style
    }
}
