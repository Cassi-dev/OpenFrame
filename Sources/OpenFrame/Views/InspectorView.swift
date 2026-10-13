import OpenFrameCore
import SwiftUI

struct InspectorView: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Group {
            if let seg = model.selectedSegment {
                SegmentInspector(segment: seg)
                    .id(seg.id)
            } else {
                ProjectInspector()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Helpers de binding

private func seconds(_ b: Binding<Micros>) -> Binding<Double> {
    Binding(get: { b.wrappedValue.seconds }, set: { b.wrappedValue = Time.seconds($0) })
}

private func color(_ b: Binding<RGBA>) -> Binding<Color> {
    Binding(get: { b.wrappedValue.color }, set: { b.wrappedValue = RGBA($0) })
}

private let percent: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }
private let signedPercent: (Double) -> String = { String(format: "%+.0f", $0 * 100) }
private let secondsFormat: (Double) -> String = { String(format: "%.1fs", $0) }

/// Cartão selecionável usado nas grades de filtros, efeitos e transições.
private struct ChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview()
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : (hovering ? Color.white.opacity(0.22) : Theme.hairline),
                                      lineWidth: selected ? 1.5 : 1))
                Text(title)
                    .font(Theme.font(11, selected ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Theme.accent : (hovering ? Theme.textPrimary : Theme.textSecondary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private let tileColumns = [GridItem(.adaptive(minimum: 80), spacing: 8)]

/// Campo de texto de uma linha com a aparência dos campos do tema.
private struct InputField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.font(12))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .field()
    }
}

// MARK: - Segmento

private struct SegmentInspector: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    var body: some View {
        let tabs = model.availableTabs(for: segment)
        let current = tabs.contains(model.inspectorTab) ? model.inspectorTab : (tabs.first ?? .basic)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top], 14)
            if tabs.count > 1 {
                PillPicker(selection: Binding(get: { current }, set: { model.inspectorTab = $0 }),
                           options: tabs, title: \.title, icon: \.icon)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }
            Text(current.title)
                .font(Theme.font(16, .light))
                .padding(.horizontal, 14)
                .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch current {
                    case .basic: BasicTab(segment: segment)
                    case .adjust: AdjustTab(id: segment.id)
                    case .filters: FiltersTab(segment: segment)
                    case .effects: EffectsTab(segment: segment)
                    case .animation: AnimationTab(segment: segment)
                    case .transition: TransitionTab(segment: segment)
                    case .text: TextTab(id: segment.id)
                    case .audio: AudioTab(segment: segment)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
    }

    /// Ícone do tipo, nome e intervalo na timeline.
    private var header: some View {
        let material = model.project.material(segment.materialId)
        let icon = segment.text != nil ? "textformat"
            : material?.kind == .audio ? "music.note" : material?.kind == .photo ? "photo" : "film"
        let name = segment.text.map { $0.text.replacingOccurrences(of: "\n", with: " ") } ?? material?.name ?? "Clipe"
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.font(12, .light))
                .frame(width: 30, height: 30)
                .field(radius: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.font(13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(Time.format(segment.targetStart)) – \(Time.format(segment.targetEnd)) · \(segment.targetDuration.shortSeconds)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Button { model.selection = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(CircleButtonStyle(size: 24))
                .help("Fechar (mostra o projeto)")
        }
    }
}

private struct BasicTab: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    var body: some View {
        let id = segment.id
        SectionHeader(title: "Transformar") {
            model.mutate { TimelineEditor.update(&$0, segment: id) { $0.transform = Transform(); $0.opacity = 1 } }
        }
        ParamSlider(title: "Escala", value: model.binding(id, \.transform.scale), range: 0.1...4, defaultValue: 1, format: percent)
        ParamSlider(title: "Posição X", value: model.binding(id, \.transform.x), format: signedPercent)
        ParamSlider(title: "Posição Y", value: model.binding(id, \.transform.y), format: signedPercent)
        ParamSlider(title: "Rotação", value: model.binding(id, \.transform.rotation), range: -180...180,
                    format: { String(format: "%.0f°", $0) })
        ParamSlider(title: "Opacidade", value: model.binding(id, \.opacity), range: 0...1, defaultValue: 1, format: percent)

