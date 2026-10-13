import OpenFrameCore
import SwiftUI
import UniformTypeIdentifiers

struct TimelineView: View {
    @Environment(EditorModel.self) private var model

    static let rowHeight: CGFloat = 50
    static let rowSpacing: CGFloat = 6
    static let rulerHeight: CGFloat = 30
    static let headerWidth: CGFloat = 58
    static let clipInset: CGFloat = 4
    static let rowStride = rowHeight + rowSpacing

    /// Topo da linha `row` no conteúdo da timeline (a régua vem antes).
    static func rowTop(_ row: Int) -> CGFloat {
        rulerHeight + rowSpacing + CGFloat(row) * rowStride
    }

    /// Linha sob a posição `y` do conteúdo; nil sobre a régua.
    static func row(atY y: CGFloat) -> Int? {
        let row = Int(((y - rulerHeight - rowSpacing) / rowStride).rounded(.down))
        return row >= 0 ? row : nil
    }

    /// Zoom e ponto sob os dedos no início da pinça.
    @State private var pinchStart: (zoom: Double, time: Double, x: CGFloat)?
    /// Posição do material arrastado da biblioteca sobre a timeline.
    @State private var dropLocation: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar()
            Rectangle().fill(Theme.hairline).frame(height: 1)
            GeometryReader { geo in
                let order = model.displayTrackOrder()
                let tracks = order.map { model.project.tracks[$0] }
                let viewportWidth = geo.size.width - Self.headerWidth
                // 15 s depois do fim (e no mínimo 160 pt, para a barra de ações do último clipe).
                let contentWidth = max(viewportWidth,
                                       CGFloat(model.duration.seconds * model.zoom) + max(CGFloat(15 * model.zoom), 160))
                let contentHeight = Self.rulerHeight + CGFloat(tracks.count) * Self.rowStride
                let drop = dropPreview
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: Self.rowSpacing) {
                            Color.clear.frame(height: Self.rulerHeight)
                            ForEach(tracks) { track in
                                TrackHeader(track: track)
                                    .frame(height: Self.rowHeight)
                            }
                        }
                        .frame(width: Self.headerWidth)

                        ScrollView(.horizontal) {
                            ZStack(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                                    RulerView(width: contentWidth)
                                    ForEach(Array(tracks.enumerated()), id: \.element.id) { row, track in
                                        TrackRow(track: track, width: contentWidth,
                                                 highlighted: model.dragTarget?.row == row || (drop != nil && drop?.row == row))
                                            .zIndex(isDragSource(track) ? 1 : 0)
                                    }
                                }
                                .padding(.bottom, ClipActionBar.reserve)
                                if let drop {
                                    DropGhost(range: drop.range, row: drop.row, height: contentHeight)
                                }
                                PlayheadView(height: contentHeight + 8, time: model.playhead)
                                    .offset(x: CGFloat(model.playhead.seconds * model.zoom) - PlayheadView.width / 2)
                                ClipActionBar(tracks: tracks, contentWidth: contentWidth)
                            }
                            .frame(width: contentWidth, alignment: .topLeading)
                            .background(ScrollViewAccessor(model: model))
                            .simultaneousGesture(pinch)
                            .onDrop(of: [.plainText], delegate: TimelineDropDelegate(model: model, location: $dropLocation))
                            .padding(.trailing, 24)
                        }
                        .scrollIndicators(.automatic)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollIndicators(.never)
                .onChange(of: viewportWidth, initial: true) { model.timelineViewportWidth = viewportWidth }
            }
        }
    }
}

extension TimelineView {
    /// Onde o material arrastado da biblioteca cairia, com a linha de destino
    /// (nil se for criada uma faixa nova).
    private var dropPreview: (row: Int?, range: TimeRange)? {
        guard let location = dropLocation else { return nil }
        let time = Micros(max(0, location.x) / model.zoom * 1_000_000)
        guard let id = model.draggingMaterial,
              let preview = model.dropPreview(id, at: time, row: Self.row(atY: location.y))
        else { return (nil, TimeRange(start: time, duration: 0)) }
        return preview
    }

    private func isDragSource(_ track: Track) -> Bool {
        guard let id = model.dragPreview?.segment else { return false }
        return track.segments.contains { $0.id == id }
    }

