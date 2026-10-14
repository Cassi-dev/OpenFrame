import CoreGraphics
import Foundation

public struct SnapGuide: Hashable, Sendable {
    /// `vertical` = linha em x constante.
    public enum Axis: Sendable { case vertical, horizontal }
    public enum Kind: Sendable { case canvasCenter, canvasEdge, safeMargin, element }

    public var axis: Axis
    /// Normalizado.
    public var position: Double
    public var kind: Kind

    public init(axis: Axis, position: Double, kind: Kind) {
        self.axis = axis
        self.position = position
        self.kind = kind
    }
}

/// Ímã do preview: alinha elementos ao canvas e entre si, e a rotação a múltiplos de 45°.
public enum Snapping {
    /// Margem de segurança, como fração do meio canvas.
    public static let safeMargin = 0.9

    /// Encaixa o centro proposto. Alvos: centro do canvas (0), bordas (±1), margem de segurança (±0,9),
    /// e o centro e as bordas dos outros elementos. Valem as bordas e o centro da caixa alinhada aos eixos
    /// (já girada) do elemento. `threshold` é normalizado por eixo (a interface converte ~6 pt da tela).
    /// O alvo mais próximo vence em cada eixo, e as guias devolvidas são as dos alvos encaixados.
    public static func snapMove(_ box: ElementBox, to proposed: CGPoint, others: [ElementBox],
                                aspect: Double, threshold: CGSize) -> (center: CGPoint, guides: [SnapGuide]) {
        // Bordas relativas ao centro: o encaixe pelo centro dá exatamente o valor do alvo.
        var origin = box
        origin.center = .zero
        let offsets = CanvasLayout.bounds(of: origin, aspect: aspect)
        let otherBounds = others.filter { $0.id != box.id }.map { CanvasLayout.bounds(of: $0, aspect: aspect) }

        func targets(_ values: (CGRect) -> [Double]) -> [(Double, SnapGuide.Kind)] {
            var t: [(Double, SnapGuide.Kind)] = [(0, .canvasCenter), (-1, .canvasEdge), (1, .canvasEdge),
                                                 (-safeMargin, .safeMargin), (safeMargin, .safeMargin)]
            for r in otherBounds { t += values(r).map { ($0, .element) } }
            return t
        }

        /// Novo centro no eixo e as guias dos alvos alinhados depois do encaixe.
        func snap(_ center: Double, offsets: [Double], targets: [(Double, SnapGuide.Kind)], threshold: Double,
                  axis: SnapGuide.Axis) -> (center: Double, guides: [SnapGuide]) {
            var best: (distance: Double, center: Double)?
            for offset in offsets {
                for (t, _) in targets {
                    let d = abs(t - (center + offset))
                    if d <= threshold, d < best?.distance ?? .infinity { best = (d, t - offset) }
                }
            }
            guard let snapped = best?.center else { return (center, []) }
            // Um alvo por posição; se houver mais de um, fica o mais forte.
            var byPosition: [(Double, SnapGuide.Kind)] = []
            for offset in offsets {
                for (t, kind) in targets where abs(t - (snapped + offset)) < 1e-9 {
                    if let i = byPosition.firstIndex(where: { abs($0.0 - t) < 1e-9 }) {
                        if rank(kind) < rank(byPosition[i].1) { byPosition[i].1 = kind }
                    } else {
                        byPosition.append((t, kind))
                    }
                }
            }
            return (snapped, byPosition.map { SnapGuide(axis: axis, position: $0.0, kind: $0.1) })
        }

        let x = snap(proposed.x, offsets: [offsets.minX, 0, offsets.maxX],
                     targets: targets { [$0.minX, $0.midX, $0.maxX] },
                     threshold: threshold.width, axis: .vertical)
        let y = snap(proposed.y, offsets: [offsets.minY, 0, offsets.maxY],
                     targets: targets { [$0.minY, $0.midY, $0.maxY] },
                     threshold: threshold.height, axis: .horizontal)
        return (CGPoint(x: x.center, y: y.center), x.guides + y.guides)
    }

    private static func rank(_ kind: SnapGuide.Kind) -> Int {
        switch kind {
        case .canvasCenter: 0
        case .canvasEdge: 1
        case .safeMargin: 2
        case .element: 3
        }
    }

    /// Encaixa em múltiplos de 45° quando está a menos de `threshold` graus.
    public static func snapRotation(_ degrees: Double, threshold: Double = 4) -> (degrees: Double, snapped: Bool) {
        let nearest = (degrees / 45).rounded() * 45
        return abs(nearest - degrees) < threshold ? (nearest, true) : (degrees, false)
    }
}
