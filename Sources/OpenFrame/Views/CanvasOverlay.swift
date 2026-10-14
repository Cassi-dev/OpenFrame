import AppKit
import OpenFrameCore
import SwiftUI

// Manipulação direta no preview: seleção, alças de escala, rotação e largura
// (texto) e guias de encaixe. A geometria e o gesto ficam em tipos puros; a view só desenha.

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
    /// Alças no meio das laterais para mudar a largura da caixa (só em texto).
    var resizesWidth = false

    static let rotationHandleGap: CGFloat = 26

    /// Caixa de meia largura e meia altura dadas (pontos), girada em torno do centro.
    init(center: CGPoint, halfSize: CGSize, rotation: Double, resizesWidth: Bool = false) {
        self.center = center
        self.rotation = rotation
        self.resizesWidth = resizesWidth
        let local = [CGPoint(x: -halfSize.width, y: -halfSize.height), CGPoint(x: halfSize.width, y: -halfSize.height),
                     CGPoint(x: halfSize.width, y: halfSize.height), CGPoint(x: -halfSize.width, y: halfSize.height)]
        corners = local.map { Self.rotate($0, by: rotation) + center }
    }

    /// Cantos já calculados (pelo núcleo), na ordem acima.
    init(center: CGPoint, corners: [CGPoint], rotation: Double, resizesWidth: Bool = false) {
        self.center = center
        self.corners = corners
        self.rotation = rotation
        self.resizesWidth = resizesWidth
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

    /// Direção "para a direita" do elemento girado, unitária: o eixo em que as alças laterais andam.
    var right: CGPoint { Self.rotate(CGPoint(x: 1, y: 0), by: rotation) }

    var rotationHandle: CGPoint { topCenter + up * Self.rotationHandleGap }

    /// Ponto médio da borda de baixo (do elemento girado).
    var bottomCenter: CGPoint { (corners[2] + corners[3]) * 0.5 }

    /// Ponto médio de uma lateral.
    func edgeHandle(_ side: EdgeSide) -> CGPoint {
        side == .left ? (corners[0] + corners[3]) * 0.5 : (corners[1] + corners[2]) * 0.5
    }

    /// A caixa está de pé (girada 0° ou 180°): as alças laterais andam na horizontal da tela.
    var isUpright: Bool {
        let r = abs(rotation.truncatingRemainder(dividingBy: 180))
        return r < 1 || r > 179
    }

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

    /// Alça sob o ponto: alças primeiro (com folga; a mais próxima ganha), depois o corpo.
    func handle(at p: CGPoint, tolerance: CGFloat = 9) -> OverlayHandle? {
        if (p - rotationHandle).length <= tolerance + 3 { return .rotate }
        var handles = corners.indices.map { (OverlayHandle.corner($0), corners[$0]) }
        if resizesWidth { handles += EdgeSide.allCases.map { (OverlayHandle.edge($0), edgeHandle($0)) } }
        if let nearest = handles.min(by: { (p - $0.1).length < (p - $1.1).length }),
           (p - nearest.1).length <= tolerance {
            return nearest.0
        }
        return contains(p) ? .body : nil
    }
}

enum EdgeSide: CaseIterable {
    case left, right

    /// Sentido em que arrastar alarga: para fora da caixa.
    var sign: CGFloat { self == .left ? -1 : 1 }
}

enum OverlayHandle: Equatable {
    case body, corner(Int), rotate, edge(EdgeSide)
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
    /// Elemento no início do gesto e os demais (alvos das guias).
    let box: ElementBox
    let others: [ElementBox]
    /// Ponto inicial do ponteiro e centro do elemento, em pontos da view.
    let startPoint: CGPoint
    let startCenterView: CGPoint
    /// Largura da caixa (fração da largura do canvas) de onde parte o arraste lateral.
    let startWidth: Double

    static let scaleRange = 0.05...10.0
    /// Distância de encaixe na tela.
    static let snapPoints: CGFloat = 6

    /// Resultado de um passo do gesto, no espaço do canvas.
    struct Placement: Equatable {
        var center: CGPoint
        var scale: Double
        var rotation: Double
        var guides: [SnapGuide] = []
        /// Graus mostrados na etiqueta durante o giro.
        var rotationLabel: Double?
        /// Largura pedida pelas alças laterais (fração da largura do canvas).
        var width: Double?
    }

