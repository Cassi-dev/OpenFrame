import AVFoundation
import CoreImage
import Foundation
import VideoToolbox

// Gera vídeos HEVC 10 bits em BT.2100 (HLG e PQ), como os do iPhone, com faixas
// de cinza e de cor, e mede como o macOS os mostra em SDR (AVAssetImageGenerator
// → sRGB 8 bits, o "sistema" do ColorTests.swift). Grava os vídeos e as medidas
// em qt/tests/fixtures (hdr-hlg.mov, hdr-pq.mov, hdr.json); a versão Qt compara
// a própria conversão com esses números. Uso: qt/tests/tools/gerar-hdr.sh

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let side = 32, height = 64

/// Valores do sinal (já codificados na curva HDR) de cada faixa.
let grays: [Int] = stride(from: 0, through: 240, by: 16).map { $0 } + [255]
let colors: [[Int]] = [
    [200, 60, 40], [40, 120, 200], [60, 200, 80], [230, 200, 60], [180, 140, 120],
    [255, 0, 0], [0, 255, 0], [0, 0, 255], [128, 64, 192], [255, 255, 128],
]
let patches: [[Int]] = grays.map { [$0, $0, $0] } + colors

func makeVideo(_ url: URL, transfer: String, cvTransfer: CFString) async throws {
    try? FileManager.default.removeItem(at: url)
    let width = side * patches.count
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
        ],
        AVVideoCompressionPropertiesKey: [
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoAverageBitRateKey: 4_000_000,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)

    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
    let buffer = pb!
    CVBufferSetAttachments(buffer, [
        kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_2020,
        kCVImageBufferTransferFunctionKey as String: cvTransfer,
        kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_2020,
    ] as CFDictionary, .shouldPropagate)
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            let c = patches[x / side]
            let p = base + y * stride + x * 4
            (p[0], p[1], p[2], p[3]) = (UInt8(c[2]), UInt8(c[1]), UInt8(c[0]), 255)
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
}

/// Cor mostrada (sRGB 0...255) no centro de cada faixa, como o Bitmap dos testes Swift.
func measure(_ url: URL) async throws -> (colors: [[Int]], space: String) {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let cg = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
    let w = cg.width, h = cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    CIContext().render(CIImage(cgImage: cg), toBitmap: &bytes, rowBytes: w * 4,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    let colors = patches.indices.map { i -> [Int] in
        let px = min(w - 1, Int((Double(i) + 0.5) / Double(patches.count) * Double(w)))
        let j = (h / 2 * w + px) * 4
        return [Int(bytes[j]), Int(bytes[j + 1]), Int(bytes[j + 2])]
    }
    return (colors, (cg.colorSpace?.name as String?) ?? "?")
}

var result: [String: Any] = ["patches": patches, "patchWidth": side]
for (name, transfer, cvTransfer) in [
    ("hlg", AVVideoTransferFunction_ITU_R_2100_HLG, kCVImageBufferTransferFunction_ITU_R_2100_HLG),
    ("pq", AVVideoTransferFunction_SMPTE_ST_2084_PQ, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ),
] {
    let url = output.appendingPathComponent("hdr-\(name).mov")
    try await makeVideo(url, transfer: transfer, cvTransfer: cvTransfer)
    let (colors, space) = try await measure(url)
    result[name] = ["file": url.lastPathComponent, "displayed": colors, "imageColorSpace": space]
    print(name, space, colors)
}
let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("hdr.json"))
