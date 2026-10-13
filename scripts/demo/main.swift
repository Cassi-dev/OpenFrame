// Gera mídia sintética e um projeto de demonstração.
// Uso: scripts/make-demo.sh [pasta-de-saída]
import AVFoundation
import CoreGraphics
import CoreText
import Foundation

let positional = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let outputDir = URL(fileURLWithPath: positional.first ?? NSHomeDirectory() + "/Desktop/OpenFrame Demo", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// Desenha um quadro: gradiente que muda de cor, círculo em movimento e um rótulo.
func drawFrame(_ ctx: CGContext, width: Int, height: Int, t: Double, hueBase: Double, label: String) {
    let w = CGFloat(width), h = CGFloat(height)
    let hue1 = (hueBase + t * 0.05).truncatingRemainder(dividingBy: 1)
    let hue2 = (hue1 + 0.25).truncatingRemainder(dividingBy: 1)
    func rgb(_ hue: Double, _ s: Double, _ v: Double) -> CGColor {
        let i = Int(hue * 6), f = hue * 6 - Double(i)
        let p = v * (1 - s), q = v * (1 - f * s), u = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double) = [(v, u, p), (q, v, p), (p, v, u), (p, q, v), (u, p, v), (v, p, q)][i % 6]
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(hue1, 0.7, 0.9), rgb(hue2, 0.8, 0.5)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
    let r = h * 0.18
    let cx = w / 2 + cos(t * 1.7) * w * 0.3
    let cy = h / 2 + sin(t * 2.3) * h * 0.25
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    let font = CTFontCreateWithName("Helvetica Neue" as CFString, h * 0.09, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.9),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(format: "%@  %.1fs", label, t), attributes: attrs))
    ctx.textPosition = CGPoint(x: w * 0.05, y: h * 0.08)
    CTLineDraw(line, ctx)
}

func writeVideo(_ url: URL, width: Int, height: Int, seconds: Double, hue: Double, label: String, tone: Double?) async throws {
    try? FileManager.default.removeItem(at: url)
    let fps = 30
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(video)
    let sampleRate = 48000.0
    var audio: AVAssetWriterInput?
    if tone != nil {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000,
        ])
        writer.add(input)
        audio = input
    }
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let frames = Int(seconds * Double(fps))
    let group = DispatchGroup()

    group.enter()
    var frame = 0
    video.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
        while video.isReadyForMoreMediaData {
            guard frame < frames, let pool = adaptor.pixelBufferPool else {
                video.markAsFinished(); group.leave(); return
            }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            CVPixelBufferLockBaseAddress(pb!, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            drawFrame(ctx, width: width, height: height, t: Double(frame) / Double(fps), hueBase: hue, label: label)
            CVPixelBufferUnlockBaseAddress(pb!, [])
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            frame += 1
        }
    }

    if let audio, let tone {
        group.enter()
        var offset = 0
        let total = Int(seconds * sampleRate)
        audio.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
            while audio.isReadyForMoreMediaData {
                let count = min(1024, total - offset)
                guard count > 0 else { audio.markAsFinished(); group.leave(); return }
                audio.append(toneBuffer(start: offset, count: count, rate: sampleRate, frequency: tone))
                offset += count
            }
        }
    }
    await withCheckedContinuation { c in group.notify(queue: .global()) { c.resume() } }
    await writer.finishWriting()
    if writer.status != .completed { throw writer.error ?? NSError(domain: "demo", code: 1) }
}

/// Tom com notas que mudam a cada meio segundo (arpejo).
func toneBuffer(start: Int, count: Int, rate: Double, frequency: Double) -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                           mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                           mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                           mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                   magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let ratios = [1.0, 1.25, 1.5, 2.0]
    var samples = [Int16](repeating: 0, count: count)
    for i in 0..<count {
        let n = start + i
        let t = Double(n) / rate
        let f = frequency * ratios[Int(t * 2) % ratios.count]
        let envelope = 1 - (t * 2).truncatingRemainder(dividingBy: 1) * 0.7
        samples[i] = Int16(sin(2 * .pi * f * t) * 9000 * envelope)
    }
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
                                       customBlockSource: nil, offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block)
    samples.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 2) }
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!,
                                                         sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
                                                         packetDescriptions: nil, sampleBufferOut: &sample)
    return sample!
}

