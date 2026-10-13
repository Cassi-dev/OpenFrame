import AppKit
import OpenFrameCore
import SwiftUI

/// O SwiftUI também declara `Material`; no app, o nome se refere ao nosso.
typealias Material = OpenFrameCore.Material

/// Sistema visual: preto puro, cinzas neutros e um único destaque ciano
/// (o "Playhead Cyan" da marca), usado só no que está ativo.
enum Theme {
    // Superfícies, do fundo para cima.
    static let background = Color.black
    static let surface = Color(white: 0.043)        // #0B0B0B, painéis
    static let raised = Color(white: 0.082)         // #151515, campos e clipes
    static let raisedHigh = Color(white: 0.125)     // #202020, hover e seleção
    static let hairline = Color.white.opacity(0.07)

    // Texto.
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)

    // Destaque.
    static let accent = Color(red: 0, green: 194 / 255, blue: 204 / 255) // #00C2CC
    static let accentSoft = accent.opacity(0.14)
    static let onAccent = Color.black

    // Clipes: tons de cinza; o ícone diz o tipo.
    static let clipVideo = Color(white: 0.15)
    static let clipText = Color(white: 0.19)
    static let clipAudio = Color(white: 0.10)
    static let waveform = Color.white.opacity(0.32)

    // Raios.
    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let fieldRadius: CGFloat = 8

    /// SF Pro, só entre os pesos 200 e 500.
    enum Weight {
        case thin, light, regular, medium
        var value: Font.Weight {
            switch self {
            case .thin: .thin
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            }
        }
    }

    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight.value)
    }

    /// Números de tempo: dígitos de largura fixa.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight.value).monospacedDigit()
    }
}

extension View {
    /// Painel flutuante sobre o fundo preto.
    func panel(radius: CGFloat = Theme.panelRadius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Campo elevado (entradas, menus, cartões).
    func field(radius: CGFloat = Theme.fieldRadius) -> some View {
        background(Theme.raised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

extension RGBA {
    var color: Color { Color(cgColor: cgColor) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}

extension Micros {
    var shortSeconds: String { String(format: "%.1fs", seconds) }
}

// MARK: - Botões

/// Botão redondo só com ícone.
struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, size: size, prominent: prominent)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let size: CGFloat
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.font(size * 0.42, prominent ? .medium : .regular))
                .foregroundStyle(prominent ? Theme.onAccent : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .frame(width: size, height: size)
                .background(prominent ? AnyShapeStyle(Theme.accent)
                                      : AnyShapeStyle(hovering ? Theme.raisedHigh : Theme.raised), in: Circle())
                .overlay(Circle().strokeBorder(prominent ? .clear : Theme.hairline))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

/// Pílula com texto: `primary` é o único botão preenchido de ciano.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind = Kind.secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind, compact: compact)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.font(compact ? 11 : 12, .medium))
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 14)
                .frame(height: compact ? 24 : 30)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(kind == .secondary ? Theme.hairline : .clear))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onAccent
            case .secondary: Theme.textPrimary
            case .quiet: hovering ? Theme.textPrimary : Theme.textSecondary
            }
        }

        private var background: AnyShapeStyle {
            switch kind {
            case .primary: AnyShapeStyle(hovering ? Theme.accent.opacity(0.88) : Theme.accent)
            case .secondary: AnyShapeStyle(hovering ? Theme.raisedHigh : Theme.raised)
            case .quiet: AnyShapeStyle(hovering ? Theme.raised : Color.clear)
            }
        }
    }
}

/// Ícone simples, sem fundo, que acende no hover.
struct GlyphButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, active: active)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let active: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(active ? Theme.accent : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Controles de formulário

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionTitle = "Redefinir"

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.font(12, .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GlyphButtonStyle())
                    .font(Theme.font(11))
            }
        }
        .padding(.top, 10)
    }
}

/// Linha "rótulo → controle", como nos formulários da referência.
struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Menu com a aparência de um campo: valor atual e uma seta.
struct MenuField<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(title(selection))
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(Theme.font(9, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .field()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// Grupo de opções em pílula; a escolhida fica elevada.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var icon: ((Value) -> String)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Group {
                        if let icon {
                            Image(systemName: icon(option)).help(title(option))
                        } else {
                            Text(title(option)).lineLimit(1)
                        }
                    }
                    .font(Theme.font(11, selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(selected ? Theme.raisedHigh : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// Interruptor com rótulo, no ciano da marca.
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(Theme.font(12)).foregroundStyle(Theme.textSecondary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.accent)
    }
}

/// Seletor de cor como linha de formulário.
struct ColorRow: View {
    let title: String
    @Binding var color: Color

    var body: some View {
        FieldRow(label: title) {
            ColorPicker("", selection: $color)
                .labelsHidden()
        }
    }
}

/// Slider com rótulo e valor; duplo clique no rótulo redefine.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var defaultValue: Double = 0
    var format: (Double) -> String = { String(format: "%.0f", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(value == defaultValue ? Theme.textTertiary : Theme.textPrimary)
            }
            .font(Theme.font(12))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { value = defaultValue }
            .help("Clique duas vezes para redefinir")
            ThinSlider(value: $value, range: range)
        }
    }
}

