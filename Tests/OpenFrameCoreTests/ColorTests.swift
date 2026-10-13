import AVFoundation
import CoreImage
import Testing
import VideoToolbox
@testable import OpenFrameCore

/// Cor exibida (em sRGB, 0...255) de um quadro, como o macOS a mostra com gerência de cor.
private func displayed(_ cg: CGImage, at points: [(Double, Double)]) -> [(r: Int, g: Int, b: Int)] {
    let bmp = Bitmap(CIImage(cgImage: cg), size: CGSize(width: cg.width, height: cg.height))
    return points.map { bmp.color($0.0, $0.1) }
}

private func frame(_ asset: AVAsset, at seconds: Double, videoComposition: AVVideoComposition? = nil) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.videoComposition = videoComposition
    return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
}

private func close(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), tolerance: Int) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
}

/// Cinzas escuros, médios e claros e duas cores, em faixas verticais.
private let patches: [(UInt8, UInt8, UInt8)] = [
    (16, 16, 16), (48, 48, 48), (128, 128, 128), (208, 208, 208), (200, 60, 40), (40, 120, 200),
]
private let patchCenters = patches.indices.map { ((Double($0) + 0.5) / Double(patches.count), 0.5) }

/// Vídeo H.264 marcado como BT.709 com as faixas de `patches`.
private func makePatchVideo() async throws -> URL {
    try await makeVideo(patches, settings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
    ])
}

/// Níveis de cinza do sinal HLG (0...255), do escuro ao pico.
private let hlgLevels: [UInt8] = [26, 64, 128, 191, 230, 255]

/// Vídeo HEVC 10 bits em BT.2100 HLG (como os do iPhone) com faixas de cinza.
private func makeHLGVideo() async throws -> URL {
    try await makeVideo(hlgLevels.map { ($0, $0, $0) }, settings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
        ],
        AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String],
    ], attachments: [
        kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_2020,
        kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_ITU_R_2100_HLG,
        kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_2020,
    ])
}

/// Vídeo de 1 s com uma faixa vertical (64 px) por cor.
private func makeVideo(_ colors: [(UInt8, UInt8, UInt8)], settings: [String: Any],
                       attachments: [String: Any]? = nil) async throws -> URL {
    let url = TestMedia.tempURL("mov")
    let width = 64 * colors.count, height = 96
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    var outputSettings = settings
    outputSettings[AVVideoWidthKey] = width
    outputSettings[AVVideoHeightKey] = height
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)

    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
    let buffer = try #require(pb)
    if let attachments { CVBufferSetAttachments(buffer, attachments as CFDictionary, .shouldPropagate) }
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = colors[x / 64]
            let p = base + y * stride + x * 4
            (p[0], p[1], p[2], p[3]) = (b, g, r, 255)
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    for frame in 0..<30 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error! }
    return url
}

/// PNG de uma cor sólida no espaço de cor dado.
private func makePNG(_ components: [CGFloat], space: CFString) throws -> URL {
    let url = TestMedia.tempURL("png")
    let cs = CGColorSpace(name: space)!
    let color = CIColor(red: components[0], green: components[1], blue: components[2], alpha: 1, colorSpace: cs)!
    let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
    try CIContext().writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: cs)
    return url
}

/// A mesma cor convertida para sRGB 0...255 pelo ColorSync.
private func srgb(_ components: [CGFloat], from space: CFString) -> (r: Int, g: Int, b: Int) {
    let c = CGColor(colorSpace: CGColorSpace(name: space)!, components: components + [1])!
        .converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)!
        .components!
    func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return (byte(c[0]), byte(c[1]), byte(c[2]))
}

private func export(_ p: Project, codec: VideoCodec = .h264, container: ContainerFormat = .mp4) async throws -> URL {
    var s = ExportSettings()
    s.resolution = .p480
    s.codec = codec
    s.container = container
    s.audioEnabled = false
    s.bitrateMode = .custom
    s.customMbps = 20
    let url = TestMedia.tempURL(container == .mov ? "mov" : "mp4")
    try await Exporter().export(project: p, settings: s, to: url) { _ in }
    return url
}

@Suite("Cores", .serialized)
struct ColorTests {
    @Test("Vídeo BT.709 sai com as mesmas cores no arquivo exportado",
          arguments: [(VideoCodec.h264, ContainerFormat.mp4), (.hevc, .mp4), (.proRes422, .mov)])
    func videoRoundTrip(codec: VideoCodec, container: ContainerFormat) async throws {
        let source = try await makePatchVideo()
        var p = Project()
        TimelineEditor.addMedia(try await MediaProbe.probe(source), to: &p)
        let exported = try await export(p, codec: codec, container: container)

        let original = displayed(try await frame(AVURLAsset(url: source), at: 0.5), at: patchCenters)
        let result = displayed(try await frame(AVURLAsset(url: exported), at: 0.5), at: patchCenters)
        for (i, (a, b)) in zip(original, result).enumerated() {
            #expect(close(a, b, tolerance: 4), "faixa \(i) (\(codec)): original \(a), exportado \(b)")
        }
    }