func writePhoto(_ url: URL) throws {
    let w = 1600, h = 1200
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawFrame(ctx, width: w, height: h, t: 3, hueBase: 0.75, label: "Foto")
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let clipA = outputDir.appendingPathComponent("clipe-a.mov")
let clipB = outputDir.appendingPathComponent("clipe-b.mov")
let music = outputDir.appendingPathComponent("musica.m4a")
let photo = outputDir.appendingPathComponent("foto.png")
try await writeVideo(clipA, width: 1280, height: 720, seconds: 6, hue: 0.55, label: "Clipe A", tone: 330)
try await writeVideo(clipB, width: 1280, height: 720, seconds: 5, hue: 0.05, label: "Clipe B", tone: 262)
try await writeVideo(music, width: 64, height: 64, seconds: 14, hue: 0, label: "", tone: 196) // só o áudio é usado
try writePhoto(photo)

// Monta o projeto com as mesmas APIs que o app usa.
var project = Project()
project.name = "Demo"
let a = try await MediaProbe.probe(clipA)
let b = try await MediaProbe.probe(clipB)
let p = try await MediaProbe.probe(photo)
var m = try await MediaProbe.probe(music)
m.kind = .audio
m.hasAudio = true

let segA = TimelineEditor.addMedia(a, to: &project)
let segB = TimelineEditor.addMedia(b, to: &project)
let segP = TimelineEditor.addMedia(p, to: &project)
TimelineEditor.update(&project, segment: segA) {
    $0.transition = Transition(kind: .slideLeft, duration: 600_000)
    $0.animationIn = SegmentAnimation(kind: .fade, duration: 700_000)
    $0.filter = FilterSetting(preset: .cinematic, intensity: 0.8)
}
TimelineEditor.update(&project, segment: segB) {
    $0.transition = Transition(kind: .dissolve, duration: 800_000)
    $0.effects = [VideoEffect(kind: .rgbSplit, intensity: 0.4)]
    $0.adjust.saturation = 0.3
}
TimelineEditor.setSpeed(&project, segment: segB, speed: 1.5)
TimelineEditor.update(&project, segment: segP) {
    $0.animationIn = SegmentAnimation(kind: .zoomIn, duration: 600_000)
    $0.animationOut = SegmentAnimation(kind: .fade, duration: 800_000)
    $0.adjust.vignette = 0.6
}
let visualEnd = project.duration
let musicSeg = TimelineEditor.addMedia(m, to: &project, at: 0)
TimelineEditor.update(&project, segment: musicSeg) {
    $0.volume = 0.5
    $0.fadeIn = 1_000_000
    $0.fadeOut = 2_000_000
}
TimelineEditor.trimEnd(&project, segment: musicSeg, to: visualEnd)

var title = TextStyle()
title.fontSize = 0.11
title.y = 0.55
title.strokeWidth = 3
let titleSeg = TimelineEditor.addText(TextContent(text: "OpenFrame", style: title), to: &project, at: 300_000, duration: 3_000_000)
TimelineEditor.update(&project, segment: titleSeg) {
    $0.animationIn = SegmentAnimation(kind: .typewriter, duration: 1_000_000)
    $0.animationOut = SegmentAnimation(kind: .fade)
}
var caption = TextStyle()
caption.backgroundEnabled = true
caption.color = .black
caption.backgroundColor = .yellow
caption.shadow = false
caption.fontSize = 0.06
TimelineEditor.addText(TextContent(text: "Editor de vídeo feito em Swift", style: caption), to: &project, at: 6_000_000, duration: 3_000_000)

// Sobreposição picture-in-picture
let overlay = TimelineEditor.addOverlay(a, to: &project, at: 7_500_000)
TimelineEditor.update(&project, segment: overlay) {
    $0.transform.scale = 0.32
    $0.transform.x = 0.6
    $0.transform.y = 0.55
    $0.source.duration = 3_000_000
    $0.animationIn = SegmentAnimation(kind: .slideLeft)
}

let projectURL = outputDir.appendingPathComponent("Demo.openframe")
try ProjectStore.save(project, to: projectURL)
print(projectURL.path)

// Com --export, também renderiza o projeto em Demo.mp4 (1080p, 30 fps).
if CommandLine.arguments.contains("--export") {
    let videoURL = outputDir.appendingPathComponent("Demo.mp4")
    let start = Date()
    try await Exporter().export(project: project, settings: ExportSettings(), to: videoURL) { _ in }
    print(videoURL.path, String(format: "(%.1fs)", Date().timeIntervalSince(start)))
}
