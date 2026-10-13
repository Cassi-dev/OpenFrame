import CoreImage
import Foundation

/// Estado de uma animação de entrada/saída num instante.
struct AnimationState {
    var scale = 1.0
    var dx = 0.0
    var dy = 0.0
    var rotation = 0.0
    var alpha = 1.0
    /// Fração do texto visível (animação "máquina de escrever").
    var reveal = 1.0
}

enum Animations {
    static func state(for seg: Segment, local: Micros) -> AnimationState {
        var st = AnimationState()
        let duration = seg.targetDuration
        if let a = seg.animationIn, a.duration > 0, local < a.duration {
            apply(a.kind, progress: ease(Double(local) / Double(a.duration)), exiting: false, to: &st)
        }
        if let a = seg.animationOut, a.duration > 0, local > duration - a.duration {
            apply(a.kind, progress: ease(Double(duration - local) / Double(a.duration)), exiting: true, to: &st)
        }
        return st
    }

    static func ease(_ p: Double) -> Double {
        let x = min(max(p, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    /// `progress` vai de 0 (invisível) a 1 (posição final).
    private static func apply(_ kind: AnimationKind, progress p: Double, exiting: Bool, to st: inout AnimationState) {
        let hidden = 1 - p
        // Na saída, "deslizar ←" continua indo para a esquerda.
        let direction: Double = exiting ? -1 : 1
        switch kind {
        case .fade:
            st.alpha *= p
        case .zoomIn:
            st.scale *= 0.5 + 0.5 * p
            st.alpha *= p
        case .zoomOut:
            st.scale *= 1.5 - 0.5 * p
            st.alpha *= p
        case .slideLeft:
            st.dx += hidden * 1.2 * direction
        case .slideRight:
            st.dx -= hidden * 1.2 * direction
        case .slideUp:
            st.dy -= hidden * 1.2 * direction
        case .slideDown:
            st.dy += hidden * 1.2 * direction
        case .spin:
            st.rotation += hidden * 360
            st.scale *= max(p, 0.001)
        case .typewriter:
            st.reveal = min(st.reveal, p)
        }
    }
}

enum Transitions {
    /// Mistura duas camadas já posicionadas no canvas.
    static func apply(_ kind: TransitionKind, from a: CIImage, to b: CIImage, progress raw: Double, canvas: CGRect, k: CGFloat) -> CIImage {
        let p = min(max(raw, 0), 1)
        func dissolve(_ x: CIImage, _ y: CIImage, _ t: Double) -> CIImage {
            x.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: y, kCIInputTimeKey: t])
        }
        let w = canvas.width
        switch kind {
        case .dissolve:
            return dissolve(a, b, p)
        case .fadeBlack, .fadeWhite:
            let color = CIImage(color: kind == .fadeBlack ? .black : .white).cropped(to: canvas)
            return p < 0.5 ? dissolve(a.composited(over: color), color, p * 2) : dissolve(color, b.composited(over: color), p * 2 - 1)
        case .wipeLeft:
            let revealed = b.cropped(to: CGRect(x: canvas.maxX - w * p, y: canvas.minY, width: w * p, height: canvas.height))
            return revealed.composited(over: a)
        case .wipeRight:
            let revealed = b.cropped(to: CGRect(x: canvas.minX, y: canvas.minY, width: w * p, height: canvas.height))
            return revealed.composited(over: a)
        case .slideLeft:
            let eased = Animations.ease(p)
            return b.transformed(by: CGAffineTransform(translationX: w * (1 - eased), y: 0))
                .composited(over: a.transformed(by: CGAffineTransform(translationX: -w * eased, y: 0)))
                .cropped(to: canvas)
        case .slideRight:
            let eased = Animations.ease(p)
            return b.transformed(by: CGAffineTransform(translationX: -w * (1 - eased), y: 0))
                .composited(over: a.transformed(by: CGAffineTransform(translationX: w * eased, y: 0)))
                .cropped(to: canvas)
        case .zoom:
            let s = 1 + 0.6 * p
            let zoomed = a.transformed(by: CGAffineTransform(translationX: -canvas.midX, y: -canvas.midY)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: canvas.midX, y: canvas.midY)))
                .cropped(to: canvas)
            return dissolve(zoomed, b, p)
        case .blur:
            let mixed = dissolve(a, b, p)
            let sigma = sin(p * .pi) * 22 * k
            guard sigma > 0.5 else { return mixed }
            return mixed.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: canvas)
        }
    }
}
