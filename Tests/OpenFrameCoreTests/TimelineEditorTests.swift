import Foundation
import Testing
@testable import OpenFrameCore

private func video(_ seconds: Double, name: String = "clip.mov") -> Material {
    Material(kind: .video, path: "/tmp/\(name)", name: name, duration: Time.seconds(seconds),
             width: 1920, height: 1080, hasAudio: true)
}

private func audio(_ seconds: Double) -> Material {
    Material(kind: .audio, path: "/tmp/song.m4a", name: "song.m4a", duration: Time.seconds(seconds),
             width: 0, height: 0, hasAudio: true)
}

private func mainSegments(_ p: Project) -> [Segment] {
    p.tracks[p.mainTrackIndex!].segments
}

@Suite("Timeline")
struct TimelineEditorTests {
    @Test("Clipes visuais entram encostados na faixa principal")
    func appendsToMainTrack() {
        var p = Project()
        TimelineEditor.addMedia(video(4), to: &p)
        TimelineEditor.addMedia(video(2, name: "b.mov"), to: &p)
        let photo = Material(kind: .photo, path: "/tmp/a.png", name: "a.png", duration: 0, width: 800, height: 600, hasAudio: false)
        TimelineEditor.addMedia(photo, to: &p)

        let segs = mainSegments(p)
        #expect(segs.map(\.targetStart) == [0, Time.seconds(4), Time.seconds(6)])
        #expect(segs[2].targetDuration == TimelineEditor.defaultPhotoDuration)
        #expect(p.duration == Time.seconds(9))
        #expect(p.materials.count == 3)
    }

    @Test("Dividir mantém o conteúdo contínuo")
    func split() throws {
        var p = Project()
        let id = TimelineEditor.addMedia(video(10), to: &p)
        let rightId = try #require(TimelineEditor.split(&p, segment: id, at: Time.seconds(4)))

        let segs = mainSegments(p)
        #expect(segs.count == 2)
        #expect(segs[0].source == TimeRange(start: 0, duration: Time.seconds(4)))
        #expect(segs[1].id == rightId)
        #expect(segs[1].source == TimeRange(start: Time.seconds(4), duration: Time.seconds(6)))
        #expect(segs[1].targetStart == Time.seconds(4))
    }

    @Test("Dividir com velocidade converte para o tempo do arquivo")
    func splitWithSpeed() throws {
        var p = Project()
        let id = TimelineEditor.addMedia(video(10), to: &p)
        TimelineEditor.setSpeed(&p, segment: id, speed: 2) // 5 s na timeline
        #expect(p.duration == Time.seconds(5))
        _ = try #require(TimelineEditor.split(&p, segment: id, at: Time.seconds(1)))
        let segs = mainSegments(p)
        #expect(segs[0].source.duration == Time.seconds(2))
        #expect(segs[1].source.start == Time.seconds(2))
        #expect(segs[1].targetDuration == Time.seconds(4))
    }

    @Test("Não divide perto demais das bordas")
    func splitRejectsEdges() {
        var p = Project()
        let id = TimelineEditor.addMedia(video(3), to: &p)
        #expect(TimelineEditor.split(&p, segment: id, at: 10_000) == nil)
        #expect(TimelineEditor.split(&p, segment: id, at: Time.seconds(3) - 10_000) == nil)
    }

    @Test("Apagar na faixa principal fecha o buraco (ripple)")
    func deleteRipples() {
        var p = Project()
        let a = TimelineEditor.addMedia(video(3), to: &p)
        TimelineEditor.addMedia(video(2, name: "b.mov"), to: &p)
        TimelineEditor.delete(&p, segment: a)
        #expect(mainSegments(p).map(\.targetStart) == [0])
        #expect(p.duration == Time.seconds(2))
    }

