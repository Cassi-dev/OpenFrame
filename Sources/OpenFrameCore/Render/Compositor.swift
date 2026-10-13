import AVFoundation
import CoreImage

/// Instrução única que cobre a timeline inteira e carrega o plano de render.
public final class OpenFrameInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    public let box: PlanBox

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], box: PlanBox) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.box = box
    }
}

/// Compositor customizado: o AVFoundation decodifica os vídeos e entrega os
/// quadros; nós desenhamos tudo (efeitos, transições, texto) com Core Image.
/// É usado tanto no preview (AVPlayer) quanto na exportação (AVAssetReader).
public final class OpenFrameCompositor: NSObject, AVVideoCompositing {
    private static let pixelAttributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]

    private let queue = DispatchQueue(label: "openframe.compositor", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false, .name: "OpenFrame"])
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
    private let lock = NSLock()
    private var generation = 0

    public var sourcePixelBufferAttributes: [String: any Sendable]? { Self.pixelAttributes }
    public var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.pixelAttributes }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let requestGeneration = currentGeneration()
        queue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                if requestGeneration != self.currentGeneration() {
                    request.finishCancelledRequest()
                    return
                }
                self.render(request)
            }
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func render(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? OpenFrameInstruction,
              let buffer = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "OpenFrame", code: -1,
                                         userInfo: [NSLocalizedDescriptionKey: "Instrução de composição inválida"]))
            return
        }
        let plan = instruction.box.plan
        var image = FrameRenderer.shared.render(plan: plan, time: request.compositionTime.micros) { trackID in
            request.sourceFrame(byTrackID: trackID).map { CIImage(cvPixelBuffer: $0) }
        }
        let size = request.renderContext.size
        if size != plan.renderSize, plan.renderSize.width > 0, plan.renderSize.height > 0 {
            image = image.transformed(by: CGAffineTransform(scaleX: size.width / plan.renderSize.width,
                                                            y: size.height / plan.renderSize.height))
        }
        context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: buffer)
    }
}