    @Test("Preview mostra o vídeo com as cores do original")
    func previewMatchesSource() async throws {
        let source = try await makePatchVideo()
        var p = Project()
        TimelineEditor.addMedia(try await MediaProbe.probe(source), to: &p)
        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 384, height: 96),
                                                       frameDuration: CMTime(value: 1, timescale: 30))
        let original = displayed(try await frame(AVURLAsset(url: source), at: 0.5), at: patchCenters)
        let preview = displayed(try await frame(built.composition, at: 0.5, videoComposition: built.videoComposition),
                                at: patchCenters)
        for (i, (a, b)) in zip(original, preview).enumerated() {
            #expect(close(a, b, tolerance: 3), "faixa \(i): original \(a), preview \(b)")
        }
    }

    @Test("Fotos sRGB e Display P3 mantêm a cor", arguments: [
        ([0.06, 0.06, 0.06], CGColorSpace.sRGB),
        ([0.5, 0.5, 0.5], CGColorSpace.sRGB),
        ([0.85, 0.3, 0.2], CGColorSpace.sRGB),
        ([0.55, 0.38, 0.28], CGColorSpace.displayP3),
        ([0.3, 0.55, 0.7], CGColorSpace.displayP3),
    ] as [([CGFloat], CFString)])
    func photoColor(components: [CGFloat], space: CFString) async throws {
        var p = Project()
        TimelineEditor.addMedia(try await MediaProbe.probe(try makePNG(components, space: space)), to: &p)
        let expected = srgb(components, from: space)
        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 320, height: 180),
                                                       frameDuration: CMTime(value: 1, timescale: 30))
        let preview = displayed(try await frame(built.composition, at: 0.5, videoComposition: built.videoComposition),
                                at: [(0.5, 0.5)])[0]
        #expect(close(preview, expected, tolerance: 3), "\(space) \(components): esperado \(expected), preview \(preview)")
        let exported = displayed(try await frame(AVURLAsset(url: try await export(p)), at: 0.5), at: [(0.5, 0.5)])[0]
        #expect(close(exported, expected, tolerance: 4), "\(space) \(components): esperado \(expected), exportado \(exported)")
    }

    @Test("Vídeo HDR HLG vira SDR sem estourar os claros")
    func hlgToSDR() async throws {
        let source = try await makeHLGVideo()
        var p = Project()
        TimelineEditor.addMedia(try await MediaProbe.probe(source), to: &p)
        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 64 * hlgLevels.count, height: 96),
                                                       frameDuration: CMTime(value: 1, timescale: 30))
        let points = hlgLevels.indices.map { ((Double($0) + 0.5) / Double(hlgLevels.count), 0.5) }
        let system = displayed(try await frame(AVURLAsset(url: source), at: 0.5), at: points)
        let preview = displayed(try await frame(built.composition, at: 0.5, videoComposition: built.videoComposition),
                                at: points)
        // A ordem dos tons se mantém e os dois níveis mais altos continuam distintos.
        #expect(zip(preview, preview.dropFirst()).allSatisfy { $0.r < $1.r }, "\(preview)")
        // Perto da conversão HDR → SDR do próprio sistema (AVAssetImageGenerator).
        for (i, (a, b)) in zip(system, preview).enumerated() {
            #expect(close(a, b, tolerance: 12), "nível \(hlgLevels[i]): sistema \(a), preview \(b)")
        }
    }

    @Test("Arquivos exportados levam as marcas de cor BT.709",
          arguments: [(VideoCodec.h264, ContainerFormat.mp4), (.hevc, .mp4), (.proRes422, .mov)])
    func exportTags(codec: VideoCodec, container: ContainerFormat) async throws {
        var p = Project()
        TimelineEditor.addMedia(try await MediaProbe.probe(try makePNG([0.5, 0.5, 0.5], space: CGColorSpace.sRGB)), to: &p)
        let url = try await export(p, codec: codec, container: container)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let desc = try #require(try await track.load(.formatDescriptions).first)
        func ext(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(desc, extensionKey: key) as? String }
        #expect(ext(kCMFormatDescriptionExtension_ColorPrimaries) == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(ext(kCMFormatDescriptionExtension_TransferFunction) == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(ext(kCMFormatDescriptionExtension_YCbCrMatrix) == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
    }
}
