import CoreGraphics
import Foundation

/// Caixa de um elemento visual em repouso (sem animação), no espaço normalizado do canvas:
/// x e y vão de -1 a 1 (centro 0, y para cima), como `Transform` e `TextStyle`.
public struct ElementBox: Hashable, Sendable {
    public let id: UUID
    public let isText: Bool
    public var center: CGPoint
    /// Tamanho com escala 1 e sem rotação, nas mesmas unidades (a largura do canvas inteiro vale 2).
    /// No texto, é a caixa do texto (mais o fundo, se ligado), sem as margens de sombra.
    public var size: CGSize
    public var scale: Double
    /// Graus, positivo = horário na tela (o mesmo sentido de `Transform.rotation`).
    public var rotation: Double

    public init(id: UUID, isText: Bool, center: CGPoint, size: CGSize, scale: Double, rotation: Double) {
        self.id = id
        self.isText = isText
        self.center = center
        self.size = size
        self.scale = scale
        self.rotation = rotation
    }
}

/// Geometria dos elementos no canvas, para selecionar, desenhar contornos e alinhar no preview.
/// Segue as mesmas contas do `FrameRenderer`: a rotação acontece em pixels, por isso as funções
/// que giram recebem a proporção do canvas.
public enum CanvasLayout {
    /// Lado menor do canvas de referência para medir texto (o tamanho normalizado quase não
    /// depende da resolução).
    static let referenceShortSide = 1080

    /// Elementos visíveis no instante, na ordem de desenho (o primeiro fica embaixo).
    /// Inclui foto e vídeo (todas as faixas de vídeo visíveis) e texto. Ignora faixas ocultas.
    public static func boxes(in project: Project, at time: Micros) -> [ElementBox] {
        let aspect = project.aspectValue
        var result: [ElementBox] = []
        for track in project.tracks where track.kind == .video && !track.hidden {
            let active = track.segments
                .filter { $0.targetRange.contains(time) }
                .sorted { $0.targetStart < $1.targetStart }
            for seg in active {
                guard let m = project.material(seg.materialId), m.isVisual, m.width > 0, m.height > 0 else { continue }
                let t = seg.transform
                result.append(ElementBox(id: seg.id, isText: false, center: CGPoint(x: t.x, y: t.y),
                                         size: fitSize(Double(m.width) / Double(m.height), canvasAspect: aspect),
                                         scale: t.scale, rotation: t.rotation))
            }
        }
        let canvas = project.canvasSize(shortSide: referenceShortSide)
        for track in project.tracks where track.kind == .text && !track.hidden {
            for seg in track.segments where seg.targetRange.contains(time) {
                guard let content = seg.text,
                      let px = TextRenderer.shared.boxSize(for: content, canvas: canvas) else { continue }
                let s = content.style
                result.append(ElementBox(id: seg.id, isText: true, center: CGPoint(x: s.x, y: s.y),
                                         size: CGSize(width: px.width / canvas.width * 2, height: px.height / canvas.height * 2),
                                         scale: s.scale, rotation: s.rotation))
            }
        }
        return result
    }

    /// Tamanho normalizado de uma mídia encaixada (`fit`) no canvas.
    static func fitSize(_ mediaAspect: Double, canvasAspect: Double) -> CGSize {
        mediaAspect >= canvasAspect
            ? CGSize(width: 2, height: 2 * canvasAspect / mediaAspect)
            : CGSize(width: 2 * mediaAspect / canvasAspect, height: 2)
    }

    /// Id do elemento mais acima sob o ponto (normalizado). `aspect` = largura/altura do canvas,
    /// necessário porque a rotação acontece em pixels.
    public static func hitTest(_ point: CGPoint, in boxes: [ElementBox], aspect: Double) -> UUID? {
        for box in boxes.reversed() {
            // Para o espaço da caixa: em unidades de meia altura do canvas, desfazendo a rotação.
            let dx = (point.x - box.center.x) * aspect
            let dy = point.y - box.center.y
            let a = -box.rotation * .pi / 180
            let u = dx * cos(a) + dy * sin(a)
            let v = -dx * sin(a) + dy * cos(a)
            let halfW = box.size.width * abs(box.scale) * aspect / 2
            let halfH = box.size.height * abs(box.scale) / 2
            if abs(u) <= halfW, abs(v) <= halfH { return box.id }
        }
        return nil
    }

    /// Os 4 cantos da caixa girada e escalada, em coordenadas normalizadas (para desenhar e alinhar).
    /// Ordem: superior esquerdo, superior direito, inferior direito, inferior esquerdo (antes de girar).
    public static func corners(of box: ElementBox, aspect: Double) -> [CGPoint] {
        let halfW = box.size.width * box.scale * aspect / 2
        let halfH = box.size.height * box.scale / 2
        // Horário na tela com y para cima = ângulo negativo.
        let a = -box.rotation * .pi / 180
        return [(-halfW, halfH), (halfW, halfH), (halfW, -halfH), (-halfW, -halfH)].map { u, v in
            let x = u * cos(a) - v * sin(a)
            let y = u * sin(a) + v * cos(a)
            return CGPoint(x: box.center.x + x / aspect, y: box.center.y + y)
        }
    }

    /// Caixa alinhada aos eixos que envolve o elemento já girado.
    public static func bounds(of box: ElementBox, aspect: Double) -> CGRect {
        let pts = corners(of: box, aspect: aspect)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
