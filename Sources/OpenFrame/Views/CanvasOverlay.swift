import AppKit
import SwiftUI

// Manipulação direta no preview: seleção, alças de escala e rotação e guias de
// encaixe. A geometria e o gesto ficam em tipos puros; a view só desenha.

/// Conversão entre o espaço normalizado do canvas (x e y de -1 a 1, centro 0,
/// y para cima) e os pontos da view do preview (origem no canto superior esquerdo).
struct CanvasMapping {
    var size: CGSize

    func view(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x + 1) / 2 * size.width, y: (1 - p.y) / 2 * size.height)
    }

    func canvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / max(size.width, 1) * 2 - 1, y: 1 - p.y / max(size.height, 1) * 2)
    }

    /// Deslocamento na tela convertido para o espaço normalizado.
    func canvasDelta(_ d: CGSize) -> CGSize {
        CGSize(width: d.width * 2 / max(size.width, 1), height: -d.height * 2 / max(size.height, 1))
    }

    /// Distância na tela (pontos) convertida para o limiar normalizado de cada eixo.
    func threshold(points: CGFloat) -> CGSize {
        CGSize(width: points * 2 / max(size.width, 1), height: points * 2 / max(size.height, 1))
    }

    var aspect: Double { size.height > 0 ? size.width / size.height : 1 }
}

/// Contorno do elemento selecionado em pontos da view.
struct SelectionFrame: Equatable {
    var center: CGPoint
    /// Cantos na ordem superior esquerdo, superior direito, inferior direito, inferior esquerdo
    /// (do elemento, antes de girar).
    var corners: [CGPoint]
    /// Graus, positivo = horário na tela.
    var rotation: Double

    static let rotationHandleGap: CGFloat = 26

    /// Caixa de meia largura e meia altura dadas (pontos), girada em torno do centro.
    init(center: CGPoint, halfSize: CGSize, rotation: Double) {
        self.center = center
        self.rotation = rotation
        let local = [CGPoint(x: -halfSize.width, y: -halfSize.height), CGPoint(x: halfSize.width, y: -halfSize.height),
                     CGPoint(x: halfSize.width, y: halfSize.height), CGPoint(x: -halfSize.width, y: halfSize.height)]
        corners = local.map { Self.rotate($0, by: rotation) + center }
    }

    /// Cantos já calculados (pelo núcleo), na ordem acima.
    init(center: CGPoint, corners: [CGPoint], rotation: Double) {
        self.center = center
        self.corners = corners
        self.rotation = rotation
    }

    /// Gira um vetor em graus no sentido horário da tela (y para baixo).
    static func rotate(_ v: CGPoint, by degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: v.x * cos(a) - v.y * sin(a), y: v.x * sin(a) + v.y * cos(a))
    }

    /// Ponto médio da borda de cima (do elemento girado).
    var topCenter: CGPoint { (corners[0] + corners[1]) * 0.5 }

    /// Direção "para cima" do elemento girado, unitária.
    var up: CGPoint { Self.rotate(CGPoint(x: 0, y: -1), by: rotation) }

    var rotationHandle: CGPoint { topCenter + up * Self.rotationHandleGap }

    func contains(_ p: CGPoint) -> Bool {
        // Ponto dentro do quadrilátero convexo: mesmo lado de todas as arestas.
        var sign: CGFloat = 0
        for i in 0..<corners.count {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross != 0 {
                if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
            }
        }
        return true
    }

    /// Alça sob o ponto: alças primeiro (com folga), depois o corpo.
    func handle(at p: CGPoint, tolerance: CGFloat = 9) -> OverlayHandle? {
        if (p - rotationHandle).length <= tolerance + 3 { return .rotate }
        if let i = corners.indices.min(by: { (p - corners[$0]).length < (p - corners[$1]).length }),
           (p - corners[i]).length <= tolerance {
            return .corner(i)
        }
        return contains(p) ? .body : nil
    }
}

enum OverlayHandle: Equatable {
    case body, corner(Int), rotate
}

/// Linha de guia em pontos da view.
struct OverlayGuide: Hashable {
    var vertical: Bool
    var position: CGFloat
    /// Centro do canvas: desenhada mais forte.
    var strong: Bool = false
    var dashed: Bool = false
}

