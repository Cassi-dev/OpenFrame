import AVFoundation
import CoreImage
import Foundation
@testable import OpenFrameCore

/// Gera arquivos de mídia sintéticos para os testes.
enum TestMedia {
    static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenFrameTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func tempURL(_ ext: String) -> URL {
        directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    /// Vídeo cuja metade de cima (no quadro original) é vermelha e a de baixo
    /// azul, com uma faixa branca que anda a cada quadro. Opcionalmente com
    /// áudio senoidal e transformação de exibição (rotação).
    static func makeVideo(width: Int = 320, height: Int = 180, seconds: Double = 2, fps: Int = 30,
                          audio: Bool = true, transform: CGAffineTransform = .identity) async throws -> URL {
        let url = tempURL("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        writer.add(videoInput)

        let sampleRate = 48000.0
        var audioInput: AVAssetWriterInput?
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)

        // Cada trilha puxa amostras na própria fila: o AVAssetWriter intercala
        // áudio e vídeo e travaria se uma fosse alimentada só depois da outra.
        let frames = Int(seconds * Double(fps))
        let totalSamples = Int(seconds * sampleRate)
        let group = DispatchGroup()

        group.enter()
        var frame = 0
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "test.video")) {
            while videoInput.isReadyForMoreMediaData {
                guard frame < frames,
                      let buffer = try? pixelBuffer(width: width, height: height, frame: frame, frames: frames)
                else {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
                frame += 1
            }
        }

        if let audioInput {
            group.enter()
            var offset = 0
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "test.audio")) {
                while audioInput.isReadyForMoreMediaData {
                    let count = min(1024, totalSamples - offset)
                    guard count > 0, let sample = try? sineBuffer(start: offset, count: count, sampleRate: sampleRate) else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    audioInput.append(sample)
                    offset += count
                }
            }
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { c.resume() }
        }

        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        return url
    }

    private static func pixelBuffer(width: Int, height: Int, frame: Int, frames: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { throw NSError(domain: "TestMedia", code: 1) }
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let barX = width * frame / max(frames, 1)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * stride + x * 4
                let top = y < height / 2 // linha 0 = topo do quadro
                var (r, g, b): (UInt8, UInt8, UInt8) = top ? (220, 30, 30) : (30, 30, 220)
                if abs(x - barX) < 3 { (r, g, b) = (255, 255, 255) }
                p[0] = b
                p[1] = g
                p[2] = r
                p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    private static func sineBuffer(start: Int, count: Int, sampleRate: Double) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                               mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = Int16(sin(2 * .pi * 440 * Double(start + i) / sampleRate) * 12000)
        }
        let byteCount = count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
                                           flags: 0, blockBufferOut: &block)
        samples.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: byteCount)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw NSError(domain: "TestMedia", code: 2) }
        return sample
    }

    /// PNG de cor sólida.
    static func makePNG(width: Int = 400, height: Int = 300, color: CIColor) throws -> URL {
        let url = tempURL("png")
        let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        try CIContext().writePNGRepresentation(of: image, to: url, format: .RGBA8,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return url
    }
}

/// Lê pixels de uma CIImage renderizada (origem no canto inferior esquerdo).
struct Bitmap {
    let width: Int
    let height: Int
    let data: [UInt8]

    init(_ image: CIImage, size: CGSize) {
        width = Int(size.width)
        height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(image, toBitmap: &bytes, rowBytes: width * 4,
                           bounds: CGRect(origin: .zero, size: size), format: .RGBA8,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        data = bytes
    }

    /// Cor no ponto (x, y) em coordenadas normalizadas 0...1 (y para cima).
    func color(_ x: Double, _ y: Double) -> (r: Int, g: Int, b: Int) {
        let px = min(width - 1, Int(x * Double(width)))
        // Linha 0 do bitmap é o topo da imagem.
        let py = min(height - 1, Int((1 - y) * Double(height)))
        let i = (py * width + px) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}
