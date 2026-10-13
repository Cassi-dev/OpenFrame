import OpenCutCore
import SwiftUI

struct TimelineView: View {
    @Environment(EditorModel.self) private var model

    static let rowHeight: CGFloat = 50
    static let rowSpacing: CGFloat = 6
    static let rulerHeight: CGFloat = 26
    static let headerWidth: CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar()
            Divider()
            GeometryReader { geo in
                let tracks = model.displayTrackOrder().map { model.project.tracks[$0] }
                let contentWidth = max(geo.size.width - Self.headerWidth,
                                       CGFloat((model.duration.seconds + 15) * model.zoom))
                let contentHeight = Self.rulerHeight + CGFloat(tracks.count) * (Self.rowHeight + Self.rowSpacing)
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
                        .padding(.horizontal, 4)

                        ScrollView(.horizontal) {
                            ZStack(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                                    RulerView(width: contentWidth)
                                    ForEach(tracks) { track in
                                        TrackRow(track: track, width: contentWidth)
                                    }
                                }
                                PlayheadView(height: contentHeight)
                                    .offset(x: CGFloat(model.playhead.seconds * model.zoom) - 6)
                            }
                            .frame(width: contentWidth, alignment: .topLeading)
                            .padding(.trailing, 20)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
        .background(Theme.panel)
    }
}

private struct TimelineToolbar: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Button { model.splitAtPlayhead() } label: { Image(systemName: "scissors") }
                .help("Dividir no cursor (⌘B)")
            Button { model.deleteSelection() } label: { Image(systemName: "trash") }
                .disabled(model.selection == nil)
                .help("Apagar (⌫)")
            Button { model.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }
                .disabled(model.selection == nil)
                .help("Duplicar (⌘D)")
            Divider().frame(height: 16)
            Button { model.addText() } label: { Label("Texto", systemImage: "textformat") }
            Spacer()
            if let seg = model.selectedSegment {
                Text("\(Time.format(seg.targetStart)) – \(Time.format(seg.targetEnd))  (\(seg.targetDuration.shortSeconds))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: Binding(get: { log(model.zoom) }, set: { model.zoom = exp($0) }),
                   in: log(8.0)...log(600.0))
                .frame(width: 140)
                .controlSize(.small)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

private struct TrackHeader: View {
    @Environment(EditorModel.self) private var model
    let track: Track

    private var icon: String {
        switch track.kind {
        case .video: track.isMain ? "film" : "rectangle.on.rectangle"
        case .audio: "waveform"
        case .text: "textformat"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(track.isMain ? Theme.accent : .secondary)
                .help(track.isMain ? "Faixa principal" : "")
            if track.kind != .text {
                Button { toggle(\.muted) } label: {
                    Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2")
                }
                .help(track.muted ? "Ativar som" : "Silenciar faixa")
            }
            if track.kind != .audio {
                Button { toggle(\.hidden) } label: {
                    Image(systemName: track.hidden ? "eye.slash" : "eye")
                }
                .help(track.hidden ? "Mostrar faixa" : "Ocultar faixa")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panelRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
    }

    private func toggle(_ keyPath: WritableKeyPath<Track, Bool>) {
        let id = track.id
        model.mutate { p in
            if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i][keyPath: keyPath].toggle() }
        }
    }
}

private struct RulerView: View {
    @Environment(EditorModel.self) private var model
    let width: CGFloat

    var body: some View {
        let zoom = model.zoom
        Canvas { ctx, size in
            let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
            let major = steps.first { $0 * zoom >= 80 } ?? 300
            let minor = major / 5
            var i = 0
            while Double(i) * minor * zoom <= size.width {
                let t = Double(i) * minor
                let x = t * zoom
                let isMajor = i % 5 == 0
                ctx.fill(Path(CGRect(x: x, y: isMajor ? 12 : 19, width: 1, height: isMajor ? 14 : 7)),
                         with: .color(.white.opacity(isMajor ? 0.55 : 0.25)))
                if isMajor {
                    ctx.draw(Text(Self.label(t, step: major)).font(.system(size: 10).monospacedDigit())
                                .foregroundColor(.secondary),
                             at: CGPoint(x: x + 3, y: 6), anchor: .leading)
                }
                i += 1
            }
        }
        .frame(width: width, height: TimelineView.rulerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            if model.isPlaying { model.togglePlay() }
            model.seek(to: Micros(max(0, value.location.x) / model.zoom * 1_000_000))
        })
        .help("Arraste para navegar")
    }

    static func label(_ t: Double, step: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        return step < 1 ? String(format: "%02d:%04.1f", minutes, seconds) : String(format: "%02d:%02d", minutes, Int(seconds))
    }
}

