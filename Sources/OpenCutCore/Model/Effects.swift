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
        }
    }

    /// Animações que só fazem sentido em texto.
    public var textOnly: Bool { self == .typewriter }
}

public struct SegmentAnimation: Codable, Hashable, Sendable {
    public var kind: AnimationKind
    public var duration: Micros = 500_000

    public init(kind: AnimationKind, duration: Micros = 500_000) {
        self.kind = kind
        self.duration = duration
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

public struct TextStyle: Codable, Hashable, Sendable {
    public var fontName = "Helvetica Neue"
    /// Tamanho como fração da altura do canvas, para independer da resolução.
    public var fontSize: Double = 0.07
    public var bold = true
    public var italic = false
    public var color = RGBA.white
    public var strokeColor = RGBA.black
    /// Espessura do contorno em % do tamanho da fonte (0 = sem contorno).
    public var strokeWidth: Double = 0
    public var backgroundEnabled = false
    public var backgroundColor = RGBA(0, 0, 0, 0.6)
    public var shadow = true
    public var alignment = TextAlignmentKind.center
    public var x: Double = 0
    public var y: Double = -0.7
    public var scale: Double = 1
    public var rotation: Double = 0
    /// Largura máxima da caixa como fração da largura do canvas.
    public var maxWidth: Double = 0.9

    public init() {}
}

public struct TextContent: Codable, Hashable, Sendable {
    public var text: String
    public var style: TextStyle

    public init(text: String, style: TextStyle = TextStyle()) {
        self.text = text
        self.style = style
    }
}