/// Trilho fino com preenchimento ciano a partir do zero (ou do mínimo).
struct ThinSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var dragging = false
    @State private var hovering = false

    private var origin: Double {
        range.lowerBound < 0 && range.upperBound > 0 ? 0 : range.lowerBound
    }

    private func fraction(_ v: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        return CGFloat((min(max(v, range.lowerBound), range.upperBound) - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = fraction(value) * width
            let o = fraction(origin) * width
            let knob: CGFloat = dragging ? 13 : 11
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10)).frame(height: 3)
                Capsule().fill(Theme.accent)
                    .frame(width: abs(x - o), height: 3)
                    .offset(x: min(x, o))
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .scaleEffect(hovering || dragging ? 1 : 0.85)
                    .offset(x: min(max(x - knob / 2, 0), width - knob))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    dragging = true
                    let f = min(max(g.location.x / max(width, 1), 0), 1)
                    value = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                }
                .onEnded { _ in dragging = false })
            .animation(.easeOut(duration: 0.12), value: dragging)
        }
        .frame(height: 16)
    }
}

// MARK: - Marca

/// O símbolo do OpenFrame (moldura aberta pela agulha), desenhado a partir
/// da geometria de `assets/brand/symbol` (caixa de 256 × 256).
struct LogoMark: View {
    var frameColor = Theme.textPrimary
    var needleColor = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 256
            ctx.translateBy(x: (size.width - 256 * s) / 2, y: (size.height - 256 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            var ring = Path(roundedRect: CGRect(x: 30, y: 60, width: 196, height: 136), cornerRadius: 36)
            ring.addPath(Path(roundedRect: CGRect(x: 54, y: 84, width: 148, height: 88), cornerRadius: 12))
            var left = ctx
            left.clip(to: Path(CGRect(x: 0, y: 0, width: 130, height: 256)))
            left.fill(ring, with: .color(frameColor), style: FillStyle(eoFill: true))
            var right = ctx
            right.clip(to: Path(CGRect(x: 170, y: 0, width: 86, height: 256)))
            right.fill(ring, with: .color(frameColor), style: FillStyle(eoFill: true))
            ctx.fill(NeedleShape.needle, with: .color(needleColor))
        }
    }
}

/// A agulha da logo, também usada como cabeça do playhead.
enum NeedleShape {
    static var needle: Path {
        var p = Path()
        p.move(to: CGPoint(x: 140, y: 26))
        p.addLine(to: CGPoint(x: 160, y: 26))
        p.addArc(tangent1End: CGPoint(x: 166, y: 26), tangent2End: CGPoint(x: 166, y: 32), radius: 6)
        p.addLine(to: CGPoint(x: 166, y: 46))
        p.addLine(to: CGPoint(x: 158, y: 56))
        p.addLine(to: CGPoint(x: 158, y: 222))
        p.addArc(tangent1End: CGPoint(x: 158, y: 230), tangent2End: CGPoint(x: 150, y: 230), radius: 8)
        p.addArc(tangent1End: CGPoint(x: 142, y: 230), tangent2End: CGPoint(x: 142, y: 222), radius: 8)
        p.addLine(to: CGPoint(x: 142, y: 56))
        p.addLine(to: CGPoint(x: 134, y: 46))
        p.addLine(to: CGPoint(x: 134, y: 32))
        p.addArc(tangent1End: CGPoint(x: 134, y: 26), tangent2End: CGPoint(x: 140, y: 26), radius: 6)
        p.closeSubpath()
        return p
    }
}

/// Cabeça da agulha com largura livre: bloco de topo arredondado que afunila
/// até a espessura da linha. Serve de balão de tempo do playhead.
struct NeedleHead: Shape {
    var taper: CGFloat = 5
    var line: CGFloat = 1.5

    func path(in r: CGRect) -> Path {
        let body = r.height - taper
        let radius = min(5, body / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + radius), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + body - radius))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY + body), tangent2End: CGPoint(x: r.maxX - radius, y: r.minY + body), radius: radius)
        p.addLine(to: CGPoint(x: r.midX + line / 2 + taper, y: r.minY + body))
        p.addLine(to: CGPoint(x: r.midX + line / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - line / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - line / 2 - taper, y: r.minY + body))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.minY + body))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY + body), tangent2End: CGPoint(x: r.minX, y: r.minY + body - radius), radius: radius)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + radius, y: r.minY), radius: radius)
        p.closeSubpath()
        return p
    }
}

// MARK: - Janela

/// Área que arrasta a janela (a barra de título do sistema fica oculta).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// Ajusta a NSWindow: fundo preto, barra de título transparente e os botões
/// de fechar/minimizar/zoom centralizados na altura da barra superior.
struct WindowConfigurator: NSViewRepresentable {
    var barHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(barHeight: barHeight) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { context.coordinator.attach(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let barHeight: CGFloat
        private var observers: [NSObjectProtocol] = []

        init(barHeight: CGFloat) { self.barHeight = barHeight }

        func attach(_ window: NSWindow) {
            window.backgroundColor = .black
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            layoutButtons(window)
            let names = [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didExitFullScreenNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        if let window { self?.layoutButtons(window) }
                    }
                })
            }
        }

        /// O AppKit recoloca os botões ao redimensionar; por isso roda de novo a cada mudança.
        private func layoutButtons(_ window: NSWindow) {
            guard !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let container = close.superview?.superview else { return }
            var frame = container.frame
            frame.size.height = barHeight
            frame.origin.y = window.frame.height - barHeight
            container.frame = frame
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let size = button.frame.size
                button.setFrameOrigin(NSPoint(x: 18 + CGFloat(index) * 20, y: (barHeight - size.height) / 2))
            }
        }
    }
}