    init(handle: OverlayHandle, box: ElementBox, others: [ElementBox], at point: CGPoint, mapping: CanvasMapping,
         startWidth: Double = 0) {
        self.handle = handle
        self.box = box
        self.others = others
        startPoint = point
        startCenterView = mapping.view(box.center)
        self.startWidth = startWidth
    }

    /// Posição, escala e rotação para o ponteiro em `p` (pontos da view).
    func placement(at p: CGPoint, mapping: CanvasMapping, aspect: Double, snapping: Bool) -> Placement {
        var out = Placement(center: box.center, scale: box.scale, rotation: box.rotation)
        switch handle {
        case .body:
            let proposed = proposedCenter(at: p, mapping: mapping)
            if snapping {
                let snapped = Snapping.snapMove(box, to: proposed, others: others, aspect: aspect,
                                                threshold: mapping.threshold(points: Self.snapPoints))
                out.center = snapped.center
                out.guides = snapped.guides
            } else {
                out.center = proposed
            }
        case .corner:
            out.scale = proposedScale(at: p)
        case .rotate:
            let r = proposedRotation(at: p)
            out.rotation = snapping ? Snapping.snapRotation(r).degrees : r
            out.rotationLabel = out.rotation
        case .edge(let side):
            out.width = proposedWidth(at: p, side: side, mapping: mapping)
        }
        return out
    }

    /// Largura simétrica em torno do centro: o quanto o ponteiro andou no eixo girado da caixa,
    /// para fora, conta dos dois lados. Desfaz a escala do elemento.
    func proposedWidth(at p: CGPoint, side: EdgeSide, mapping: CanvasMapping) -> Double {
        let axis = SelectionFrame.rotate(CGPoint(x: 1, y: 0), by: box.rotation)
        let d = p - startPoint
        let outward = (d.x * axis.x + d.y * axis.y) * side.sign
        let pointsPerWidth = max(abs(box.scale), 0.01) * mapping.size.width
        let w = startWidth + Double(2 * outward / max(pointsPerWidth, 1))
        return min(max(w, TextBoxWidth.range.lowerBound), TextBoxWidth.range.upperBound)
    }

    /// Centro proposto (normalizado) para um arraste do corpo.
    func proposedCenter(at p: CGPoint, mapping: CanvasMapping) -> CGPoint {
        let d = mapping.canvasDelta(CGSize(width: p.x - startPoint.x, height: p.y - startPoint.y))
        return CGPoint(x: box.center.x + d.width, y: box.center.y + d.height)
    }

