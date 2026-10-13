import Foundation

/// Operações de edição da timeline. Todas são funções puras sobre `Project`,
/// o que permite testá-las sem interface e implementar desfazer por snapshot.
public enum TimelineEditor {
    public static let minDuration: Micros = 100_000
    public static let defaultPhotoDuration: Micros = 3 * Time.second
    public static let defaultTextDuration: Micros = 3 * Time.second

    // MARK: - Layout

    /// Reposiciona a faixa principal: clipes encostados, com sobreposição
    /// apenas onde há transição.
    public static func relayoutMain(_ p: inout Project) {
        guard let mi = p.mainTrackIndex else { return }
        var t: Micros = 0
        let count = p.tracks[mi].segments.count
        for i in 0..<count {
            p.tracks[mi].segments[i].targetStart = t
            let seg = p.tracks[mi].segments[i]
            var overlap: Micros = 0
            if i + 1 < count, let tr = seg.transition {
                let next = p.tracks[mi].segments[i + 1]
                overlap = max(0, min(tr.duration, seg.targetDuration / 2, next.targetDuration / 2))
            }
            t = seg.targetEnd - overlap
        }
    }

    public static func removeEmptyTracks(_ p: inout Project) {
        p.tracks.removeAll { !$0.isMain && $0.segments.isEmpty }
    }

    private static func normalize(_ p: inout Project) {
        for t in p.tracks.indices where !p.tracks[t].isMain {
            p.tracks[t].segments.sort { $0.targetStart < $1.targetStart }
        }
        relayoutMain(&p)
        removeEmptyTracks(&p)
    }

    // MARK: - Adição

    public static func sourceRange(for m: Material) -> TimeRange {
        switch m.kind {
        case .photo: TimeRange(start: 0, duration: defaultPhotoDuration)
        case .video, .audio: TimeRange(start: 0, duration: max(m.duration, minDuration))
        }
    }

    /// Adiciona o material: visual vai para o fim da faixa principal; áudio
    /// vai para uma faixa de áudio livre na posição `time`.
    @discardableResult
    public static func addMedia(_ m: Material, to p: inout Project, at time: Micros = 0) -> UUID {
        if !p.materials.contains(where: { $0.id == m.id }) { p.materials.append(m) }
        if m.kind == .audio {
            let seg = Segment(materialId: m.id, source: sourceRange(for: m), targetStart: max(0, time))
            place(seg, kind: .audio, in: &p)
            return seg.id
        }
        if p.mainTrackIndex == nil {
            p.tracks.insert(Track(kind: .video, isMain: true), at: 0)
        }
        let mi = p.mainTrackIndex!
        let end = p.tracks[mi].segments.last?.targetEnd ?? 0
        let seg = Segment(materialId: m.id, source: sourceRange(for: m), targetStart: end)
        p.tracks[mi].segments.append(seg)
        relayoutMain(&p)
        return seg.id
    }

    /// Adiciona como sobreposição (picture-in-picture) a partir de `time`.
    @discardableResult
    public static func addOverlay(_ m: Material, to p: inout Project, at time: Micros) -> UUID {
        if !p.materials.contains(where: { $0.id == m.id }) { p.materials.append(m) }
        var seg = Segment(materialId: m.id, source: sourceRange(for: m), targetStart: max(0, time))
        seg.transform.scale = 0.5
        place(seg, kind: .video, in: &p)
        return seg.id
    }

    @discardableResult
    public static func addText(_ content: TextContent, to p: inout Project, at time: Micros, duration: Micros = defaultTextDuration) -> UUID {
        let seg = Segment.text(content, at: max(0, time), duration: max(duration, minDuration))
        place(seg, kind: .text, in: &p)
        return seg.id
    }

    /// Coloca o segmento na primeira faixa não principal do tipo com espaço
    /// livre; cria uma nova faixa se nenhuma servir.
    private static func place(_ seg: Segment, kind: TrackKind, in p: inout Project) {
        if let t = freeTrack(kind: kind, range: seg.targetRange, in: p, excluding: seg.id) {
            p.tracks[t].segments.append(seg)
            p.tracks[t].segments.sort { $0.targetStart < $1.targetStart }
        } else {
            var track = Track(kind: kind)
            track.segments = [seg]
            p.tracks.append(track)
        }
    }

