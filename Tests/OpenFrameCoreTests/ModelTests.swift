import CoreGraphics
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Legendas")
struct SubtitleTests {
    let sample = """
    1
    00:00:01,000 --> 00:00:03,500
    Primeira linha

    2
    00:00:04,250 --> 00:00:06,000 X1:10 X2:20
    Duas
    linhas

    lixo sem horário
    """

    @Test func parses() {
        let cues = SRT.parse(sample)
        #expect(cues.count == 2)
        #expect(cues[0] == SubtitleCue(start: 1_000_000, end: 3_500_000, text: "Primeira linha"))
        #expect(cues[1].start == 4_250_000)
        #expect(cues[1].text == "Duas\nlinhas")
    }

    @Test func roundTrips() {
        let cues = SRT.parse(sample)
        #expect(SRT.parse(SRT.serialize(cues)) == cues)
    }

    @Test func importsAsTextTrack() {
        var p = Project()
        SRT.importCues(SRT.parse(sample), into: &p)
        let track = p.tracks.last!
        #expect(track.kind == .text)
        #expect(track.segments.count == 2)
        #expect(SRT.cues(from: p) == SRT.parse(sample))
    }
}

@Suite("Projeto")
struct ProjectTests {
    @Test("Salvar e abrir preserva tudo")
    func roundTrip() throws {
        var p = Project()
        p.canvas.aspect = .r9x16
        p.canvas.background = .blur(0.4)
        let m = Material(kind: .video, path: "/tmp/a.mov", name: "a.mov", duration: 5_000_000, width: 1920, height: 1080, hasAudio: true)
        let id = TimelineEditor.addMedia(m, to: &p)
        TimelineEditor.update(&p, segment: id) {
            $0.adjust.brightness = 0.3
            $0.filter = FilterSetting(preset: .cinematic, intensity: 0.7)
            $0.effects = [VideoEffect(kind: .rgbSplit)]
            $0.animationIn = SegmentAnimation(kind: .zoomIn)
        }
        TimelineEditor.addText(TextContent(text: "Olá"), to: &p, at: 0)
        #expect(try ProjectStore.decode(ProjectStore.encode(p)) == p)
    }

    @Test("Canvas: proporção original vem do primeiro clipe")
    func canvasSize() {
        var p = Project()
        #expect(p.canvasSize(shortSide: 1080) == CGSize(width: 1920, height: 1080))
        let portrait = Material(kind: .video, path: "/tmp/p.mov", name: "p.mov", duration: 1_000_000, width: 1080, height: 1920, hasAudio: false)
        TimelineEditor.addMedia(portrait, to: &p)
        #expect(p.canvasSize(shortSide: 720) == CGSize(width: 720, height: 1280))
        p.canvas.aspect = .r1x1
        #expect(p.canvasSize(shortSide: 1080) == CGSize(width: 1080, height: 1080))
        p.canvas.aspect = .r4x3
        #expect(p.canvasSize(shortSide: 480) == CGSize(width: 640, height: 480))
    }
}

@Suite("Configurações de exportação")
struct ExportSettingsTests {
    func project(seconds: Double, aspect: AspectRatio = .r16x9) -> Project {
        var p = Project()
        p.canvas.aspect = aspect
        let m = Material(kind: .video, path: "/tmp/a.mov", name: "a.mov", duration: Time.seconds(seconds), width: 1920, height: 1080, hasAudio: true)
        TimelineEditor.addMedia(m, to: &p)
        return p
    }

    @Test("Resolução segue a proporção do canvas")
    func outputSize() {
        var s = ExportSettings()
        s.resolution = .p2160
        #expect(s.outputSize(for: project(seconds: 1)) == CGSize(width: 3840, height: 2160))
        #expect(s.outputSize(for: project(seconds: 1, aspect: .r9x16)) == CGSize(width: 2160, height: 3840))
        s.resolution = .custom
        s.customWidth = 1001
        s.customHeight = 501
        #expect(s.outputSize(for: project(seconds: 1)) == CGSize(width: 1000, height: 500))
    }

    @Test("Qualidade escala o bitrate; HEVC usa menos que H.264")
    func bitratePresets() {
        let size = CGSize(width: 1920, height: 1080)
        var s = ExportSettings()
        s.bitrateMode = .lower
        let lower = s.videoBitrate(size: size, duration: Time.second)
        s.bitrateMode = .recommended
        let recommended = s.videoBitrate(size: size, duration: Time.second)
        s.bitrateMode = .higher
        let higher = s.videoBitrate(size: size, duration: Time.second)
        #expect(lower < recommended && recommended < higher)
        #expect(abs(recommended - 6_220_800) < 1000) // 1920×1080×30×0,1

        s.bitrateMode = .recommended
        s.codec = .hevc
        #expect(s.videoBitrate(size: size, duration: Time.second) < recommended)

        s.frameRate = .fps60
        s.codec = .h264
        #expect(s.videoBitrate(size: size, duration: Time.second) == recommended * 2)
    }

    @Test("Tamanho alvo determina o bitrate")
    func targetSize() {
        var s = ExportSettings()
        s.bitrateMode = .targetSize
        s.targetMegabytes = 30
        s.audioKbps = 128
        let p = project(seconds: 60)
        // 30 MB em 60 s = 4 Mbps no total, menos 128 kbps de áudio.
        #expect(s.videoBitrate(size: s.outputSize(for: p), duration: p.duration) == 4_000_000 - 128_000)
        let estimate = Double(s.estimatedBytes(for: p))
        #expect(abs(estimate - 30_000_000) / 30_000_000 < 0.02)
    }

    @Test("Bitrate personalizado e estimativa de tamanho")
    func customBitrate() {
        var s = ExportSettings()
        s.bitrateMode = .custom
        s.customMbps = 8
        s.audioEnabled = false
        let p = project(seconds: 10)
        #expect(s.videoBitrate(size: s.outputSize(for: p), duration: p.duration) == 8_000_000)
        #expect(abs(s.estimatedBytes(for: p) - 10_100_000) < 1000)
    }

    @Test("Validação recusa combinações impossíveis")
    func validation() {
        let p = project(seconds: 2)
        var s = ExportSettings()
        #expect(s.validationError(for: p) == nil)
        s.resolution = .p4320
        #expect(s.validationError(for: p) != nil) // 8K em H.264
        s.codec = .hevc
        #expect(s.validationError(for: p) == nil)
        s.codec = .proRes422
        #expect(s.validationError(for: p) != nil) // ProRes em MP4
        s.container = .mov
        #expect(s.validationError(for: p) == nil)
        #expect(ExportSettings().validationError(for: Project()) != nil)
    }

    @Test("Durações de quadro exatas para taxas NTSC")
    func frameRates() {
        #expect(abs(FrameRate.fps29_97.value - 29.97) < 0.001)
        #expect(abs(FrameRate.fps23_976.value - 23.976) < 0.001)
        #expect(FrameRate.fps120.value == 120)
    }
}