private struct PlayheadView: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .frame(height: 12)
            Rectangle().frame(width: 1.5)
        }
        .foregroundStyle(Theme.playhead)
        .frame(width: 12, height: height)
        .allowsHitTesting(false)
    }
}

private struct TrackRow: View {
    @Environment(EditorModel.self) private var model
    let track: Track
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(track.isMain ? 0.06 : 0.03))
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    model.selection = nil
                    model.seek(to: Micros(location.x / model.zoom * 1_000_000))
                }
            ForEach(track.segments) { seg in
                SegmentView(segment: seg, track: track)
                    .offset(x: CGFloat(seg.targetStart.seconds * model.zoom), y: 3)
            }
            if track.isMain {
                ForEach(Array(track.segments.dropLast().enumerated()), id: \.element.id) { index, seg in
                    transitionButton(seg, next: track.segments[index + 1])
                }
            }
        }
        .frame(width: width, height: TimelineView.rowHeight)
        .opacity(track.hidden ? 0.45 : 1)
    }

    /// Botão na junção entre dois clipes, como no CapCut.
    private func transitionButton(_ seg: Segment, next: Segment) -> some View {
        let junction = Double(seg.targetEnd + next.targetStart) / 2 / 1_000_000
        return Button {
            model.selection = seg.id
            model.inspectorTab = .transition
        } label: {
            Image(systemName: seg.transition == nil ? "plus" : "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(seg.transition == nil ? Theme.panelRaised : Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(seg.transition.map { "Transição: \($0.kind.displayName)" } ?? "Adicionar transição")
        .offset(x: CGFloat(junction * model.zoom) - 9, y: TimelineView.rowHeight / 2 - 9)
    }
}

private struct SegmentView: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment
    let track: Track

    private var material: Material? { model.project.material(segment.materialId) }
    private var width: CGFloat { max(4, CGFloat(segment.targetDuration.seconds * model.zoom)) }
    private var height: CGFloat { TimelineView.rowHeight - 6 }
    private var isSelected: Bool { model.selection == segment.id }
    private static let rowStride = TimelineView.rowHeight + TimelineView.rowSpacing

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            badges
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1))
        .overlay(alignment: .leading) { if isSelected { handle(leading: true) } }
        .overlay(alignment: .trailing) { if isSelected { handle(leading: false) } }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in model.dragMove(segment.id, dx: value.translation.width) }
                .onEnded { value in
                    model.endDragMove(segment.id, rows: Int((value.translation.height / Self.rowStride).rounded()))
                })
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

    @ViewBuilder
    private var content: some View {
        if let text = segment.text {
            ZStack(alignment: .leading) {
                Theme.textClip
                Label(text.text.replacingOccurrences(of: "\n", with: " "), systemImage: "textformat")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        } else if let m = material, m.kind == .audio {
            ZStack(alignment: .leading) {
                Theme.audioClip
                // Linha de volume
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(height: 1)
                    .offset(y: height * (0.5 - CGFloat(min(segment.volume, 1)) * 0.35))
                Label(m.name, systemImage: "music.note")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        } else if let m = material {
            ThumbnailStrip(material: m, segment: segment, images: model.thumbnails[m.id] ?? [])
        } else {
            Color.gray
        }
    }

    @ViewBuilder
    private var badges: some View {
        let items = badgeItems
        if !items.isEmpty, width > 40 {
            HStack(spacing: 3) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 3)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(4)
        }
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
        Rectangle()
            .fill(Color.white)
            .frame(width: 7)
            .overlay(Image(systemName: leading ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in model.dragTrim(segment.id, leading: leading, dx: value.translation.width) }
                    .onEnded { _ in model.endGesture() })
    }
}

/// Miniaturas repetidas ao longo do clipe, escolhidas pelo tempo de origem.
private struct ThumbnailStrip: View {
    let material: Material
    let segment: Segment
    let images: [CGImage]

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(material.kind == .photo ? Theme.photoClip : Theme.videoClip))
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
