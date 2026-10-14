import OpenFrameCore
import SwiftUI

/// Aba Animação: grades de Entrada, Saída e Loop com miniaturas que tocam no
/// hover e no selecionado (feitas pelo núcleo com o mesmo render da exportação).
struct AnimationTab: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment

    var body: some View {
        let isText = segment.text != nil
        let kinds = AnimationKind.allCases.filter { isText || !$0.textOnly }
        let subject = ThumbSubject(segment, thumbnails: model.thumbnails)
        AnimationGrid(title: "Entrada", segment: segment, keyPath: \.animationIn, kinds: kinds, isEntry: true, subject: subject)
        AnimationGrid(title: "Saída", segment: segment, keyPath: \.animationOut, kinds: kinds, isEntry: false, subject: subject)
        LoopGrid(segment: segment, subject: subject)
    }
}

/// O que aparece nas miniaturas: o próprio texto (curto) com o estilo dele, ou a
/// miniatura do material.
struct ThumbSubject {
    let key: AnyHashable
    let subject: AnimationPreview.Subject

    init?(_ seg: Segment, thumbnails: [UUID: [CGImage]]) {
        if let text = seg.text {
            let content = TextContent(text: Self.short(text.text), style: text.style)
            key = content
            subject = .text(content)
        } else if let id = seg.materialId, let image = thumbnails[id]?.first {
            key = id
            subject = .image(image)
        } else {
            return nil
        }
    }

    /// Primeira linha, até ~14 caracteres sem cortar palavras.
    static func short(_ text: String) -> String {
        let limit = 14
        let line = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !line.isEmpty else { return "Aa" }
        guard line.count > limit else { return line }
        var out = ""
        for word in line.split(separator: " ") {
            let next = out.isEmpty ? String(word) : out + " " + word
            if next.count > limit, !out.isEmpty { break }
            out = next
        }
        return out.count > limit ? String(out.prefix(limit - 2)) + "…" : out
    }
}

private struct AnimationGrid: View {
    @Environment(EditorModel.self) private var model
    let title: String
    let segment: Segment
    let keyPath: WritableKeyPath<Segment, SegmentAnimation?>
    let kinds: [AnimationKind]
    let isEntry: Bool
    let subject: ThumbSubject?

