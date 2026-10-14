import CoreImage
import CoreMedia
import Foundation
import ImageIO

/// Tudo que o compositor precisa para desenhar um quadro.
public struct RenderPlan: @unchecked Sendable {
    public var project: Project
    public var renderSize: CGSize
    /// Segmento de vídeo → faixa da composição que entrega os quadros dele.
    public var trackIDs: [UUID: CMPersistentTrackID]
    /// Segmento de vídeo → orientação de exibição (vídeos gravados em pé).
    public var orientations: [UUID: CGImagePropertyOrientation]
    /// Material de foto → imagem já carregada (prévias que não vêm de arquivo).
    var stills: [UUID: CIImage] = [:]

    public init(project: Project, renderSize: CGSize,
                trackIDs: [UUID: CMPersistentTrackID] = [:],
                orientations: [UUID: CGImagePropertyOrientation] = [:]) {
        self.project = project
        self.renderSize = renderSize
        self.trackIDs = trackIDs
        self.orientations = orientations
    }
}

/// Plano mutável compartilhado com o compositor: mudanças só de efeitos
/// (sem alterar tempos) atualizam o preview sem remontar a composição.
public final class PlanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: RenderPlan

    public init(_ plan: RenderPlan) {
        current = plan
    }

    public var plan: RenderPlan {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func update(project: Project) {
        lock.lock()
        current.project = project
        lock.unlock()
    }
}

public final class FrameRenderer: @unchecked Sendable {
    public static let shared = FrameRenderer()

    private let photoCache = NSCache<NSString, CIImage>()

    public init() {
        photoCache.countLimit = 64
    }

    /// Desenha o quadro do instante `time`. `source` devolve o quadro
    /// decodificado de uma faixa da composição.
    public func render(plan: RenderPlan, time: Micros, source: (CMPersistentTrackID) -> CIImage?) -> CIImage {
        let canvas = CGRect(origin: .zero, size: plan.renderSize)
        let k = max(plan.renderSize.height, 1) / 1080
        let project = plan.project
        var output = background(plan: plan, time: time, canvas: canvas, k: k, source: source)

        for track in project.tracks where track.kind == .video && !track.hidden {
            let active = track.segments
                .filter { $0.targetRange.contains(time) }
                .sorted { $0.targetStart < $1.targetStart }
            if active.count >= 2, let transition = active[0].transition, active[1].targetStart < active[0].targetEnd {
                let a = layer(active[0], plan: plan, time: time, canvas: canvas, k: k, source: source) ?? CIImage.empty()
                let b = layer(active[1], plan: plan, time: time, canvas: canvas, k: k, source: source) ?? CIImage.empty()
                let start = active[1].targetStart
                let end = active[0].targetEnd
                let progress = Double(time - start) / Double(max(1, end - start))
                output = Transitions.apply(transition.kind, from: a, to: b, progress: progress, canvas: canvas, k: k)
                    .composited(over: output)
            } else {
                for seg in active {
                    if let img = layer(seg, plan: plan, time: time, canvas: canvas, k: k, source: source) {
                        output = img.composited(over: output)
                    }
                }
            }
        }

        for track in project.tracks where track.kind == .text && !track.hidden {
            for seg in track.segments where seg.targetRange.contains(time) {
                if let img = textLayer(seg, time: time, canvas: canvas) {
                    output = img.composited(over: output)
                }
            }
        }
        return output.cropped(to: canvas)
    }

    // MARK: - Camadas