    /// Pinça no trackpad: zoom mantendo parado o ponto sob os dedos.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? {
                    let anchor = model.zoomAnchor(contentX: value.startLocation.x)
                    return (model.zoom, anchor.time, anchor.x)
                }()
                pinchStart = start
                model.setZoom(start.zoom * value.magnification, keeping: start.time, at: start.x)
            }
            .onEnded { _ in pinchStart = nil }
    }
}

/// Entrega ao modelo o NSScrollView horizontal da timeline, para acompanhar a rolagem.
private struct ScrollViewAccessor: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> NSView { Probe(model: model) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        private weak var model: EditorModel?

        init(model: EditorModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scroll = enclosingScrollView { model?.attachTimelineScroll(scroll) }
        }
    }
}

/// Recebe materiais arrastados da biblioteca (o id do material como texto).
private struct TimelineDropDelegate: DropDelegate {
    let model: EditorModel
    @Binding var location: CGPoint?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        location = info.location
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        location = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        location = nil
        model.draggingMaterial = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let time = Micros(max(0, info.location.x) / model.zoom * 1_000_000)
        let row = TimelineView.row(atY: info.location.y)
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString, let id = UUID(uuidString: text as String) else { return }
            Task { @MainActor in model.dropMaterial(id, at: time, row: row) }
        }
        return true
    }
}

/// Contorno de onde o material solto vai cair; sem linha conhecida (faixa
/// nova), só a linha vertical no tempo.
private struct DropGhost: View {
    @Environment(EditorModel.self) private var model
    let range: TimeRange
    let row: Int?
    let height: CGFloat

    var body: some View {
        let x = CGFloat(range.start.seconds * model.zoom)
        Rectangle()
            .fill(Theme.accent)
            .frame(width: 2, height: height)
            .offset(x: x - 1)
            .allowsHitTesting(false)
        if let row, range.duration > 0 {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.accent.opacity(0.12))
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: max(4, CGFloat(range.duration.seconds * model.zoom)),
                       height: TimelineView.rowHeight - TimelineView.clipInset * 2)
                .offset(x: x, y: TimelineView.rowTop(row) + TimelineView.clipInset)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Barra de ferramentas

private struct TimelineToolbar: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Button { model.splitAtPlayhead() } label: { Image(systemName: "scissors") }
                .help("Dividir no cursor (⌘B)")
            Button { model.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }
                .disabled(model.selection == nil)
                .help("Duplicar (⌘D)")
            Button { model.deleteSelection() } label: { Image(systemName: "trash") }
                .disabled(model.selection == nil)
                .help("Apagar (⌫)")
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, 6)
            Button { model.addText() } label: { Label("Texto", systemImage: "textformat") }
                .buttonStyle(PillButtonStyle(kind: .quiet, compact: true))
                .help("Adicionar texto (⌘T)")
            Spacer()
            if let seg = model.selectedSegment {
                Text("\(Time.format(seg.targetStart)) – \(Time.format(seg.targetEnd))")
                    .foregroundStyle(Theme.textSecondary)
                Text(seg.targetDuration.shortSeconds)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button { model.zoomToFit() } label: { Image(systemName: "rectangle.arrowtriangle.2.outward") }
                .buttonStyle(GlyphButtonStyle())
                .help("Ajustar à janela (⇧Z)")
                .padding(.trailing, 6)
            Button { model.zoomOut() } label: { Image(systemName: "minus") }
                .buttonStyle(GlyphButtonStyle())
                .help("Afastar (⌘−)")
            ThinSlider(value: zoomFraction, range: 0...1)
                .frame(width: 120)
            Button { model.zoomIn() } label: { Image(systemName: "plus") }
                .buttonStyle(GlyphButtonStyle())
                .help("Aproximar (⌘=)")
        }
        .font(Theme.mono(11))
        .buttonStyle(CircleButtonStyle(size: 28))
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    /// Zoom em escala logarítmica, de `minZoom` (projeto inteiro) a `maxZoom`.
    private var zoomFraction: Binding<Double> {
        let low = log(model.minZoom), high = log(EditorModel.maxZoom)
        return Binding(get: { (log(model.zoom) - low) / (high - low) },
                       set: { model.setZoom(exp(low + $0 * (high - low))) })
    }
}

// MARK: - Cabeçalho das faixas

