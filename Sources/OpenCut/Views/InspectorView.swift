import OpenCutCore
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
        .background(Theme.panel)
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

private struct TabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Tile selecionável usado nas grades de filtros, efeitos e transições.
private struct ChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                preview()
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(Theme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Theme.accent : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmento

private struct SegmentInspector: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    var body: some View {
        let tabs = model.availableTabs(for: segment)
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        TabButton(title: tab.title, selected: model.inspectorTab == tab) { model.inspectorTab = tab }
                    }
                }
                .padding(8)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tabs.contains(model.inspectorTab) ? model.inspectorTab : (tabs.first ?? .basic) {
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
                .padding(14)
            }
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
        ParamSlider(title: "Velocidade", value: model.binding(id, \.speed), range: 0.1...4, defaultValue: 1,
                    format: { String(format: "%.2fx", $0) })
        HStack {
            ForEach([0.5, 1, 1.5, 2, 3], id: \.self) { s in
                Button(String(format: "%gx", s)) {
                    model.mutate { TimelineEditor.setSpeed(&$0, segment: id, speed: s) }
                }
                .controlSize(.small)
            }
        }

        if model.project.material(segment.materialId)?.hasAudio == true {
            AudioControls(id: id)
        }
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
        ParamSlider(title: "Velocidade", value: model.binding(segment.id, \.speed), range: 0.25...4, defaultValue: 1,
                    format: { String(format: "%.2fx", $0) })
        Text("O tom é preservado ao mudar a velocidade.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct AdjustTab: View {
    @Environment(EditorModel.self) private var model
    let id: UUID

    var body: some View {
        SectionHeader(title: "Ajustar") {
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
        SectionHeader(title: "Filtros")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 10) {
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
                        Image(systemName: "camera.filters").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: segment.materialId) { await makePreviews() }
        if segment.filter != nil {
            ParamSlider(title: "Intensidade", value: model.binding(id, \.filter!.intensity), range: 0...1,
                        defaultValue: 1, format: percent)
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
        case .blur: "drop.fill"
        case .pixelate: "square.grid.3x3.fill"
        case .rgbSplit: "camera.filters"
        case .mirror: "rectangle.split.2x1"
        case .shake: "waveform.path"
        case .flash: "bolt.fill"
        case .zoomPulse: "plus.magnifyingglass"
        case .kaleidoscope: "hexagon"
        case .comic: "pencil.and.outline"
        case .edges: "scribble.variable"
        }
    }

    var body: some View {
        let id = segment.id
        SectionHeader(title: "Efeitos de vídeo")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 10) {
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
                    Image(systemName: icon(kind)).font(.title3).foregroundStyle(active ? Theme.accent : .secondary)
                }
            }
        }
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
    @Environment(EditorModel.self) private var model
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
        Picker("Tipo", selection: Binding<AnimationKind?>(
            get: { anim.wrappedValue?.kind },
            set: { kind in
                anim.wrappedValue = kind.map { SegmentAnimation(kind: $0, duration: anim.wrappedValue?.duration ?? 500_000) }
            })) {
            Text("Nenhuma").tag(AnimationKind?.none)
            ForEach(kinds) { kind in Text(kind.displayName).tag(AnimationKind?.some(kind)) }
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
        SectionHeader(title: "Transição para o próximo clipe")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 10) {
            ChoiceTile(title: "Nenhuma", selected: current == nil) {
                model.mutate { TimelineEditor.update(&$0, segment: id) { $0.transition = nil } }
            } preview: {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            }
            ForEach(TransitionKind.allCases) { kind in
                ChoiceTile(title: kind.displayName, selected: current == kind) {
                    model.mutate {
                        TimelineEditor.update(&$0, segment: id) { seg in
                            seg.transition = Transition(kind: kind, duration: seg.transition?.duration ?? 500_000)
                        }
                    }
                } preview: {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(current == kind ? Theme.accent : .secondary)
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
            Text("A transição sobrepõe o fim deste clipe ao início do próximo.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        SectionHeader(title: "Texto")
        TextEditor(text: text)
            .font(.body)
            .frame(height: 70)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 6))

        SectionHeader(title: "Estilos prontos")
        HStack(spacing: 6) {
            presetButton("Clássico", style) { _ in }
            presetButton("Contorno", style) { $0.strokeWidth = 4; $0.shadow = false }
            presetButton("Destaque", style) {
                $0.color = .black
                $0.backgroundEnabled = true
                $0.backgroundColor = .yellow
                $0.shadow = false
            }
            presetButton("Neon", style) {
                $0.color = RGBA(0.3, 1, 0.95)
                $0.strokeWidth = 2
                $0.strokeColor = RGBA(0.05, 0.2, 0.4)
            }
        }

        SectionHeader(title: "Fonte")
        Picker("Fonte", selection: model.binding(id, \.text!.style.fontName)) {
            ForEach(Self.fonts, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
        }
        ParamSlider(title: "Tamanho", value: model.binding(id, \.text!.style.fontSize), range: 0.02...0.25,
                    defaultValue: 0.07, format: { String(format: "%.0f", $0 * 1000) })
        HStack {
            Toggle("Negrito", isOn: model.binding(id, \.text!.style.bold))
            Toggle("Itálico", isOn: model.binding(id, \.text!.style.italic))
        }
        Picker("Alinhamento", selection: model.binding(id, \.text!.style.alignment)) {
            Image(systemName: "text.alignleft").tag(TextAlignmentKind.left)
            Image(systemName: "text.aligncenter").tag(TextAlignmentKind.center)
            Image(systemName: "text.alignright").tag(TextAlignmentKind.right)
        }
        .pickerStyle(.segmented)

        SectionHeader(title: "Cores")
        ColorPicker("Cor do texto", selection: color(model.binding(id, \.text!.style.color)))
        ParamSlider(title: "Contorno", value: model.binding(id, \.text!.style.strokeWidth), range: 0...10,
                    format: { String(format: "%.1f", $0) })
        ColorPicker("Cor do contorno", selection: color(model.binding(id, \.text!.style.strokeColor)))
        Toggle("Fundo", isOn: model.binding(id, \.text!.style.backgroundEnabled))
        if style.wrappedValue.backgroundEnabled {
            ColorPicker("Cor do fundo", selection: color(model.binding(id, \.text!.style.backgroundColor)))
        }
        Toggle("Sombra", isOn: model.binding(id, \.text!.style.shadow))

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

    private func presetButton(_ title: String, _ style: Binding<TextStyle>, _ apply: @escaping (inout TextStyle) -> Void) -> some View {
        Button(title) {
            var s = TextStyle()
            let old = style.wrappedValue
            s.fontName = old.fontName
            s.fontSize = old.fontSize
            s.x = old.x
            s.y = old.y
            s.alignment = old.alignment
            apply(&s)
            style.wrappedValue = s
        }
        .controlSize(.small)
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
                SectionHeader(title: "Projeto")
                TextField("Nome", text: model.projectBinding(\.name))
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Duração", value: Time.format(model.duration))
                LabeledContent("Clipes", value: "\(model.project.tracks.flatMap(\.segments).count)")

                SectionHeader(title: "Canvas")
                Picker("Proporção", selection: model.projectBinding(\.canvas.aspect)) {
                    ForEach(AspectRatio.allCases) { Text($0.label).tag($0) }
                }
                Picker("Fundo", selection: backgroundKind) {
                    ForEach(BackgroundKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch model.project.canvas.background {
                case .color(let c):
                    ColorPicker("Cor do fundo", selection: Binding(
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
                Text("O fundo aparece onde o vídeo não cobre o canvas — útil ao converter 16:9 para 9:16.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SectionHeader(title: "Atalhos")
                VStack(alignment: .leading, spacing: 4) {
                    shortcut("Espaço", "Reproduzir / pausar")
                    shortcut("⌘B", "Dividir no cursor")
                    shortcut("⌫", "Apagar clipe")
                    shortcut("⌘D", "Duplicar")
                    shortcut("← →", "Quadro a quadro (⇧ = 10)")
                    shortcut("⌘Z / ⇧⌘Z", "Desfazer / refazer")
                    shortcut("⌘E", "Exportar")
                }
                .font(.caption)
            }
            .padding(14)
        }
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

    private func shortcut(_ keys: String, _ action: String) -> some View {
        HStack {
            Text(keys).monospaced().frame(width: 90, alignment: .leading)
            Text(action).foregroundStyle(.secondary)
        }
    }
}