        SectionHeader(title: "Velocidade")
        SpeedPresets(id: id, speed: segment.speed)
        ParamSlider(title: "Velocidade", value: model.binding(id, \.speed), range: 0.1...4, defaultValue: 1,
                    format: { String(format: "%.2fx", $0) })

        if model.project.material(segment.materialId)?.hasAudio == true {
            AudioControls(id: id)
        }
    }
}

private struct SpeedPresets: View {
    @Environment(EditorModel.self) private var model
    let id: UUID
    let speed: Double

    var body: some View {
        PillPicker(selection: Binding(get: { speed }, set: { s in
            model.mutate { TimelineEditor.setSpeed(&$0, segment: id, speed: s) }
        }), options: [0.5, 1, 1.5, 2, 3], title: { String(format: "%gx", $0) })
    }
}

private struct AudioControls: View {
    @Environment(EditorModel.self) private var model
    let id: UUID

    var body: some View {
        SectionHeader(title: "Som")
        ParamSlider(title: "Volume", value: model.binding(id, \.volume), range: 0...1, defaultValue: 1, format: percent)
        ParamSlider(title: "Fade de entrada", value: seconds(model.binding(id, \.fadeIn)), range: 0...5, format: secondsFormat)
        ParamSlider(title: "Fade de saída", value: seconds(model.binding(id, \.fadeOut)), range: 0...5, format: secondsFormat)
    }
}

private struct AudioTab: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    var body: some View {
        AudioControls(id: segment.id)
        SectionHeader(title: "Velocidade")
        SpeedPresets(id: segment.id, speed: segment.speed)
        ParamSlider(title: "Velocidade", value: model.binding(segment.id, \.speed), range: 0.25...4, defaultValue: 1,
                    format: { String(format: "%.2fx", $0) })
        Text("O tom é preservado ao mudar a velocidade.")
            .font(Theme.font(11))
            .foregroundStyle(Theme.textTertiary)
    }
}

private struct AdjustTab: View {
    @Environment(EditorModel.self) private var model
    let id: UUID

    var body: some View {
        SectionHeader(title: "Luz e cor") {
            model.mutate { TimelineEditor.update(&$0, segment: id) { $0.adjust = Adjust() } }
        }
        ParamSlider(title: "Brilho", value: model.binding(id, \.adjust.brightness), format: signedPercent)
        ParamSlider(title: "Contraste", value: model.binding(id, \.adjust.contrast), format: signedPercent)
        ParamSlider(title: "Saturação", value: model.binding(id, \.adjust.saturation), format: signedPercent)
        ParamSlider(title: "Exposição", value: model.binding(id, \.adjust.exposure), format: signedPercent)
        ParamSlider(title: "Temperatura", value: model.binding(id, \.adjust.temperature), format: signedPercent)
        ParamSlider(title: "Matiz (tint)", value: model.binding(id, \.adjust.tint), format: signedPercent)
        ParamSlider(title: "Realces", value: model.binding(id, \.adjust.highlights), format: signedPercent)
        ParamSlider(title: "Sombras", value: model.binding(id, \.adjust.shadows), format: signedPercent)
        ParamSlider(title: "Tom (hue)", value: model.binding(id, \.adjust.hue), format: signedPercent)
        SectionHeader(title: "Detalhes")
        ParamSlider(title: "Nitidez", value: model.binding(id, \.adjust.sharpen), range: 0...1, format: percent)
        ParamSlider(title: "Vinheta", value: model.binding(id, \.adjust.vignette), range: 0...1, format: percent)
        ParamSlider(title: "Desbotar", value: model.binding(id, \.adjust.fade), range: 0...1, format: percent)
        ParamSlider(title: "Granulado", value: model.binding(id, \.adjust.grain), range: 0...1, format: percent)
    }
}