private struct TrackHeader: View {
    @Environment(EditorModel.self) private var model
    let track: Track

    private var icon: String {
        switch track.kind {
        case .video: track.isMain ? "film" : "square.on.square"
        case .audio: "waveform"
        case .text: "textformat"
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(Theme.font(11, .light))
                .foregroundStyle(track.isMain ? Theme.textSecondary : Theme.textTertiary)
                .help(track.isMain ? "Faixa principal" : "")
            HStack(spacing: 9) {
                if track.kind != .text {
                    Button { toggle(\.muted) } label: {
                        Image(systemName: track.muted ? "speaker.slash" : "speaker.wave.2")
                    }
                    .buttonStyle(GlyphButtonStyle(active: track.muted))
                    .help(track.muted ? "Ativar som" : "Silenciar faixa")
                }
                if track.kind != .audio {
                    Button { toggle(\.hidden) } label: {
                        Image(systemName: track.hidden ? "eye.slash" : "eye")
                    }
                    .buttonStyle(GlyphButtonStyle(active: track.hidden))
                    .help(track.hidden ? "Mostrar faixa" : "Ocultar faixa")
                }
            }
            .font(Theme.font(10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ keyPath: WritableKeyPath<Track, Bool>) {
        let id = track.id
        model.mutate { p in
            if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i][keyPath: keyPath].toggle() }
        }
    }
}

// MARK: - Régua e playhead

private struct RulerView: View {
    @Environment(EditorModel.self) private var model
    let width: CGFloat

    var body: some View {
        let zoom = model.zoom
        Canvas { ctx, size in
            let pill = CGRect(x: 0, y: 4, width: size.width, height: size.height - 8)
            ctx.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(Theme.raised))
            let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 14400]
            let major = steps.first { $0 * zoom >= 110 } ?? 14400
            let minor = major / 4
            var i = 0
            while Double(i) * minor * zoom <= size.width {
                let t = Double(i) * minor
                let x = t * zoom
                if i % 4 == 0 {
                    let label = Text(Self.label(t, step: major))
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.textTertiary)
                    if i == 0 {
                        ctx.draw(label, at: CGPoint(x: 12, y: size.height / 2), anchor: .leading)
                    } else {
                        ctx.draw(label, at: CGPoint(x: x, y: size.height / 2), anchor: .center)
                    }
                } else {
                    ctx.fill(Path(CGRect(x: x - 0.5, y: size.height / 2 - 2.5, width: 1, height: 5)),
                             with: .color(Color.white.opacity(0.18)))
                }
                i += 1
            }
        }
        .frame(width: width, height: TimelineView.rulerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            model.scrub(to: Micros(max(0, value.location.x) / model.zoom * 1_000_000))
        })
        .help("Arraste para navegar")
    }

    static func label(_ t: Double, step: Double) -> String {
        if t >= 3600 {
            let s = Int(t)
            return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        }
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        return step < 1 ? String(format: "%02d:%04.1f", minutes, seconds) : String(format: "%02d:%02d", minutes, Int(seconds))
    }
}

/// Playhead com a cabeça da agulha da marca, que leva o tempo atual. A
/// cabeça pode ser arrastada; a linha deixa os cliques passarem para os clipes.
private struct PlayheadView: View {
    @Environment(EditorModel.self) private var model
    static let width: CGFloat = 60
    let height: CGFloat
    let time: Micros
    @State private var dragStart: Micros?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NeedleHead(taper: 5, line: 1.5)
                    .fill(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 6)
                Text(Time.format(time))
                    .font(Theme.mono(9.5, .medium))
                    .foregroundStyle(Theme.onAccent)
                    .frame(height: 16)
            }
            .frame(width: Self.width, height: 21)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? model.playhead
                    dragStart = start
                    model.scrub(to: start + Micros(Double(value.translation.width) / model.zoom * 1_000_000))
                }
                .onEnded { _ in dragStart = nil })
            .help("Arraste para navegar")
            .padding(.top, 4)
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 1.5)
                .shadow(color: Theme.accent.opacity(0.5), radius: 3)
                .allowsHitTesting(false)
        }
        .frame(width: Self.width, height: height, alignment: .top)
    }
}

// MARK: - Faixas e clipes