    private func background(plan: RenderPlan, time: Micros, canvas: CGRect, k: CGFloat,
                            source: (CMPersistentTrackID) -> CIImage?) -> CIImage {
        let black = CIImage(color: .black).cropped(to: canvas)
        switch plan.project.canvas.background {
        case .black:
            return black
        case .color(let c):
            return CIImage(color: c.ciColor).cropped(to: canvas)
        case .blur(let amount):
            guard let main = plan.project.mainTrackIndex,
                  let seg = plan.project.tracks[main].segments.first(where: { $0.targetRange.contains(time) }),
                  let img = sourceImage(seg, plan: plan, source: source),
                  img.extent.width > 0, img.extent.height > 0
            else { return black }
            let s = max(canvas.width / img.extent.width, canvas.height / img.extent.height) * 1.1
            let filled = img.transformed(by: CGAffineTransform(translationX: -img.extent.width / 2, y: -img.extent.height / 2)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: canvas.midX, y: canvas.midY)))
            return filled.clampedToExtent()
                .applyingGaussianBlur(sigma: (8 + amount * 50) * k)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.08])
                .cropped(to: canvas)
                .composited(over: black)
        }
    }

    /// Imagem do material no instante atual, na orientação de exibição e com origem em (0, 0).
    private func sourceImage(_ seg: Segment, plan: RenderPlan, source: (CMPersistentTrackID) -> CIImage?) -> CIImage? {
        guard let m = plan.project.material(seg.materialId) else { return nil }
        var img: CIImage
        switch m.kind {
        case .video:
            guard let id = plan.trackIDs[seg.id], let frame = source(id) else { return nil }
            img = frame
            if let o = plan.orientations[seg.id], o != .up { img = img.oriented(o) }
        case .photo:
            guard let photo = plan.stills[m.id] ?? photo(m) else { return nil }
            img = photo
        case .audio:
            return nil
        }
        return img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    }

    /// Fotos são decodificadas uma vez (reduzidas a no máximo 4K) e mantidas em cache.
    private func photo(_ m: Material) -> CIImage? {
        let key = m.path as NSString
        if let cached = photoCache.object(forKey: key) { return cached }
        guard let src = CGImageSourceCreateWithURL(m.url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3840,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let img = CIImage(cgImage: cg)
        photoCache.setObject(img, forKey: key)
        return img
    }

    private func layer(_ seg: Segment, plan: RenderPlan, time: Micros, canvas: CGRect, k: CGFloat,
                       source: (CMPersistentTrackID) -> CIImage?) -> CIImage? {
        guard var img = sourceImage(seg, plan: plan, source: source),
              img.extent.width > 0, img.extent.height > 0
        else { return nil }
        let local = time - seg.targetStart
        let seconds = local.seconds

        img = ImageEffects.adjust(img, seg.adjust, k: k, time: seconds)
        if let f = seg.filter { img = ImageEffects.filter(img, f) }
        img = ImageEffects.effects(img, seg.effects, k: k, time: seconds)

        let anim = Animations.state(for: seg, local: local)
        if let shine = anim.shine {
            img = TextMotion.applyShine(img, in: img.extent, position: shine.position, strength: shine.strength)
        }
        let geo = ImageEffects.geometry(seg.effects, time: seconds)
        let w = img.extent.width
        let h = img.extent.height
        let fit = min(canvas.width / w, canvas.height / h)
        let scale = fit * seg.transform.scale * anim.scale * geo.scale
        let cx = canvas.midX + (seg.transform.x + anim.dx + geo.dx) * canvas.width / 2
        let cy = canvas.midY + (seg.transform.y + anim.dy + geo.dy) * canvas.height / 2
        let radians = -(seg.transform.rotation + anim.rotation) * .pi / 180

        let t = CGAffineTransform(translationX: -w / 2, y: -h / 2)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: cx, y: cy))
        img = finish(img.transformed(by: t, highQualityDownsample: true), anim: anim, canvas: canvas)
        if anim.glow > 0 { img = TextMotion.applyGlow(img, amount: anim.glow, sigma: 0.012 * canvas.height) }
        return withAlpha(img, seg.opacity * anim.alpha)
    }

    /// Desfoque da animação "foco", já no espaço do canvas.
    private func finish(_ img: CIImage, anim: AnimationState, canvas: CGRect) -> CIImage {
        let sigma = anim.blur * canvas.height
        return sigma > 0.3 ? img.applyingGaussianBlur(sigma: sigma) : img
    }

    private func textLayer(_ seg: Segment, time: Micros, canvas: CGRect) -> CIImage? {
        guard let content = seg.text else { return nil }
        let anim = Animations.state(for: seg, local: time - seg.targetStart)
        let img: CIImage
        let w: CGFloat
        let h: CGFloat
        if Animations.usesUnits(seg) {
            // Por unidade no clipe inteiro; a caixa nominal é a da imagem estática.
            let granularity = Animations.granularity(for: seg, state: anim)
            guard let r = TextMotion.image(content, canvas: canvas.size, state: anim, granularity: granularity) else { return nil }
            (img, w, h) = (r.image, r.size.width, r.size.height)
        } else {
            guard let still = TextRenderer.shared.image(for: content, canvas: canvas.size, reveal: anim.reveal) else { return nil }
            (img, w, h) = (still, still.extent.width, still.extent.height)
        }
        let style = content.style
        let scale = style.scale * anim.scale
        let cx = canvas.midX + (style.x + anim.dx) * canvas.width / 2
        let cy = canvas.midY + (style.y + anim.dy) * canvas.height / 2
        let radians = -(style.rotation + anim.rotation) * .pi / 180
        let t = CGAffineTransform(translationX: -w / 2, y: -h / 2)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: cx, y: cy))
        let placed = finish(img.transformed(by: t, highQualityDownsample: true), anim: anim, canvas: canvas)
        return withAlpha(placed, seg.opacity * anim.alpha)
    }

    private func withAlpha(_ img: CIImage, _ alpha: Double) -> CIImage {
        guard alpha < 0.999 else { return img }
        return img.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, alpha)),
        ])
    }
}