private struct FiltersTab: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment
    @State private var previews: [FilterPreset: CGImage] = [:]

    var body: some View {
        let id = segment.id
        let current = segment.filter?.preset ?? .none
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ForEach(FilterPreset.allCases) { preset in
                ChoiceTile(title: preset.displayName, selected: current == preset) {
                    model.mutate {
                        TimelineEditor.update(&$0, segment: id) { seg in
                            seg.filter = preset == .none ? nil : FilterSetting(preset: preset, intensity: seg.filter?.intensity ?? 1)
                        }
                    }
                } preview: {
                    if let image = previews[preset] {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "camera.filters").foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.top, 8)
        .task(id: segment.materialId) { await makePreviews() }
        if segment.filter != nil {
            ParamSlider(title: "Intensidade", value: model.binding(id, \.filter!.intensity), range: 0...1,
                        defaultValue: 1, format: percent)
                .padding(.top, 6)
        }
    }

    private func makePreviews() async {
        guard let materialId = segment.materialId, let base = model.thumbnails[materialId]?.first else { return }
        let results = await Task.detached(priority: .userInitiated) {
            var out: [FilterPreset: CGImage] = [:]
            for preset in FilterPreset.allCases {
                out[preset] = preset == .none ? base : EffectPreview.filtered(base, preset: preset)
            }
            return out
        }.value
        previews = results
    }
}

private struct EffectsTab: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    private func icon(_ kind: VideoEffectKind) -> String {
        switch kind {
        case .blur: "drop"
        case .pixelate: "square.grid.3x3"
        case .rgbSplit: "camera.filters"
        case .mirror: "rectangle.split.2x1"
        case .shake: "waveform.path"
        case .flash: "bolt"
        case .zoomPulse: "plus.magnifyingglass"
        case .kaleidoscope: "hexagon"
        case .comic: "pencil.and.outline"
        case .edges: "scribble.variable"
        }
    }

    var body: some View {
        let id = segment.id
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ForEach(VideoEffectKind.allCases) { kind in
                let active = segment.effects.contains { $0.kind == kind }
                ChoiceTile(title: kind.displayName, selected: active) {
                    model.mutate {
                        TimelineEditor.update(&$0, segment: id) { seg in
                            if let i = seg.effects.firstIndex(where: { $0.kind == kind }) {
                                seg.effects.remove(at: i)
                            } else {
                                seg.effects.append(VideoEffect(kind: kind))
                            }
                        }
                    }
                } preview: {
                    Image(systemName: icon(kind))
                        .font(Theme.font(17, .light))
                        .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                }
            }
        }
        .padding(.top, 8)
        if !segment.effects.isEmpty {
            SectionHeader(title: "Aplicados") {
                model.mutate { TimelineEditor.update(&$0, segment: id) { $0.effects = [] } }
            }
            ForEach(Array(segment.effects.enumerated()), id: \.element.id) { index, effect in
                ParamSlider(title: effect.kind.displayName, value: model.binding(id, \.effects[index].intensity),
                            range: 0...1, defaultValue: 0.5, format: percent)
            }
        }
    }
}

private struct AnimationTab: View {
    let segment: Segment

    var body: some View {
        let isText = segment.text != nil
        let kinds = AnimationKind.allCases.filter { isText || !$0.textOnly }
        AnimationPicker(title: "Entrada", id: segment.id, keyPath: \.animationIn, kinds: kinds)
        AnimationPicker(title: "Saída", id: segment.id, keyPath: \.animationOut, kinds: kinds)
    }
}

private struct AnimationPicker: View {
    @Environment(EditorModel.self) private var model
    let title: String
    let id: UUID
    let keyPath: WritableKeyPath<Segment, SegmentAnimation?>
    let kinds: [AnimationKind]

    var body: some View {
        let anim = model.binding(id, keyPath)
        SectionHeader(title: title)
        FieldRow(label: "Tipo") {
            MenuField(selection: Binding<AnimationKind?>(
                get: { anim.wrappedValue?.kind },
                set: { kind in
                    anim.wrappedValue = kind.map { SegmentAnimation(kind: $0, duration: anim.wrappedValue?.duration ?? 500_000) }
                }),
                      options: [nil] + kinds.map(Optional.some),
                      title: { $0?.displayName ?? "Nenhuma" })
        }
        if anim.wrappedValue != nil {
            ParamSlider(title: "Duração",
                        value: Binding(get: { anim.wrappedValue?.duration.seconds ?? 0.5 },
                                       set: { anim.wrappedValue?.duration = Time.seconds($0) }),
                        range: 0.1...3, defaultValue: 0.5, format: secondsFormat)
        }
    }
}