private struct TrackRow: View {
    @Environment(EditorModel.self) private var model
    let track: Track
    let width: CGFloat
    /// Destino de um clipe ou material arrastado.
    let highlighted: Bool
    /// Junção da faixa principal sob o mouse, que mostra o botão de transição.
    @State private var hoveredJunction: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(highlighted ? 0.07 : track.isMain ? 0.035 : 0.018))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(highlighted ? 0.5 : 0)))
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    model.selection = nil
                    model.seek(to: Micros(location.x / model.zoom * 1_000_000))
                }
            ForEach(Array(track.segments.enumerated()), id: \.element.id) { index, seg in
                let isDragged = model.dragPreview?.segment == seg.id
                SegmentView(segment: seg, track: track)
                    .offset(x: CGFloat(displayStart(seg, index: index).seconds * model.zoom), y: TimelineView.clipInset)
                    // O clipe do gesto (ou o selecionado) fica por cima dos vizinhos nos dois sentidos.
                    .zIndex(isDragged ? 2 : model.selection == seg.id ? 1 : 0)
                    // Ele segue o cursor; só os outros deslizam.
                    .transaction { if isDragged { $0.animation = nil } }
            }
            if track.isMain && !hasGesture {
                ForEach(Array(track.segments.dropLast().enumerated()), id: \.element.id) { index, seg in
                    transitionButton(seg, next: track.segments[index + 1], index: index)
                }
            }
        }
        .frame(width: width, height: TimelineView.rowHeight)
        .opacity(track.hidden ? 0.4 : 1)
        .onContinuousHover { phase in
            guard track.isMain else { return }
            var nearest: Int?
            if case .active(let point) = phase {
                nearest = junctions.indices.min { abs(junctions[$0] - point.x) < abs(junctions[$1] - point.x) }
                if let i = nearest, abs(junctions[i] - point.x) > 40 { nearest = nil }
            }
            if nearest != hoveredJunction { hoveredJunction = nearest }
        }
    }

    /// Algum clipe desta faixa está sendo arrastado ou aparado pelo início.
    private var hasGesture: Bool {
        guard let id = model.dragPreview?.segment else { return false }
        return track.segments.contains { $0.id == id }
    }

    /// Início desenhado: o clipe do gesto segue o cursor; na faixa principal,
    /// ao aparar o início, os clipes seguintes ficam onde estavam até soltar.
    private func displayStart(_ seg: Segment, index: Int) -> Micros {
        guard let preview = model.dragPreview else { return seg.targetStart }
        if preview.segment == seg.id { return preview.start }
        if preview.following != 0, track.isMain,
           let dragged = track.segments.firstIndex(where: { $0.id == preview.segment }), index > dragged {
            return seg.targetStart + preview.following
        }
        return seg.targetStart
    }

    /// Posição x de cada junção entre clipes da faixa principal.
    private var junctions: [CGFloat] {
        zip(track.segments, track.segments.dropFirst()).map { seg, next in
            CGFloat(Double(seg.targetEnd + next.targetStart) / 2 / 1_000_000 * model.zoom)
        }
    }

    /// Botão na junção entre dois clipes. Sem transição, só aparece com o mouse
    /// perto da junção ou com um dos dois clipes selecionado.
    private func transitionButton(_ seg: Segment, next: Segment, index: Int) -> some View {
        let junction = Double(seg.targetEnd + next.targetStart) / 2 / 1_000_000
        let has = seg.transition != nil
        let visible = has || hoveredJunction == index || model.selection == seg.id || model.selection == next.id
        return Button {
            model.selection = seg.id
            model.inspectorTab = .transition
        } label: {
            Image(systemName: has ? "arrow.left.arrow.right" : "plus")
                .font(Theme.font(9, .medium))
                .foregroundStyle(has ? Theme.onAccent : Theme.textPrimary)
                .frame(width: 20, height: 20)
                .background(has ? Theme.accent : Theme.raisedHigh, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(has ? 0 : 0.18)))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help(seg.transition.map { "Transição: \($0.kind.displayName)" } ?? "Adicionar transição")
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeOut(duration: 0.12), value: visible)
        // Abaixo do nome do clipe, para não cobri-lo.
        .offset(x: CGFloat(junction * model.zoom) - 10, y: TimelineView.rowHeight - TimelineView.clipInset - 24)
    }
}