    public static func freeTrack(kind: TrackKind, range: TimeRange, in p: Project, excluding id: UUID?) -> Int? {
        p.tracks.indices.first { t in
            let track = p.tracks[t]
            guard track.kind == kind, !track.isMain else { return false }
            return !track.segments.contains { other in
                other.id != id && other.targetStart < range.end && range.start < other.targetEnd
            }
        }
    }

    // MARK: - Edição

    /// Divide o segmento em `time`. Retorna o id da parte direita.
    @discardableResult
    public static func split(_ p: inout Project, segment id: UUID, at time: Micros) -> UUID? {
        guard let (t, i) = p.locate(id) else { return nil }
        let seg = p.tracks[t].segments[i]
        guard time - seg.targetStart >= minDuration, seg.targetEnd - time >= minDuration else { return nil }

        let offsetSrc = Micros((Double(time - seg.targetStart) * seg.speed).rounded())
        var left = seg
        var right = seg
        right.id = UUID()
        left.source.duration = offsetSrc
        right.source.duration = seg.source.duration - offsetSrc
        if seg.text == nil, p.material(seg.materialId)?.kind != .photo {
            right.source.start = seg.source.start + offsetSrc
        }
        right.targetStart = time
        left.transition = nil
        left.animationOut = nil
        left.fadeOut = 0
        right.animationIn = nil
        right.fadeIn = 0
        p.tracks[t].segments.replaceSubrange(i...i, with: [left, right])
        normalize(&p)
        return right.id
    }

    public static func delete(_ p: inout Project, segment id: UUID) {
        guard let (t, i) = p.locate(id) else { return }
        p.tracks[t].segments.remove(at: i)
        normalize(&p)
    }

    @discardableResult
    public static func duplicate(_ p: inout Project, segment id: UUID) -> UUID? {
        guard let (t, i) = p.locate(id) else { return nil }
        var copy = p.tracks[t].segments[i]
        copy.id = UUID()
        if p.tracks[t].isMain {
            p.tracks[t].segments.insert(copy, at: i + 1)
        } else {
            copy.targetStart = p.tracks[t].segments[i].targetEnd
            place(copy, kind: p.tracks[t].kind, in: &p)
        }
        normalize(&p)
        return copy.id
    }

    /// Move horizontalmente um segmento de faixa não principal (sem resolver
    /// sobreposições — chame `resolveOverlap` ao soltar).
    public static func move(_ p: inout Project, segment id: UUID, toStart start: Micros) {
        guard let (t, i) = p.locate(id), !p.tracks[t].isMain else { return }
        p.tracks[t].segments[i].targetStart = max(0, start)
    }

    /// Reordena um segmento da faixa principal pela posição do centro.
    public static func reorderMain(_ p: inout Project, segment id: UUID, toCenter center: Micros) {
        guard let (t, i) = p.locate(id), p.tracks[t].isMain else { return }
        let seg = p.tracks[t].segments.remove(at: i)
        let index = p.tracks[t].segments.filter { ($0.targetStart + $0.targetEnd) / 2 < center }.count
        p.tracks[t].segments.insert(seg, at: index)
        relayoutMain(&p)
    }

    /// Se o segmento ficou sobreposto a outro na mesma faixa, manda-o para
    /// uma faixa livre do mesmo tipo (criando uma se preciso).
    public static func resolveOverlap(_ p: inout Project, segment id: UUID) {
        guard let (t, i) = p.locate(id), !p.tracks[t].isMain else { return }
        let seg = p.tracks[t].segments[i]
        let overlaps = p.tracks[t].segments.contains {
            $0.id != id && $0.targetStart < seg.targetEnd && seg.targetStart < $0.targetEnd
        }
        if overlaps {
            p.tracks[t].segments.remove(at: i)
            place(seg, kind: p.tracks[t].kind, in: &p)
        }
        normalize(&p)
    }