    @Test("Aparar respeita os limites do arquivo")
    func trimClamps() {
        var p = Project()
        let id = TimelineEditor.addMedia(video(5), to: &p)
        TimelineEditor.trimEnd(&p, segment: id, to: Time.seconds(20))
        #expect(p.segment(id)!.source.duration == Time.seconds(5))

        TimelineEditor.trimStart(&p, segment: id, to: Time.seconds(2))
        let s = p.segment(id)!
        #expect(s.source.start == Time.seconds(2))
        #expect(s.source.duration == Time.seconds(3))
        #expect(s.targetStart == 0) // faixa principal continua encostada no início

        TimelineEditor.trimStart(&p, segment: id, to: -Time.seconds(10))
        #expect(p.segment(id)!.source.start == 0)
    }

    @Test("Fotos podem ser esticadas sem limite")
    func photoTrim() {
        var p = Project()
        let photo = Material(kind: .photo, path: "/tmp/a.png", name: "a.png", duration: 0, width: 800, height: 600, hasAudio: false)
        let id = TimelineEditor.addMedia(photo, to: &p)
        TimelineEditor.trimEnd(&p, segment: id, to: Time.seconds(12))
        #expect(p.segment(id)!.targetDuration == Time.seconds(12))
        #expect(p.segment(id)!.source.start == 0)
    }

    @Test("Transição sobrepõe os clipes vizinhos")
    func transitionOverlap() {
        var p = Project()
        let a = TimelineEditor.addMedia(video(4), to: &p)
        TimelineEditor.addMedia(video(4, name: "b.mov"), to: &p)
        TimelineEditor.update(&p, segment: a) { $0.transition = Transition(kind: .dissolve, duration: Time.seconds(1)) }
        #expect(mainSegments(p)[1].targetStart == Time.seconds(3))
        #expect(p.duration == Time.seconds(7))

        // Transição maior que metade do clipe é limitada.
        TimelineEditor.update(&p, segment: a) { $0.transition?.duration = Time.seconds(10) }
        #expect(mainSegments(p)[1].targetStart == Time.seconds(2))
    }

    @Test("Sobreposições e textos vão para faixas próprias sem colidir")
    func overlayPlacement() {
        var p = Project()
        TimelineEditor.addMedia(video(10), to: &p)
        let o1 = TimelineEditor.addOverlay(video(3, name: "o1.mov"), to: &p, at: Time.seconds(1))
        let o2 = TimelineEditor.addOverlay(video(3, name: "o2.mov"), to: &p, at: Time.seconds(2))
        let o3 = TimelineEditor.addOverlay(video(2, name: "o3.mov"), to: &p, at: Time.seconds(5))
        #expect(p.locate(o1)!.track == p.locate(o3)!.track)
        #expect(p.locate(o1)!.track != p.locate(o2)!.track)

        let t = TimelineEditor.addText(TextContent(text: "Olá"), to: &p, at: Time.seconds(2))
        #expect(p.tracks[p.locate(t)!.track].kind == .text)
    }

    @Test("Áudio vai para faixa de áudio e cria outra se colidir")
    func audioPlacement() {
        var p = Project()
        let a = TimelineEditor.addMedia(audio(5), to: &p, at: 0)
        let b = TimelineEditor.addMedia(audio(5), to: &p, at: Time.seconds(2))
        #expect(p.tracks[p.locate(a)!.track].kind == .audio)
        #expect(p.locate(a)!.track != p.locate(b)!.track)
    }

    @Test("Reordenar a faixa principal pelo centro")
    func reorder() {
        var p = Project()
        let a = TimelineEditor.addMedia(video(2, name: "a.mov"), to: &p)
        let b = TimelineEditor.addMedia(video(2, name: "b.mov"), to: &p)
        TimelineEditor.reorderMain(&p, segment: a, toCenter: Time.seconds(3.5))
        #expect(mainSegments(p).map(\.id) == [b, a])
        #expect(mainSegments(p).map(\.targetStart) == [0, Time.seconds(2)])
    }

    /// Faixa principal com clipes das durações dadas, sem transições.
    private func mainProject(_ seconds: [Double]) -> (Project, [UUID]) {
        var p = Project()
        let ids = seconds.enumerated().map { i, s in
            TimelineEditor.addMedia(video(s, name: "\(i).mov"), to: &p)
        }
        return (p, ids)
    }