private struct SegmentView: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment
    let track: Track

    private static let radius: CGFloat = 9
    private var material: Material? { model.project.material(segment.materialId) }
    private var width: CGFloat { max(4, CGFloat(segment.targetDuration.seconds * model.zoom)) }
    private var height: CGFloat { TimelineView.rowHeight - TimelineView.clipInset * 2 }
    private var isSelected: Bool { model.selection == segment.id }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            if width > 46 { titleChip }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1))
        .overlay(alignment: .leading) { if isSelected { handle(leading: true) } }
        .overlay(alignment: .trailing) { if isSelected { handle(leading: false) } }
        .shadow(color: isSelected ? Theme.accent.opacity(0.35) : .clear, radius: 10)
        .contentShape(Rectangle())
        .offset(dragShift)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    let rows = Int((value.translation.height / TimelineView.rowStride).rounded())
                    model.dragMove(segment.id, dx: value.translation.width, rows: rows)
                }
                .onEnded { _ in model.endDragMove(segment.id) })
        .onTapGesture { model.selection = segment.id }
        .contextMenu {
            Button("Dividir no cursor") {
                model.selection = segment.id
                model.splitAtPlayhead()
            }
            Button("Duplicar") {
                model.selection = segment.id
                model.duplicateSelection()
            }
            Divider()
            Button("Apagar", role: .destructive) {
                model.selection = segment.id
                model.deleteSelection()
            }
        }
    }

    /// Deslocamento até a faixa de destino enquanto o clipe é arrastado para outra linha
    /// (o horizontal vem de `dragPreview`, na linha).
    private var dragShift: CGSize {
        guard let preview = model.dragPreview, preview.segment == segment.id else { return .zero }
        return CGSize(width: 0, height: CGFloat(preview.rows) * TimelineView.rowStride)
    }

    @ViewBuilder
    private var content: some View {
        if segment.text != nil {
            Theme.clipText
        } else if let m = material, m.kind == .audio {
            ZStack(alignment: .bottomLeading) {
                Theme.clipAudio
                if let peaks = model.waveforms[m.id] {
                    WaveformBars(peaks: peaks, from: segment.source.start.seconds,
                                 to: (segment.source.start + segment.source.duration).seconds,
                                 color: isSelected ? Theme.accent.opacity(0.7) : Theme.waveform)
                        .frame(height: height * 0.5)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                        .opacity(0.4 + 0.6 * min(segment.volume, 1))
                }
            }
        } else if let m = material {
            ZStack {
                Theme.clipVideo
                ThumbnailStrip(material: m, segment: segment, images: model.thumbnails[m.id] ?? [])
                    .clipShape(RoundedRectangle(cornerRadius: Self.radius - 2, style: .continuous))
                    .padding(2)
            }
        } else {
            Theme.raised
        }
    }

    /// Ícone e nome dentro do clipe, mais os indicadores de ajustes.
    private var titleChip: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(Theme.font(9, .medium))
            Text(title)
                .font(Theme.font(10, .medium))
                .lineLimit(1)
            ForEach(badgeItems, id: \.self) { item in
                Text(item)
                    .font(Theme.font(9, .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(.black.opacity(segment.text != nil ? 0 : 0.55), in: Capsule())
        .padding(6)
        .frame(maxWidth: width - 4, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var iconName: String {
        if segment.text != nil { return "textformat" }
        switch material?.kind {
        case .audio: return "music.note"
        case .photo: return "photo"
        default: return track.isMain ? "film" : "square.on.square"
        }
    }

    private var title: String {
        if let text = segment.text { return text.text.replacingOccurrences(of: "\n", with: " ") }
        return material?.name ?? ""
    }

    private var badgeItems: [String] {
        var items: [String] = []
        if abs(segment.speed - 1) > 0.001 { items.append(String(format: "%.2gx", segment.speed)) }
        if let f = segment.filter, f.preset != .none { items.append(f.preset.displayName) }
        if !segment.effects.isEmpty { items.append("✦\(segment.effects.count)") }
        if !segment.adjust.isIdentity { items.append("◐") }
        if segment.animationIn != nil || segment.animationOut != nil { items.append("↻") }
        return items
    }

    private func handle(leading: Bool) -> some View {
        UnevenRoundedRectangle(cornerRadii: leading
                               ? .init(topLeading: Self.radius, bottomLeading: Self.radius)
                               : .init(bottomTrailing: Self.radius, topTrailing: Self.radius),
                               style: .continuous)
            .fill(Theme.accent)
            .frame(width: 9)
            .overlay(Capsule().fill(Theme.onAccent.opacity(0.75)).frame(width: 2, height: 14))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in model.dragTrim(segment.id, leading: leading, dx: value.translation.width) }
                    .onEnded { _ in model.endDragTrim() })
    }
}

/// Ações do clipe selecionado, flutuando junto dele: acima do clipe ou, na
/// primeira faixa, abaixo (para não cobrir a régua). A timeline reserva
/// `reserve` sob a última faixa, para a barra nunca passar do conteúdo,
/// que o ScrollView recorta; na horizontal ela fica dentro da área visível.
private struct ClipActionBar: View {
    static let height: CGFloat = 30
    static let reserve: CGFloat = height + 6

    @Environment(EditorModel.self) private var model
    let tracks: [Track]
    let contentWidth: CGFloat

    var body: some View {
        if model.dragPreview == nil, let seg = model.selectedSegment,
           let row = tracks.firstIndex(where: { $0.segments.contains { $0.id == seg.id } }) {
            let zoom = model.zoom
            let start = CGFloat(seg.targetStart.seconds * zoom)
            let end = CGFloat(seg.targetEnd.seconds * zoom)
            let canSplit = seg.targetRange.contains(model.playhead) && model.playhead > seg.targetStart
            let actions = canSplit ? 3 : 2
            let width = CGFloat(actions) * Self.height + CGFloat(actions - 1) + 8
            // Ao lado da linha do playhead (ou no início do clipe), dentro da área
            // visível, sem se afastar do clipe e sem passar das bordas do conteúdo.
            let anchor = canSplit ? CGFloat(model.playhead.seconds * zoom) + 8 : start + 8
            let visibleLeft = model.timelineScrollX
            let visibleRight = visibleLeft + model.timelineViewportWidth
            let inView = model.timelineViewportWidth > 0
                ? max(min(anchor, visibleRight - width - 8), visibleLeft + 8) : anchor
            let nearClip = min(max(inView, start - width + 24), end - 24)
            let x = max(0, min(nearClip, contentWidth - width))
            let rowTop = TimelineView.rowTop(row)
            let y = row == 0 ? rowTop + TimelineView.rowHeight - 2 : rowTop - Self.height + 2
            HStack(spacing: 0) {
                if canSplit {
                    action("scissors", "Dividir (⌘B)") { model.splitAtPlayhead() }
                    separator
                }
                action("plus.square.on.square", "Duplicar (⌘D)") { model.duplicateSelection() }
                separator
                action("trash", "Apagar (⌫)") { model.deleteSelection() }
            }
            .padding(.horizontal, 4)
            .frame(height: Self.height)
            .background(Theme.raisedHigh, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
            .fixedSize()
            .offset(x: x, y: y)
            .transition(.opacity)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 16)
    }

    private func action(_ icon: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon)
                .font(Theme.font(11))
                .frame(width: Self.height, height: Self.height)
        }
        .buttonStyle(GlyphButtonStyle())
        .help(help)
    }
}

/// Miniaturas repetidas ao longo do clipe, escolhidas pelo tempo de origem.
private struct ThumbnailStrip: View {
    let material: Material
    let segment: Segment
    let images: [CGImage]

    var body: some View {
        Canvas { ctx, size in
            guard !images.isEmpty else { return }
            let aspect = material.height > 0 ? CGFloat(material.width) / CGFloat(material.height) : 16 / 9
            let tile = max(20, size.height * aspect)
            var x: CGFloat = 0
            while x < size.width {
                var index = 0
                if material.kind == .video, material.duration > 0 {
                    let fraction = Double((x + tile / 2) / max(size.width, 1))
                    let sourceTime = Double(segment.source.start) + fraction * Double(segment.source.duration)
                    index = min(images.count - 1, max(0, Int(sourceTime / Double(material.duration) * Double(images.count))))
                }
                ctx.draw(Image(decorative: images[index], scale: 1), in: CGRect(x: x, y: 0, width: tile, height: size.height))
                x += tile
            }
        }
    }
}
