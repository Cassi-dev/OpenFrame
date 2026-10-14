import OpenFrameCore
import SwiftUI

/// Aba Animação: grades de Entrada e Saída com miniaturas que tocam no hover.
struct AnimationTab: View {
    let segment: Segment

    var body: some View {
        let isText = segment.text != nil
        let kinds = AnimationKind.allCases.filter { isText || !$0.textOnly }
        AnimationGrid(title: "Entrada", segment: segment, keyPath: \.animationIn, kinds: kinds, isEntry: true)
        AnimationGrid(title: "Saída", segment: segment, keyPath: \.animationOut, kinds: kinds, isEntry: false)
    }
}

private struct AnimationGrid: View {
    @Environment(EditorModel.self) private var model
    let title: String
    let segment: Segment
    let keyPath: WritableKeyPath<Segment, SegmentAnimation?>
    let kinds: [AnimationKind]
    let isEntry: Bool

    var body: some View {
        let id = segment.id
        let current = segment[keyPath: keyPath]
        SectionHeader(title: title)
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ChoiceTile(title: "Nenhuma", selected: current == nil, twoLineTitle: true) {
                model.mutate { TimelineEditor.update(&$0, segment: id) { $0[keyPath: keyPath] = nil } }
            } hoverPreview: { _ in
                Image(systemName: "nosign").font(Theme.font(15, .light)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(kinds) { kind in
                let selected = current?.kind == kind
                ChoiceTile(title: kind.displayName, selected: selected, twoLineTitle: true) {
                    choose(kind)
                } hoverPreview: { _ in
                    Image(systemName: AnimationIcons.symbol(kind))
                        .font(Theme.font(16, .light))
                        .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                }
                .help(kind.displayName)
            }
        }
        if current != nil {
            ParamSlider(title: "Duração",
                        value: Binding(get: { model.project.segment(id)?[keyPath: keyPath]?.duration.seconds ?? 0.5 },
                                       set: { v in
                                           model.mutate(coalesce: "\(id)\(keyPath)") {
                                               TimelineEditor.update(&$0, segment: id) { $0[keyPath: keyPath]?.duration = Time.seconds(v) }
                                           }
                                       }),
                        range: 0.1...3, defaultValue: 0.5, format: { String(format: "%.1fs", $0) })
                .padding(.top, 4)
        }
    }

    /// Aplica o efeito e toca o trecho dele no preview.
    private func choose(_ kind: AnimationKind) {
        let id = segment.id
        model.mutate {
            TimelineEditor.update(&$0, segment: id) { seg in
                seg[keyPath: keyPath] = SegmentAnimation(kind: kind, duration: seg[keyPath: keyPath]?.duration ?? 500_000)
            }
        }
        guard let seg = model.project.segment(id), let anim = seg[keyPath: keyPath] else { return }
        model.playExcerpt(isEntry ? AnimationPlayback.entry(seg, duration: anim.duration)
                                  : AnimationPlayback.exit(seg, duration: anim.duration))
    }
}

/// Trechos do preview tocados ao escolher um efeito.
enum AnimationPlayback {
    /// Depois da entrada, um respiro no repouso.
    static let entryTail: Micros = 300_000

    /// Do início do clipe até o fim da animação + 0,3 s.
    static func entry(_ seg: Segment, duration: Micros) -> Range<Micros> {
        seg.targetStart..<max(seg.targetStart, min(seg.targetEnd, seg.targetStart + duration + entryTail))
    }

    /// Da saída até o fim do clipe.
    static func exit(_ seg: Segment, duration: Micros) -> Range<Micros> {
        max(seg.targetStart, seg.targetEnd - duration)..<seg.targetEnd
    }

    /// Dois ciclos a partir do playhead, ou do início do clipe se ele estiver fora.
    static func loop(_ seg: Segment, period: Micros, playhead: Micros) -> Range<Micros> {
        let start = (seg.targetStart..<seg.targetEnd).contains(playhead) ? playhead : seg.targetStart
        return start..<max(start, min(seg.targetEnd, start + 2 * period))
    }
}

/// Símbolo provisório enquanto a miniatura animada não fica pronta.
enum AnimationIcons {
    private static let symbols: [String: String] = [
        "fade": "circle.lefthalf.filled", "zoomIn": "plus.magnifyingglass", "zoomOut": "minus.magnifyingglass",
        "slideLeft": "arrow.left", "slideRight": "arrow.right", "slideUp": "arrow.up", "slideDown": "arrow.down",
        "spin": "arrow.clockwise", "typewriter": "character.cursor.ibeam",
    ]

    static func symbol(_ kind: AnimationKind) -> String { symbols[kind.rawValue] ?? "sparkles" }
}

// MARK: - Miniaturas animadas

/// Quadros das miniaturas, gerados em segundo plano um de cada vez e guardados.
/// Pedidos urgentes (hover, selecionado) passam à frente da fila.
@MainActor
@Observable
final class FrameStripStore {
    private(set) var strips: [AnyHashable: [CGImage]] = [:]
    @ObservationIgnored private var queue: [(key: AnyHashable, make: @Sendable () -> [CGImage])] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    func strip(_ key: AnyHashable) -> [CGImage]? { strips[key] }

    func request(_ key: AnyHashable, urgent: Bool, make: @escaping @Sendable () -> [CGImage]) {
        guard strips[key] == nil else { return }
        if let i = queue.firstIndex(where: { $0.key == key }) {
            guard urgent else { return }
            queue.insert(queue.remove(at: i), at: 0)
        } else if urgent {
            queue.insert((key, make), at: 0)
        } else {
            queue.append((key, make))
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let item = self?.dequeue() {
                let frames = await Task.detached(priority: .userInitiated) { item.make() }.value
                self?.store(frames, for: item.key)
            }
            self?.worker = nil
        }
    }

    private func dequeue() -> (key: AnyHashable, make: @Sendable () -> [CGImage])? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    private func store(_ frames: [CGImage], for key: AnyHashable) {
        if strips.count > 400 { strips.removeAll() }
        strips[key] = frames
    }
}

/// Toca os quadros em ciclo enquanto `playing`; parada, mostra o quadro `rest`.
struct FrameStripView<Placeholder: View>: View {
    let frames: [CGImage]?
    let rest: Int
    let playing: Bool
    var fps: Double = 24
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var start = Date()

    var body: some View {
        if let frames, !frames.isEmpty {
            SwiftUI.TimelineView(.animation(minimumInterval: 1 / fps, paused: !playing)) { context in
                let index = playing ? Int(max(0, context.date.timeIntervalSince(start)) * fps) % frames.count
                                    : min(max(rest, 0), frames.count - 1)
                Image(decorative: frames[index], scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .onChange(of: playing) { if playing { start = Date() } }
        } else {
            placeholder()
        }
    }
}