private struct TransitionTab: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    var body: some View {
        let id = segment.id
        let current = segment.transition?.kind
        Text("Para o próximo clipe da faixa principal.")
            .font(Theme.font(11))
            .foregroundStyle(Theme.textTertiary)
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ChoiceTile(title: "Nenhuma", selected: current == nil) {
                model.mutate { TimelineEditor.update(&$0, segment: id) { $0.transition = nil } }
            } preview: {
                Image(systemName: "nosign").font(Theme.font(15, .light)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(TransitionKind.allCases) { kind in
                ChoiceTile(title: kind.displayName, selected: current == kind) {
                    model.mutate {
                        TimelineEditor.update(&$0, segment: id) { seg in
                            seg.transition = Transition(kind: kind, duration: seg.transition?.duration ?? 500_000)
                        }
                    }
                } preview: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(Theme.font(15, .light))
                        .foregroundStyle(current == kind ? Theme.accent : Theme.textSecondary)
                }
            }
        }
        if segment.transition != nil {
            ParamSlider(title: "Duração",
                        value: Binding(get: { segment.transition?.duration.seconds ?? 0.5 },
                                       set: { v in
                                           model.mutate(coalesce: "transition\(id)") {
                                               TimelineEditor.update(&$0, segment: id) { $0.transition?.duration = Time.seconds(v) }
                                           }
                                       }),
                        range: 0.1...2, defaultValue: 0.5, format: secondsFormat)
                .padding(.top, 6)
            Text("A transição sobrepõe o fim deste clipe ao início do próximo.")
                .font(Theme.font(11))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct TextTab: View {
    @Environment(EditorModel.self) private var model
    let id: UUID

    private static let fonts = ["Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Arial Rounded MT Bold",
                                "Impact", "Georgia", "Didot", "Times New Roman", "American Typewriter",
                                "Menlo", "Marker Felt", "Chalkboard SE", "Noteworthy", "Copperplate"]

    var body: some View {
        let text = model.binding(id, \.text!.text)
        let style = model.binding(id, \.text!.style)
        TextEditor(text: text)
            .font(Theme.font(13))
            .frame(height: 72)
            .scrollContentBackground(.hidden)
            .padding(6)
            .field()

        SectionHeader(title: "Estilos prontos")
        HStack(spacing: 6) {
            ForEach(TextStylePreset.allCases) { preset in
                Button(preset.title) { style.wrappedValue = preset.applied(to: style.wrappedValue) }
                    .buttonStyle(PillButtonStyle(compact: true))
            }
        }

        SectionHeader(title: "Fonte")
        FieldRow(label: "Família") {
            MenuField(selection: model.binding(id, \.text!.style.fontName), options: Self.fonts, title: { $0 })
        }
        ParamSlider(title: "Tamanho", value: model.binding(id, \.text!.style.fontSize), range: 0.02...0.25,
                    defaultValue: 0.07, format: { String(format: "%.0f", $0 * 1000) })
        HStack(spacing: 8) {
            PillPicker(selection: model.binding(id, \.text!.style.alignment),
                       options: TextAlignmentKind.allCases,
                       title: { ["left": "Esquerda", "center": "Centro", "right": "Direita"][$0.rawValue] ?? "" },
                       icon: { "text.align\($0.rawValue)" })
            Toggle(isOn: model.binding(id, \.text!.style.bold)) { Image(systemName: "bold") }
                .toggleStyle(IconToggleStyle())
                .help("Negrito")
            Toggle(isOn: model.binding(id, \.text!.style.italic)) { Image(systemName: "italic") }
                .toggleStyle(IconToggleStyle())
                .help("Itálico")
        }

        SectionHeader(title: "Cores")
        ColorRow(title: "Texto", color: color(model.binding(id, \.text!.style.color)))
        ParamSlider(title: "Contorno", value: model.binding(id, \.text!.style.strokeWidth), range: 0...10,
                    format: { String(format: "%.1f", $0) })
        ColorRow(title: "Contorno", color: color(model.binding(id, \.text!.style.strokeColor)))
        SwitchRow(title: "Fundo", isOn: model.binding(id, \.text!.style.backgroundEnabled))
        if style.wrappedValue.backgroundEnabled {
            ColorRow(title: "Cor do fundo", color: color(model.binding(id, \.text!.style.backgroundColor)))
        }
        SwitchRow(title: "Sombra", isOn: model.binding(id, \.text!.style.shadow))

        SectionHeader(title: "Posição") {
            model.mutate {
                TimelineEditor.update(&$0, segment: id) {
                    $0.text?.style.x = 0
                    $0.text?.style.y = -0.7
                    $0.text?.style.scale = 1
                    $0.text?.style.rotation = 0
                }
            }
        }
        ParamSlider(title: "Posição X", value: model.binding(id, \.text!.style.x), format: signedPercent)
        ParamSlider(title: "Posição Y", value: model.binding(id, \.text!.style.y), defaultValue: -0.7, format: signedPercent)
        ParamSlider(title: "Escala", value: model.binding(id, \.text!.style.scale), range: 0.2...3, defaultValue: 1, format: percent)
        ParamSlider(title: "Rotação", value: model.binding(id, \.text!.style.rotation), range: -180...180,
                    format: { String(format: "%.0f°", $0) })
        ParamSlider(title: "Largura máxima", value: model.binding(id, \.text!.style.maxWidth), range: 0.2...1,
                    defaultValue: 0.9, format: percent)
    }
}

/// Liga/desliga em forma de botão redondo; ligado fica em ciano.
private struct IconToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(CircleButtonStyle(size: 28, prominent: configuration.isOn))
    }
}