    @Test("Reordenar é simétrico: direita e esquerda trocam na mesma distância")
    func reorderIsSymmetric() {
        // [2, 3, 5] arrastando o do meio para a direita espelha [5, 3, 2] para a esquerda.
        // Os centros ficam a 4 s: troca só depois disso, nos dois sentidos (empate não troca).
        for step in 0...40 {
            let d = Double(step) * 0.25
            var right = mainProject([2, 3, 5])
            let rightCenter = (Time.seconds(2) + Time.seconds(5)) / 2
            TimelineEditor.reorderMain(&right.0, segment: right.1[1], toCenter: rightCenter + Time.seconds(d))
            var left = mainProject([5, 3, 2])
            let leftCenter = (Time.seconds(5) + Time.seconds(8)) / 2
            TimelineEditor.reorderMain(&left.0, segment: left.1[1], toCenter: leftCenter - Time.seconds(d))

            let movedRight = mainSegments(right.0).firstIndex { $0.id == right.1[1] } != 1
            let movedLeft = mainSegments(left.0).firstIndex { $0.id == left.1[1] } != 1
            #expect(movedRight == movedLeft, "d = \(d) s")
            #expect(movedRight == (d > 4), "d = \(d) s")
        }
    }

    @Test("Reordenar passa vários vizinhos com a mesma regra nos dois sentidos")
    func reorderAcrossSeveral() {
        var right = mainProject([2, 2, 2, 2, 2])
        TimelineEditor.reorderMain(&right.0, segment: right.1[0], toCenter: Time.seconds(1 + 6.5))
        #expect(mainSegments(right.0).map(\.id) == [right.1[1], right.1[2], right.1[3], right.1[0], right.1[4]])
        var left = mainProject([2, 2, 2, 2, 2])
        TimelineEditor.reorderMain(&left.0, segment: left.1[4], toCenter: Time.seconds(9 - 6.5))
        #expect(mainSegments(left.0).map(\.id) == [left.1[0], left.1[4], left.1[1], left.1[2], left.1[3]])
    }

