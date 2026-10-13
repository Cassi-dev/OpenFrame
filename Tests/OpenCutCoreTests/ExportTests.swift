import AVFoundation
import CoreImage
import Testing
@testable import OpenCutCore

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func add(_ v: Double) {
        lock.lock()
        values.append(v)
        lock.unlock()
    }

    var all: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Suite("Exportação", .serialized)
struct ExportTests {
    /// Projeto com dois vídeos (um acelerado), uma foto, transição, filtro,
    /// efeito e texto.
    func richProject() async throws -> Project {
        let videoURL = try await TestMedia.makeVideo(seconds: 2)
        let video = try await MediaProbe.probe(videoURL)
        let photoURL = try TestMedia.makePNG(color: CIColor(red: 0.2, green: 0.8, blue: 0.3))
        let photo = try await MediaProbe.probe(photoURL)

        var p = Project()
        let a = TimelineEditor.addMedia(video, to: &p)
        let b = TimelineEditor.addMedia(video, to: &p)
        TimelineEditor.addMedia(photo, to: &p)
        TimelineEditor.update(&p, segment: a) {
            $0.transition = Transition(kind: .slideLeft, duration: 400_000)
            $0.filter = FilterSetting(preset: .cinematic)
            $0.fadeIn = 300_000
        }
        TimelineEditor.setSpeed(&p, segment: b, speed: 2)
        TimelineEditor.update(&p, segment: b) { $0.effects = [VideoEffect(kind: .rgbSplit)] }
        TimelineEditor.addText(TextContent(text: "OpenCut"), to: &p, at: 500_000, duration: 2_000_000)
        return p
    }

    func videoTrack(_ url: URL) async throws -> AVAssetTrack {
        try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
    }

    @Test("Exporta com resolução, fps, codec e bitrate escolhidos")
    func fullExport() async throws {
        let p = try await richProject()
        var s = ExportSettings()
        s.resolution = .p720
        s.frameRate = .fps60
        s.codec = .hevc
        s.bitrateMode = .custom
        s.customMbps = 3
        s.audioKbps = 128
        let url = TestMedia.tempURL("mp4")
        let log = ProgressLog()

        try await Exporter().export(project: p, settings: s, to: url) { log.add($0) }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - p.duration.seconds) < 0.1)

        let video = try await videoTrack(url)
        let (size, fps, formats) = try await video.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
        #expect(size == CGSize(width: 1280, height: 720))
        #expect(abs(fps - 60) < 0.5)
        #expect(formats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kCMVideoCodecType_HEVC)
        let dataRate = try await video.load(.estimatedDataRate)
        #expect(dataRate > 0 && dataRate < 3_000_000 * 1.5)

        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let audioFormats = try await audio.load(.formatDescriptions)
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormats[0])!.pointee
        #expect(asbd.mSampleRate == 48000)
        #expect(asbd.mChannelsPerFrame == 2)

        let progress = log.all
        #expect(progress.last == 1)
        #expect(progress == progress.sorted())
    }

    @Test("Canvas 9:16 em 720p a 24 fps com H.264")
    func verticalExport() async throws {
        var p = try await richProject()
        p.canvas.aspect = .r9x16
        p.canvas.background = .blur(0.5)
        var s = ExportSettings()
        s.resolution = .p720
        s.frameRate = .fps24
        s.bitrateMode = .lower
        let url = TestMedia.tempURL("mp4")
        try await Exporter().export(project: p, settings: s, to: url) { _ in }

        let (size, fps, formats) = try await videoTrack(url).load(.naturalSize, .nominalFrameRate, .formatDescriptions)
        #expect(size == CGSize(width: 720, height: 1280))
        #expect(abs(fps - 24) < 0.5)
        #expect(formats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kCMVideoCodecType_H264)
    }

    @Test("29,97 fps em MOV com ProRes e sem áudio")
    func proResExport() async throws {
        let p = try await richProject()
        var s = ExportSettings()
        s.resolution = .p480
        s.frameRate = .fps29_97
        s.codec = .proRes422
        s.container = .mov
        s.audioEnabled = false
        let url = TestMedia.tempURL("mov")
        try await Exporter().export(project: p, settings: s, to: url) { _ in }

        let (fps, formats) = try await videoTrack(url).load(.nominalFrameRate, .formatDescriptions)
        #expect(abs(fps - 29.97) < 0.05)
        #expect(formats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kCMVideoCodecType_AppleProRes422)
        #expect(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test("Exportar só o áudio em M4A")
    func audioOnly() async throws {
        let p = try await richProject()
        var s = ExportSettings()
        s.container = .m4a
        let url = TestMedia.tempURL("m4a")
        try await Exporter().export(project: p, settings: s, to: url) { _ in }

        let asset = AVURLAsset(url: url)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    @Test("O arquivo exportado mostra o conteúdo renderizado")
    func renderedContent() async throws {
        let photoURL = try TestMedia.makePNG(width: 320, height: 180, color: CIColor(red: 1, green: 0, blue: 0))
        var p = Project()
        TimelineEditor.addMedia(try await MediaProbe.probe(photoURL), to: &p)
        var style = TextStyle()
        style.y = 0.6
        style.backgroundEnabled = true
        style.backgroundColor = RGBA(0, 0, 1)
        TimelineEditor.addText(TextContent(text: "TESTE", style: style), to: &p, at: 0)
        var s = ExportSettings()
        s.resolution = .p480
        s.audioEnabled = false
        let url = TestMedia.tempURL("mp4")
        try await Exporter().export(project: p, settings: s, to: url) { _ in }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        let (cg, _) = try await generator.image(at: CMTime(value: 1, timescale: 1))
        let size = CGSize(width: cg.width, height: cg.height)
        #expect(size == CGSize(width: 854, height: 480))
        let bmp = Bitmap(CIImage(cgImage: cg), size: size)
        let center = bmp.color(0.5, 0.3)
        #expect(center.r > 200 && center.g < 50 && center.b < 50)
        // A caixa azul do texto (entre as letras brancas) aparece na faixa superior.
        let hasLabelBox = (0..<20).contains { i in
            let c = bmp.color(0.3 + Double(i) * 0.02, 0.8)
            return c.b > 150 && c.r < 100
        }
        #expect(hasLabelBox)
    }

    @Test("Cancelar interrompe e apaga o arquivo parcial")
    func cancel() async throws {
        let videoURL = try await TestMedia.makeVideo(seconds: 2)
        let video = try await MediaProbe.probe(videoURL)
        var p = Project()
        for _ in 0..<10 { TimelineEditor.addMedia(video, to: &p) }
        var s = ExportSettings()
        s.resolution = .p1080
        let url = TestMedia.tempURL("mp4")
        let exporter = Exporter()
        let task = Task { try await exporter.export(project: p, settings: s, to: url) { _ in } }
        try await Task.sleep(nanoseconds: 300_000_000)
        exporter.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Configuração inválida é recusada antes de começar")
    func rejectsInvalid() async throws {
        let p = try await richProject()
        var s = ExportSettings()
        s.resolution = .p4320
        await #expect(throws: ExportError.self) {
            try await Exporter().export(project: p, settings: s, to: TestMedia.tempURL("mp4")) { _ in }
        }
    }
}