    var body: some View {
        let id = segment.id
        let current = segment[keyPath: keyPath]
        SectionHeader(title: title)
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ChoiceTile(title: "Nenhuma", selected: current == nil, twoLineTitle: true) {
                model.mutate { TimelineEditor.update(&$0, segment: id) { $0[keyPath: keyPath] = nil } }
            } hoverPreview: { _ in
                AnimatedThumb(subject: subject, part: nil, playing: false, symbol: "nosign", selected: false)
            }
            ForEach(kinds) { kind in
                let selected = current?.kind == kind
                ChoiceTile(title: kind.displayName, selected: selected, twoLineTitle: true) {
                    choose(kind)
                } hoverPreview: { hovering in
                    AnimatedThumb(subject: subject, part: isEntry ? .entry(kind) : .exit(kind),
                                  playing: hovering || selected, symbol: AnimationIcons.symbol(kind), selected: selected)
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

private struct LoopGrid: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment
    let subject: ThumbSubject?

    var body: some View {
        let id = segment.id
        let current = segment.animationLoop
        SectionHeader(title: "Loop")
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ChoiceTile(title: "Nenhum", selected: current == nil, twoLineTitle: true) {
                model.mutate { TimelineEditor.update(&$0, segment: id) { $0.animationLoop = nil } }
            } hoverPreview: { _ in
                AnimatedThumb(subject: subject, part: nil, playing: false, symbol: "nosign", selected: false)
            }
            ForEach(LoopKind.allCases) { kind in
                let selected = current?.kind == kind
                ChoiceTile(title: kind.displayName, selected: selected, twoLineTitle: true) {
                    choose(kind)
                } hoverPreview: { hovering in
                    AnimatedThumb(subject: subject, part: .loop(kind), playing: hovering || selected,
                                  symbol: AnimationIcons.symbol(kind), selected: selected)
                }
                .help(kind.displayName)
            }
        }
        if current != nil {
            ParamSlider(title: "Ciclo", value: loopValue(\.periodSeconds), range: 0.5...6, defaultValue: 2,
                        format: { String(format: "%.1fs", $0) })
                .padding(.top, 4)
            ParamSlider(title: "Intensidade", value: loopValue(\.intensity), range: 0...1, defaultValue: 0.5,
                        format: { String(format: "%.0f%%", $0 * 100) })
        }
        Text("O loop se repete durante todo o clipe, junto com a entrada e a saída.")
            .font(Theme.font(11))
            .foregroundStyle(Theme.textTertiary)
    }

    private func loopValue(_ keyPath: WritableKeyPath<LoopAnimation, Double>) -> Binding<Double> {
        let id = segment.id
        return Binding(
            get: { model.project.segment(id)?.animationLoop?[keyPath: keyPath] ?? 0 },
            set: { v in
                model.mutate(coalesce: "\(id)loop\(keyPath)") {
                    TimelineEditor.update(&$0, segment: id) { $0.animationLoop?[keyPath: keyPath] = v }
                }
            })
    }

    private func choose(_ kind: LoopKind) {
        let id = segment.id
        model.mutate {
            TimelineEditor.update(&$0, segment: id) { seg in
                let old = seg.animationLoop
                seg.animationLoop = LoopAnimation(kind: kind, period: old?.period ?? 2_000_000, intensity: old?.intensity ?? 0.5)
            }
        }
        guard let seg = model.project.segment(id), let loop = seg.animationLoop else { return }
        model.playExcerpt(AnimationPlayback.loop(seg, period: loop.period, playhead: model.playhead))
    }
}

/// Miniatura de uma animação: o quadro de repouso quando parada e o ciclo quando toca.
/// Sem os quadros prontos, mostra um símbolo.
private struct AnimatedThumb: View {
    @Environment(EditorModel.self) private var model
    let subject: ThumbSubject?
    /// `nil` = só o repouso ("Nenhuma").
    let part: AnimationPreview.Part?
    let playing: Bool
    let symbol: String
    let selected: Bool

    /// Pixels das miniaturas (exibidas em 2x, cabem no cartão de ~90×50 pt).
    static let pixelSize = CGSize(width: 180, height: 100)

    var body: some View {
        let store = model.animationStrips
        let restKey = subject.map { StripKey(subject: $0.key, part: nil) }
        let stripKey = subject.flatMap { s in part.map { StripKey(subject: s.key, part: $0) } }
        let rest = restKey.flatMap { store.strip($0) }?.first
        let frames = stripKey.flatMap { store.strip($0) }
        Group {
            if playing, let frames, let part {
                FrameStripView(frames: frames, rest: 0, playing: true, cycle: Self.cycle(part)) { EmptyView() }
            } else if let rest {
                Image(decorative: rest, scale: 2).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: symbol)
                    .font(Theme.font(16, .light))
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
            }
        }
        .task(id: restKey) { request(urgent: false) }
        .onChange(of: playing) { if playing { request(urgent: true) } }
    }

    private func request(urgent: Bool) {
        guard let subject else { return }
        let store = model.animationStrips
        let s = subject.subject
        let size = Self.pixelSize
        store.request(StripKey(subject: subject.key, part: nil), urgent: urgent) {
            // A saída começa no repouso.
            Array(AnimationPreview.frames(subject: s, part: .exit(.fade), size: size, count: 1).prefix(1))
        }
        guard let part else { return }
        let count = Self.frameCount(part)
        store.request(StripKey(subject: subject.key, part: part), urgent: urgent || playing) {
            AnimationPreview.frames(subject: s, part: part, size: size, count: count)
        }
    }

    /// Duração de um ciclo da prévia do núcleo: entrada/saída de 0,6 s + 0,6 s de pausa;
    /// loop, dois períodos padrão.
    static func cycle(_ part: AnimationPreview.Part) -> Double {
        switch part {
        case .entry, .exit: 1.2
        case .loop(let kind): 2 * LoopAnimation(kind: kind).period.seconds
        }
    }

    static func frameCount(_ part: AnimationPreview.Part) -> Int {
        switch part {
        case .entry, .exit: 30
        case .loop: 60
        }
    }
}

private extension LoopAnimation {
    var periodSeconds: Double {
        get { period.seconds }
        set { period = Time.seconds(newValue) }
    }
}

private struct StripKey: Hashable {
    let subject: AnyHashable
    let part: AnimationPreview.Part?
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

    static func symbol(_ kind: LoopKind) -> String {
        switch kind {
        case .float: "arrow.up.and.down"
        case .pulse: "circle.circle"
        case .glow: "sun.max"
        case .shine: "sparkle"
        }
    }
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
    /// Segundos de um ciclo completo dos quadros.
    let cycle: Double
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var start = Date()

    var body: some View {
        if let frames, !frames.isEmpty {
            let fps = Double(frames.count) / max(cycle, 0.1)
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
