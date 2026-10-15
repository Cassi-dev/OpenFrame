import CoreImage
import Foundation

/// Miniaturas animadas para o inspetor, feitas com o mesmo `FrameRenderer` da
/// exportação (prévia = resultado).
public enum AnimationPreview {
    public enum Subject: Sendable { case text(TextContent), image(CGImage) }
    public enum Part: Hashable, Sendable { case entry(AnimationKind), exit(AnimationKind), loop(LoopKind) }

    /// Duração da animação de entrada/saída na prévia e pausa no repouso.
    static let animationDuration: Micros = 600_000
    static let hold: Micros = 600_000

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let renderer = FrameRenderer()

    /// `count` quadros de um ciclo que se repete. Entrada: a animação e depois uma pausa no repouso.
    /// Saída: repouso e depois a saída. Loop: dois períodos, na intensidade máxima. O texto é centralizado e redimensionado
    /// para caber; a imagem é encaixada. Fundo transparente.
    public static func frames(subject: Subject, part: Part, size: CGSize, count: Int) -> [CGImage] {
        let pixels = CGSize(width: max(2, size.width.rounded()), height: max(2, size.height.rounded()))
        guard count > 0, var plan = plan(subject, size: pixels),
              let id = plan.project.tracks.lazy.flatMap(\.segments).first?.id
        else { return [] }

        let cycle: Micros
        var duration: Micros
        switch part {
        case .entry(let kind):
            cycle = animationDuration + hold
            duration = cycle * 10
            TimelineEditor.update(&plan.project, segment: id) {
                $0.animationIn = SegmentAnimation(kind: kind, duration: animationDuration)
            }
        case .exit(let kind):
            cycle = animationDuration + hold
            duration = cycle
            TimelineEditor.update(&plan.project, segment: id) {
                $0.animationOut = SegmentAnimation(kind: kind, duration: animationDuration)
            }
        case .loop(let kind):
            // Intensidade máxima: na miniatura, o efeito padrão mal aparece.
            let loop = LoopAnimation(kind: kind, intensity: 1)
            cycle = loop.period * 2
            duration = cycle * 10
            TimelineEditor.update(&plan.project, segment: id) { $0.animationLoop = loop }
        }
        TimelineEditor.update(&plan.project, segment: id) { $0.source.duration = duration }

        let rect = CGRect(origin: .zero, size: pixels)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return (0..<count).compactMap { i in
            let t = Micros((Double(cycle) * Double(i) / Double(count)).rounded())
            let image = renderer.render(plan: plan, time: min(t, duration - 1)) { _ in nil }
            return context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: space)
        }
    }

    /// Projeto de um elemento só, centralizado, num canvas transparente do tamanho da prévia.
    private static func plan(_ subject: Subject, size: CGSize) -> RenderPlan? {
        var project = Project()
        project.canvas.background = .color(RGBA(0, 0, 0, 0))
        var stills: [UUID: CIImage] = [:]
        switch subject {
        case .text(let content):
            guard let fitted = fit(content, canvas: size) else { return nil }
            TimelineEditor.addText(fitted, to: &project, at: 0)
        case .image(let cg):
            let m = Material(kind: .photo, path: "", name: "", duration: 0, width: cg.width, height: cg.height, hasAudio: false)
            stills[m.id] = CIImage(cgImage: cg)
            TimelineEditor.addMedia(m, to: &project)
        }
        var plan = RenderPlan(project: project, renderSize: size)
        plan.stills = stills
        return plan
    }

    /// Centraliza o texto e muda o tamanho da fonte (não a escala, para ficar nítido)
    /// até a caixa ocupar boa parte da prévia, mantendo as quebras de linha.
    private static func fit(_ content: TextContent, canvas: CGSize) -> TextContent? {
        var c = content
        c.style.x = 0
        c.style.y = 0
        c.style.scale = 1
        c.style.rotation = 0
        guard let box = TextRenderer.shared.boxSize(for: c, canvas: canvas), box.width > 0, box.height > 0 else { return nil }
        let factor = min(canvas.width * 0.8 / box.width, canvas.height * 0.6 / box.height)
        c.style.fontSize *= factor
        c.style.maxWidth *= factor
        return c
    }
}