    /// Escala uniforme pela distância ao centro, relativa ao início do gesto.
    func proposedScale(at p: CGPoint) -> Double {
        let start = (startPoint - startCenterView).length
        guard start > 1 else { return box.scale }
        let s = box.scale * Double((p - startCenterView).length / start)
        return min(max(s, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    /// Rotação (graus, horário) pelo ângulo do ponteiro em torno do centro, em -180...180.
    func proposedRotation(at p: CGPoint) -> Double {
        func angle(_ q: CGPoint) -> Double { atan2(Double(q.y - startCenterView.y), Double(q.x - startCenterView.x)) }
        let delta = (angle(p) - angle(startPoint)) * 180 / .pi
        return Self.normalized(box.rotation + delta)
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

extension SelectionFrame {
    /// Contorno de uma caixa do núcleo em pontos da view.
    init(_ box: ElementBox, mapping: CanvasMapping, aspect: Double) {
        self.init(center: mapping.view(box.center),
                  corners: CanvasLayout.corners(of: box, aspect: aspect).map(mapping.view),
                  rotation: box.rotation, resizesWidth: box.isText)
    }
}

/// Largura da caixa de um texto (`TextStyle.maxWidth`, fração da largura do canvas).
/// PROVISÓRIO até a etapa 1 do núcleo: troca por `TextStyle.maxWidthRange` e
/// `TimelineEditor.setTextWidth`, que fazem o mesmo (numa faixa de legendas automáticas,
/// a largura vale para todos os textos dela).
enum TextBoxWidth {
    static let range: ClosedRange<Double> = 0.1...3.0

    static func set(_ p: inout Project, segment id: UUID, maxWidth: Double) {
        guard let loc = p.locate(id) else { return }
        let w = min(max(maxWidth, range.lowerBound), range.upperBound)
        let track = p.tracks[loc.track]
        let targets = track.isAutoCaptions ? track.segments.map(\.id) : [id]
        for target in targets {
            TimelineEditor.update(&p, segment: target) { $0.text?.style.maxWidth = w }
        }
    }
}

/// Estado do arraste lateral mostrado no preview.
struct WidthDragState: Equatable {
    /// Largura pedida (fração da largura do canvas): a moldura mostra a caixa de quebra.
    var width: Double
    /// O texto está numa faixa de legendas automáticas: a largura vale para todas.
    var wholeTrack: Bool

    var label: String {
        let percent = String(format: "%.0f%%", width * 100)
        return wholeTrack ? "\(percent) · todas as legendas" : percent
    }
}

extension OverlayGuide {
    init(_ guide: SnapGuide, mapping: CanvasMapping) {
        let vertical = guide.axis == .vertical
        let p = mapping.view(CGPoint(x: guide.position, y: guide.position))
        self.init(vertical: vertical, position: vertical ? p.x : p.y,
                  strong: guide.kind == .canvasCenter, dashed: guide.kind == .safeMargin)
    }
}

// MARK: - Gesto no modelo

extension EditorModel {
    /// Elementos visíveis no playhead (em repouso).
    func canvasBoxes() -> [ElementBox] { CanvasLayout.boxes(in: project, at: playhead) }

    /// Contorno do elemento selecionado, se ele aparece no playhead. Some durante a reprodução.
    /// Durante o arraste lateral, mostra a largura pedida (a caixa de quebra), não a do texto.
    func selectionFrame(mapping: CanvasMapping) -> SelectionFrame? {
        guard !isPlaying, let id = selection, var box = canvasBoxes().first(where: { $0.id == id }) else { return nil }
        if let widthDrag = canvasWidthDrag { box.size.width = widthDrag.width * 2 }
        return SelectionFrame(box, mapping: mapping, aspect: project.aspectValue)
    }

    /// O texto está numa faixa de legendas automáticas (a largura da caixa vale para a faixa toda).
    func isInAutoCaptions(_ id: UUID) -> Bool {
        project.locate(id).map { project.tracks[$0.track].isAutoCaptions } ?? false
    }

    /// Clique no preview: alça ou corpo do selecionado, senão o elemento mais acima
    /// sob o ponteiro, senão tira a seleção. Duplo clique num texto abre a aba Texto.
    func canvasPointerDown(at p: CGPoint, mapping: CanvasMapping, clickCount: Int = 1) {
        guard !isPlaying else { return }
        let boxes = canvasBoxes()
        let aspect = project.aspectValue
        var target: (box: ElementBox, handle: OverlayHandle)?
        if let id = selection, let box = boxes.first(where: { $0.id == id }),
           let handle = SelectionFrame(box, mapping: mapping, aspect: aspect).handle(at: p) {
            target = (box, handle)
        } else if let id = CanvasLayout.hitTest(mapping.canvas(p), in: boxes, aspect: aspect),
                  let box = boxes.first(where: { $0.id == id }) {
            target = (box, .body)
        }
        guard let target else {
            selection = nil
            return
        }
        if clickCount >= 2, target.box.isText {
            editText(target.box.id)
        } else {
            selection = target.box.id
        }
        placementDrag = PlacementDrag(handle: target.handle, box: target.box,
                                      others: boxes.filter { $0.id != target.box.id }, at: p, mapping: mapping,
                                      startWidth: startWidth(target.box))
        beginGesture()
    }

    /// De onde parte o arraste lateral. Numa legenda automática, da largura de quebra da faixa:
    /// partir da largura do texto desta legenda estreitaria todas as outras. Num texto solto,
    /// da caixa que se vê (num texto curto, a largura de quebra fica bem além dele).
    private func startWidth(_ box: ElementBox) -> Double {
        guard box.isText, let style = project.segment(box.id)?.text?.style else { return 0 }
        return isInAutoCaptions(box.id) ? style.maxWidth : min(Double(box.size.width) / 2, style.maxWidth)
    }

    func canvasPointerMoved(to p: CGPoint, mapping: CanvasMapping) {
        guard let drag = placementDrag else { return }
        let result = drag.placement(at: p, mapping: mapping, aspect: project.aspectValue,
                                    snapping: PlacementDrag.snappingEnabled)
        if canvasGuides != result.guides { canvasGuides = result.guides }
        if canvasRotationLabel != result.rotationLabel { canvasRotationLabel = result.rotationLabel }
        if case .edge = drag.handle, let width = result.width {
            // O clique sem arrastar não muda nada (nem cria um passo de desfazer).
            guard p != drag.startPoint || canvasWidthDrag != nil else { return }
            canvasWidthDrag = WidthDragState(width: width, wholeTrack: isInAutoCaptions(drag.box.id))
            updateGesture { TextBoxWidth.set(&$0, segment: drag.box.id, maxWidth: width) }
            return
        }
        updateGesture {
            TimelineEditor.setPlacement(&$0, segment: drag.box.id, center: result.center,
                                        scale: result.scale, rotation: result.rotation)
        }
    }

    func canvasPointerUp() {
        guard placementDrag != nil else { return }
        placementDrag = nil
        canvasGuides = []
        canvasRotationLabel = nil
        canvasWidthDrag = nil
        endGesture()
    }
}

// MARK: - Camada do preview

/// Recebe cliques e arrastes sobre o vídeo (mesmo quadro do player) e desenha a seleção.
struct CanvasManipulationLayer: View {
    @Environment(EditorModel.self) private var model
    @State private var pressed = false

    var body: some View {
        GeometryReader { geo in
            let mapping = CanvasMapping(size: geo.size)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            if !pressed {
                                pressed = true
                                model.canvasPointerDown(at: value.startLocation, mapping: mapping,
                                                        clickCount: NSApp.currentEvent?.clickCount ?? 1)
                            }
                            model.canvasPointerMoved(to: value.location, mapping: mapping)
                        }
                        .onEnded { _ in
                            pressed = false
                            model.canvasPointerUp()
                        })
                    .onContinuousHover { phase in
                        guard case .active(let p) = phase else { return NSCursor.arrow.set() }
                        cursor(at: p, mapping: mapping).set()
                    }
                SelectionOverlayDrawing(frame: model.selectionFrame(mapping: mapping),
                                        guides: model.canvasGuides.map { OverlayGuide($0, mapping: mapping) },
                                        rotationLabel: model.canvasRotationLabel,
                                        widthLabel: model.canvasWidthDrag?.label)
            }
        }
        .allowsHitTesting(!model.isPlaying)
    }

    private func cursor(at p: CGPoint, mapping: CanvasMapping) -> NSCursor {
        let frame = model.selectionFrame(mapping: mapping)
        if let drag = model.placementDrag {
            if case .edge = drag.handle, frame?.isUpright ?? true { return .resizeLeftRight }
            return .closedHand
        }
        switch frame?.handle(at: p) {
        case .rotate?, .corner?: return .crosshair
        case .edge?: return frame?.isUpright ?? true ? .resizeLeftRight : .crosshair
        case .body?: return .openHand
        case nil:
            let hit = CanvasLayout.hitTest(mapping.canvas(p), in: model.canvasBoxes(), aspect: model.project.aspectValue)
            return hit == nil ? .arrow : .pointingHand
        }
    }
}

// MARK: - Desenho

/// Guias, contorno, alças e etiqueta de graus. Não recebe cliques.
struct SelectionOverlayDrawing: View {
    var frame: SelectionFrame?
    var guides: [OverlayGuide]
    /// Etiqueta de graus durante o giro.
    var rotationLabel: Double?
    /// Etiqueta da largura durante o arraste lateral.
    var widthLabel: String?

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
                if frame.resizesWidth {
                    for side in EdgeSide.allCases { drawEdgeHandle(frame.edgeHandle(side), frame: frame, in: &ctx) }
                }
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
            if let widthLabel, let frame {
                Text(widthLabel)
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1))
                    .fixedSize()
                    .position(frame.bottomCenter - frame.up * 22)
            }
        }
        .allowsHitTesting(false)
    }

    /// Pílula vertical curta, girada com a caixa: diferente dos cantos quadrados.
    private func drawEdgeHandle(_ point: CGPoint, frame: SelectionFrame, in ctx: inout GraphicsContext) {
        let pill = Path(roundedRect: CGRect(x: -3, y: -8, width: 6, height: 16), cornerRadius: 3)
            .applying(CGAffineTransform(rotationAngle: frame.rotation * .pi / 180)
                .concatenating(CGAffineTransform(translationX: point.x, y: point.y)))
        ctx.fill(pill, with: .color(.white))
        ctx.stroke(pill, with: .color(Theme.accent), lineWidth: 1.5)
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
