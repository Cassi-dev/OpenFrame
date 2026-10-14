import CoreImage
import Foundation

/// Animação por unidade (letra, palavra ou linha) em andamento.
struct UnitAnimation: Equatable {
    var kind: AnimationKind
    /// Progresso linear no tempo: 0 = início da entrada (ou fim da saída), 1 = repouso.
    var progress: Double
    var exiting: Bool
}

/// Estado de uma animação de entrada/saída num instante.
struct AnimationState {
    var scale = 1.0
    var dx = 0.0
    var dy = 0.0
    var rotation = 0.0
    var alpha = 1.0
    /// Fração do texto visível (animação "máquina de escrever").
    var reveal = 1.0
    /// Desfoque da camada inteira, como fração da altura do canvas (animação "foco").
    var blur = 0.0
    /// Animação por unidade ativa no instante (só texto).
    var unit: UnitAnimation?
    /// Opacidade do fundo do texto durante uma animação por unidade.
    var backgroundAlpha = 1.0
    var loop: LoopAnimation?
    /// Tempo desde o início do clipe.
    var local: Micros = 0

    /// Brilho e reflexo do loop no instante (0 quando não há).
    var glow: Double {
        guard let loop, loop.kind == .glow else { return 0 }
        return Animations.clamp(loop.intensity) * (0.5 + 0.5 * sin(2 * .pi * Animations.loopPhase(loop, local: local)))
    }

    /// Posição da faixa de luz (0...1 atravessando a caixa) e força, ou nil fora da passagem.
    var shine: (position: Double, strength: Double)? {
        guard let loop, loop.kind == .shine else { return nil }
        let phase = Animations.loopPhase(loop, local: local)
        let f = (phase - phase.rounded(.down)) / 0.58
        guard f < 1 else { return nil }
        // Quase linear, com entrada e saída levemente suaves.
        let eased = 0.8 * f + 0.2 * f * f * (3 - 2 * f)
        return (eased, Animations.clamp(loop.intensity))
    }
}

enum Animations {
    static func state(for seg: Segment, local: Micros) -> AnimationState {
        var st = AnimationState()
        st.local = local
        let duration = seg.targetDuration
        if let a = seg.animationIn, a.duration > 0, local < a.duration {
            apply(a.kind, raw: Double(local) / Double(a.duration), exiting: false, to: &st)
        }
        if let a = seg.animationOut, a.duration > 0, local > duration - a.duration {
            apply(a.kind, raw: Double(duration - local) / Double(a.duration), exiting: true, to: &st)
        }
        if let loop = seg.animationLoop, loop.period > 0 {
            st.loop = loop
            applyLoop(loop, local: local, to: &st)
        }
        return st
    }

    /// Fase do loop no instante, em ciclos (0...1 = primeiro ciclo).
    static func loopPhase(_ loop: LoopAnimation, local: Micros) -> Double {
        Double(max(0, local)) / Double(max(loop.period, 1))
    }

    private static func applyLoop(_ loop: LoopAnimation, local: Micros, to st: inout AnimationState) {
        let wave = sin(2 * .pi * loopPhase(loop, local: local))
        let intensity = clamp(loop.intensity)
        switch loop.kind {
        case .float:
            st.dy += wave * 0.02 * intensity
        case .pulse:
            st.scale *= 1 + 0.05 * intensity * wave
        case .glow, .shine:
            break // desenhados pelo renderizador (`glow` e `shine` do estado)
        }
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    static func ease(_ p: Double) -> Double {
        let x = clamp(p)
        return 1 - pow(1 - x, 3)
    }

    // MARK: - Curvas (0 → 1, sem pulo no fim)

    static func expoOut(_ x: Double) -> Double {
        let x = clamp(x)
        return (1 - pow(2, -10 * x)) / (1 - pow(2, -10))
    }

    static func quartOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 4) }
    static func quintOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 5) }

    /// Mola amortecida, com ~18% de exagero; vale 0 em 0 e 1 em 1.
    static func spring(_ x: Double) -> Double {
        let x = clamp(x)
        return 1 - exp(-6 * x) * cos(3.5 * .pi * x)
    }

    /// Animações desenhadas por unidade e a granularidade de cada uma.
    static func granularity(_ kind: AnimationKind) -> TextGranularity? {
        switch kind {
        case .cascade, .elastic, .wave, .tracking, .decode, .typewriter: .letter
        case .wordByWord: .word
        case .maskReveal: .line
        default: nil
        }
    }

    static func isPerUnit(_ kind: AnimationKind) -> Bool { kind != .typewriter && granularity(kind) != nil }

    /// O texto usa o caminho por unidade no clipe inteiro (não só durante a animação),
    /// para não haver pulo entre os dois desenhos. Brilho e reflexo também precisam
    /// das letras separadas da sombra.
    static func usesUnits(_ seg: Segment) -> Bool {
        if let a = seg.animationIn, isPerUnit(a.kind) { return true }
        if let a = seg.animationOut, isPerUnit(a.kind) { return true }
        if let l = seg.animationLoop, l.kind == .glow || l.kind == .shine { return true }
        return false
    }

    /// Granularidade usada no instante: a da animação ativa; em repouso, a da entrada
    /// (ou da saída), para o desenho não mudar quando a animação termina.
    static func granularity(for seg: Segment, state: AnimationState) -> TextGranularity {
        if let u = state.unit { return granularity(u.kind) ?? .line }
        if state.reveal < 1 { return .letter }
        if let a = seg.animationIn, isPerUnit(a.kind), let g = granularity(a.kind) { return g }
        if let a = seg.animationOut, isPerUnit(a.kind), let g = granularity(a.kind) { return g }
        return .line
    }

    /// `raw` vai de 0 (invisível) a 1 (posição final), linear no tempo.
    private static func apply(_ kind: AnimationKind, raw: Double, exiting: Bool, to st: inout AnimationState) {
        let p = ease(raw)
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
        case .focus:
            let e = expoOut(raw)
            st.blur = max(st.blur, (1 - e) * 0.02)
            st.scale *= 1.08 - 0.08 * e
            st.alpha *= e
        case .cascade, .elastic, .wave, .wordByWord, .maskReveal, .tracking, .decode:
            st.unit = UnitAnimation(kind: kind, progress: clamp(raw), exiting: exiting)
            st.backgroundAlpha *= p
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