    @Test("Ímã ao mover: a borda mais perto vence, nos dois sentidos")
    func snapMoveIsSymmetric() {
        let length = Time.seconds(20)
        let threshold = Time.seconds(0.1)
        let duration = Time.seconds(2)
        let points = [Time.seconds(5), Time.seconds(7.03), Time.seconds(12), Time.seconds(14.5)]
        let mirrored = points.map { length - $0 }
        for step in 0...1400 {
            let start = Time.seconds(Double(step) * 0.01)
            let right = TimelineEditor.snapMove(start: start, duration: duration, to: points,
                                                threshold: threshold, forward: true)
            let left = TimelineEditor.snapMove(start: length - start - duration, duration: duration,
                                               to: mirrored, threshold: threshold, forward: false)
            #expect(right + duration == length - left, "início \(start.seconds) s")
        }
        // Início a 0,04 s de um ponto e fim a 0,01 s de outro: o fim vence.
        #expect(TimelineEditor.snapMove(start: Time.seconds(5.04), duration: duration, to: points,
                                        threshold: threshold, forward: false) == Time.seconds(5.03))
    }

    @Test("Mover para cima de outro clipe manda para nova faixa")
    func resolveOverlap() {
        var p = Project()
        let a = TimelineEditor.addText(TextContent(text: "A"), to: &p, at: 0)
        let b = TimelineEditor.addText(TextContent(text: "B"), to: &p, at: Time.seconds(5))
        TimelineEditor.move(&p, segment: b, toStart: Time.seconds(1))
        TimelineEditor.resolveOverlap(&p, segment: b)
        #expect(p.locate(a)!.track != p.locate(b)!.track)
        #expect(p.segment(b)!.targetStart == Time.seconds(1))
    }

    @Test("Faixas vazias somem, a principal fica")
    func removesEmptyTracks() {
        var p = Project()
        let t = TimelineEditor.addText(TextContent(text: "A"), to: &p, at: 0)
        #expect(p.tracks.count == 2)
        TimelineEditor.delete(&p, segment: t)
        #expect(p.tracks.count == 1)
        #expect(p.tracks[0].isMain)
    }

    @Test("Duplicar insere logo depois")
    func duplicate() {
        var p = Project()
        let a = TimelineEditor.addMedia(video(2), to: &p)
        let copy = TimelineEditor.duplicate(&p, segment: a)
        #expect(mainSegments(p).map(\.id) == [a, copy!])
        #expect(p.duration == Time.seconds(4))
    }

    @Test("Soltar na faixa principal insere na junção mais próxima")
    func dropOnMain() {
        var p = Project()
        let a = TimelineEditor.addMedia(video(4), to: &p)
        let b = TimelineEditor.addMedia(video(4, name: "b.mov"), to: &p)
        let main = p.mainTrackIndex!
        let c = TimelineEditor.insertMedia(video(2, name: "c.mov"), into: &p, at: Time.seconds(3), track: main)
        #expect(mainSegments(p).map(\.id) == [a, c, b])
        #expect(p.segment(c)!.targetStart == Time.seconds(4))
        // Fora das faixas, o visual também vai para a principal.
        let d = TimelineEditor.insertMedia(video(1, name: "d.mov"), into: &p, at: 0, track: nil)
        #expect(mainSegments(p).first?.id == d)
    }

    @Test("Soltar sobre sobreposição ou texto cria sobreposição no tempo")
    func dropAsOverlay() {
        var p = Project()
        TimelineEditor.addMedia(video(10), to: &p)
        TimelineEditor.addText(TextContent(text: "A"), to: &p, at: 0)
        let text = p.tracks.firstIndex { $0.kind == .text }!
        let o = TimelineEditor.insertMedia(video(2, name: "o.mov"), into: &p, at: Time.seconds(5), track: text)
        let loc = p.locate(o)!
        #expect(p.tracks[loc.track].kind == .video && !p.tracks[loc.track].isMain)
        #expect(p.segment(o)!.targetStart == Time.seconds(5))
        // Na mesma faixa de sobreposição, se houver espaço.
        let o2 = TimelineEditor.insertMedia(video(2, name: "o2.mov"), into: &p, at: 0, track: loc.track)
        #expect(p.locate(o2)!.track == loc.track)
        // Colidindo, vai para outra faixa.
        let o3 = TimelineEditor.insertMedia(video(2, name: "o3.mov"), into: &p, at: Time.seconds(6), track: loc.track)
        #expect(p.locate(o3)!.track != loc.track)
    }

    @Test("Soltar áudio fica em faixa de áudio")
    func dropAudio() {
        var p = Project()
        TimelineEditor.addMedia(video(10), to: &p)
        let s = TimelineEditor.insertMedia(audio(3), into: &p, at: Time.seconds(2), track: p.mainTrackIndex)
        let loc = p.locate(s)!
        #expect(p.tracks[loc.track].kind == .audio)
        #expect(p.segment(s)!.targetStart == Time.seconds(2))
        let s2 = TimelineEditor.insertMedia(audio(3), into: &p, at: Time.seconds(6), track: loc.track)
        #expect(p.locate(s2)!.track == loc.track)
    }

    @Test("Mover entre faixas só para o mesmo tipo de mídia")
    func canMoveBetweenTracks() {
        var p = Project()
        let v = TimelineEditor.addMedia(video(4), to: &p)
        let t = TimelineEditor.addText(TextContent(text: "A"), to: &p, at: 0)
        let o = TimelineEditor.addOverlay(video(2, name: "o.mov"), to: &p, at: 0)
        let text = p.locate(t)!.track, overlay = p.locate(o)!.track
        #expect(TimelineEditor.canMove(p, segment: v, toTrack: overlay))
        #expect(!TimelineEditor.canMove(p, segment: v, toTrack: text))
        #expect(!TimelineEditor.canMove(p, segment: v, toTrack: p.mainTrackIndex!))
    }

    @Test("Ímã puxa para o ponto mais próximo dentro do limite")
    func snapping() {
        let points: [Micros] = [0, 1_000_000, 2_000_000]
        #expect(TimelineEditor.snap(1_030_000, to: points, threshold: 50_000) == 1_000_000)
        #expect(TimelineEditor.snap(1_300_000, to: points, threshold: 50_000) == 1_300_000)
    }
}