    /// Move o segmento para outra faixa do mesmo tipo de mídia.
    public static func moveToTrack(_ p: inout Project, segment id: UUID, track target: Int) {
        guard let (t, i) = p.locate(id), target != t, p.tracks.indices.contains(target) else { return }
        let seg = p.tracks[t].segments[i]
        let dest = p.tracks[target]
        let isText = seg.text != nil
        let isAudio = p.material(seg.materialId)?.kind == .audio
        let destOK: Bool = switch dest.kind {
        case .text: isText
        case .audio: isAudio
        case .video: !isText && !isAudio
        }
        guard destOK else { return }
        p.tracks[t].segments.remove(at: i)
        if dest.isMain {
            let center = (seg.targetStart + seg.targetEnd) / 2
            let index = p.tracks[target].segments.filter { ($0.targetStart + $0.targetEnd) / 2 < center }.count
            p.tracks[target].segments.insert(seg, at: index)
        } else {
            p.tracks[target].segments.append(seg)
        }
        normalize(&p)
        resolveOverlap(&p, segment: id)
    }

    /// Apara o início do segmento até `newStart` (tempo da timeline).
    public static func trimStart(_ p: inout Project, segment id: UUID, to newStart: Micros) {
        guard let (t, i) = p.locate(id) else { return }
        var s = p.tracks[t].segments[i]
        let timed = isTimed(s, in: p)
        var deltaSrc = Micros((Double(newStart - s.targetStart) * s.speed).rounded())
        if timed { deltaSrc = max(deltaSrc, -s.source.start) }
        if !p.tracks[t].isMain { deltaSrc = max(deltaSrc, -Micros(Double(s.targetStart) * s.speed)) }
        deltaSrc = min(deltaSrc, s.source.duration - Micros(Double(minDuration) * s.speed))
        if timed { s.source.start += deltaSrc }
        s.source.duration -= deltaSrc
        s.targetStart += Micros((Double(deltaSrc) / s.speed).rounded())
        p.tracks[t].segments[i] = s
        normalize(&p)
    }

    /// Apara o fim do segmento até `newEnd` (tempo da timeline).
    public static func trimEnd(_ p: inout Project, segment id: UUID, to newEnd: Micros) {
        guard let (t, i) = p.locate(id) else { return }
        var s = p.tracks[t].segments[i]
        let targetDur = max(minDuration, newEnd - s.targetStart)
        var srcDur = Micros((Double(targetDur) * s.speed).rounded())
        if isTimed(s, in: p), let m = p.material(s.materialId) {
            srcDur = min(srcDur, m.duration - s.source.start)
        }
        s.source.duration = max(srcDur, Micros(Double(minDuration) * s.speed))
        p.tracks[t].segments[i] = s
        normalize(&p)
    }

    public static func setSpeed(_ p: inout Project, segment id: UUID, speed: Double) {
        update(&p, segment: id) { $0.speed = min(max(speed, 0.1), 10) }
    }

    /// Altera um segmento e reaplica o layout da faixa principal.
    public static func update(_ p: inout Project, segment id: UUID, _ change: (inout Segment) -> Void) {
        guard let (t, i) = p.locate(id) else { return }
        change(&p.tracks[t].segments[i])
        relayoutMain(&p)
    }

    /// Vídeo e áudio têm duração limitada pelo arquivo; foto e texto não.
    private static func isTimed(_ s: Segment, in p: Project) -> Bool {
        guard let m = p.material(s.materialId) else { return false }
        return m.kind != .photo
    }

    // MARK: - Ímã (snap)

    public static func snapPoints(_ p: Project, excluding id: UUID?, extra: [Micros] = []) -> [Micros] {
        var points: [Micros] = [0] + extra
        for track in p.tracks {
            for s in track.segments where s.id != id {
                points.append(s.targetStart)
                points.append(s.targetEnd)
            }
        }
        return points
    }

    public static func snap(_ t: Micros, to points: [Micros], threshold: Micros) -> Micros {
        var best = t
        var bestDistance = threshold + 1
        for point in points {
            let d = abs(point - t)
            if d <= threshold, d < bestDistance {
                best = point
                bestDistance = d
            }
        }
        return best
    }
}