/// Estado de um gesto no preview. Cada atualização parte do estado inicial,
/// como os gestos da timeline.
struct PlacementDrag {
    let handle: OverlayHandle
    /// Ponto inicial do ponteiro e centro do elemento, em pontos da view.
    let startPoint: CGPoint
    let startCenterView: CGPoint
    /// Valores iniciais no espaço do canvas.
    let startCenter: CGPoint
    let startScale: Double
    let startRotation: Double

    static let scaleRange = 0.05...10.0

    /// Centro proposto (normalizado) para um arraste do corpo.
    func proposedCenter(at p: CGPoint, mapping: CanvasMapping) -> CGPoint {
        let d = mapping.canvasDelta(CGSize(width: p.x - startPoint.x, height: p.y - startPoint.y))
        return CGPoint(x: startCenter.x + d.width, y: startCenter.y + d.height)
    }

    /// Escala uniforme pela distância ao centro, relativa ao início do gesto.
    func proposedScale(at p: CGPoint) -> Double {
        let start = (startPoint - startCenterView).length
        guard start > 1 else { return startScale }
        let s = startScale * Double((p - startCenterView).length / start)
        return min(max(s, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    /// Rotação (graus, horário) pelo ângulo do ponteiro em torno do centro, em -180...180.
    func proposedRotation(at p: CGPoint) -> Double {
        func angle(_ q: CGPoint) -> Double { atan2(Double(q.y - startCenterView.y), Double(q.x - startCenterView.x)) }
        let delta = (angle(p) - angle(startPoint)) * 180 / .pi
        return Self.normalized(startRotation + delta)
    }

    static func normalized(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// ⌘ segurado desliga o encaixe.
    @MainActor static var snappingEnabled: Bool { !NSEvent.modifierFlags.contains(.command) }
}

// MARK: - Desenho

/// Guias, contorno, alças e etiqueta de graus. Não recebe cliques.
struct SelectionOverlayDrawing: View {
    var frame: SelectionFrame?
    var guides: [OverlayGuide]
    /// Etiqueta de graus durante o giro.
    var rotationLabel: Double?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                for guide in guides { draw(guide, in: &ctx, size: size) }
                guard let frame else { return }
                var outline = Path()
                outline.addLines(frame.corners)
                outline.closeSubpath()
                // Contorno escuro por baixo: fica visível sobre fundos claros.
                ctx.stroke(outline, with: .color(.black.opacity(0.35)), lineWidth: 3)
                ctx.stroke(outline, with: .color(Theme.accent), lineWidth: 1.25)
                var stem = Path()
                stem.move(to: frame.topCenter)
                stem.addLine(to: frame.rotationHandle)
                ctx.stroke(stem, with: .color(Theme.accent), lineWidth: 1)
                for corner in frame.corners {
                    let r = CGRect(x: corner.x - 4.5, y: corner.y - 4.5, width: 9, height: 9)
                    let shape = Path(roundedRect: r, cornerRadius: 2.5)
                    ctx.fill(shape, with: .color(.white))
                    ctx.stroke(shape, with: .color(Theme.accent), lineWidth: 1.5)
                }
                let h = frame.rotationHandle
                let knob = Path(ellipseIn: CGRect(x: h.x - 8, y: h.y - 8, width: 16, height: 16))
                ctx.fill(knob, with: .color(.white))
                ctx.stroke(knob, with: .color(Theme.accent), lineWidth: 1.5)
                ctx.draw(Text(Image(systemName: "arrow.clockwise")).font(.system(size: 8, weight: .bold))
                    .foregroundColor(.black), at: h)
            }
            if let rotationLabel, let frame {
                Text(String(format: "%.0f°", rotationLabel))
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Theme.accent, in: Capsule())
                    .fixedSize()
                    .position(frame.rotationHandle + frame.up * 22)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ guide: OverlayGuide, in ctx: inout GraphicsContext, size: CGSize) {
        var path = Path()
        if guide.vertical {
            path.move(to: CGPoint(x: guide.position, y: 0))
            path.addLine(to: CGPoint(x: guide.position, y: size.height))
        } else {
            path.move(to: CGPoint(x: 0, y: guide.position))
            path.addLine(to: CGPoint(x: size.width, y: guide.position))
        }
        let style = StrokeStyle(lineWidth: guide.strong ? 1.25 : 0.75, dash: guide.dashed ? [4, 3] : [])
        ctx.stroke(path, with: .color(Theme.accent.opacity(guide.strong ? 1 : 0.7)), style: style)
    }
}

// MARK: - Vetores

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
}
