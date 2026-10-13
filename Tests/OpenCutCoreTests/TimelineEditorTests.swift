import Foundation
import Testing
@testable import OpenCutCore

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

    @Test("Ímã puxa para o ponto mais próximo dentro do limite")
    func snapping() {
        let points: [Micros] = [0, 1_000_000, 2_000_000]
        #expect(TimelineEditor.snap(1_030_000, to: points, threshold: 50_000) == 1_000_000)
        #expect(TimelineEditor.snap(1_300_000, to: points, threshold: 50_000) == 1_300_000)
    }
}