// MARK: - Projeto

private struct ProjectInspector: View {
    @Environment(EditorModel.self) private var model

    private enum BackgroundKind: String, CaseIterable, Identifiable {
        case black, color, blur
        var id: String { rawValue }
        var title: String {
            switch self {
            case .black: "Preto"
            case .color: "Cor"
            case .blur: "Desfoque"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Projeto")
                FieldRow(label: "Nome") {
                    InputField(placeholder: "Nome", text: model.projectBinding(\.name))
                }
                FieldRow(label: "Duração") {
                    Text(Time.format(model.duration)).font(Theme.mono(12))
                }
                FieldRow(label: "Clipes") {
                    Text("\(model.project.tracks.flatMap(\.segments).count)").font(Theme.mono(12))
                }

                SectionHeader(title: "Canvas")
                FieldRow(label: "Proporção") {
                    MenuField(selection: model.projectBinding(\.canvas.aspect), options: AspectRatio.allCases, title: \.label)
                }
                FieldRow(label: "Fundo") {
                    PillPicker(selection: backgroundKind, options: BackgroundKind.allCases, title: \.title)
                }
                switch model.project.canvas.background {
                case .color(let c):
                    ColorRow(title: "Cor do fundo", color: Binding(
                        get: { c.color },
                        set: { new in model.mutate(coalesce: "bgcolor") { $0.canvas.background = .color(RGBA(new)) } }))
                case .blur(let amount):
                    ParamSlider(title: "Intensidade do desfoque", value: Binding(
                        get: { amount },
                        set: { v in model.mutate(coalesce: "bgblur") { $0.canvas.background = .blur(v) } }),
                                range: 0...1, defaultValue: 0.5, format: percent)
                case .black:
                    EmptyView()
                }
                Text("O fundo aparece onde o vídeo não cobre o canvas, por exemplo ao converter 16:9 para 9:16.")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)

                SectionHeader(title: "Dica")
                Text("Selecione um clipe na timeline para ajustar transformação, cor, filtros, efeitos, animações e transições.")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
        }
        .scrollIndicators(.never)
    }

    private var backgroundKind: Binding<BackgroundKind> {
        Binding(
            get: {
                switch model.project.canvas.background {
                case .black: .black
                case .color: .color
                case .blur: .blur
                }
            },
            set: { kind in
                model.mutate {
                    switch kind {
                    case .black: $0.canvas.background = .black
                    case .color: $0.canvas.background = .color(RGBA(0.1, 0.1, 0.12))
                    case .blur: $0.canvas.background = .blur(0.5)
                    }
                }
            })
    }
}
