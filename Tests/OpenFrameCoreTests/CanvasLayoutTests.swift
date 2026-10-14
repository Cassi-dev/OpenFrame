import CoreImage
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Layout do canvas e ímã")
struct CanvasLayoutTests {
    let aspect = 16.0 / 9

    func photo(width: Int = 400, height: Int = 300) throws -> Material {
        let url = try TestMedia.makePNG(width: width, height: height, color: CIColor(red: 1, green: 1, blue: 1))
        return Material(kind: .photo, path: url.path, name: url.lastPathComponent, duration: 0,
                        width: width, height: height, hasAudio: false)
    }

    func box(_ x: Double, _ y: Double, w: Double = 0.4, h: Double = 0.4, scale: Double = 1, rotation: Double = 0,
             id: UUID = UUID()) -> ElementBox {
        ElementBox(id: id, isText: false, center: CGPoint(x: x, y: y), size: CGSize(width: w, height: h),
                   scale: scale, rotation: rotation)
    }

    func close(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

    // MARK: - Caixas

    @Test("Caixas em ordem de desenho, com tamanho encaixado e faixas ocultas de fora")
    func boxesOrderAndSize() throws {
        var p = Project()
        p.canvas.aspect = .r16x9
        let main = TimelineEditor.addMedia(try photo(), to: &p)
        let overlay = TimelineEditor.addOverlay(try photo(width: 100, height: 400), to: &p, at: 0)
        TimelineEditor.update(&p, segment: overlay) {
            $0.transform.x = 0.3
            $0.transform.y = -0.2
            $0.transform.rotation = 15
        }
        let text = TimelineEditor.addText(TextContent(text: "Olá"), to: &p, at: 0)
        let hidden = TimelineEditor.addText(TextContent(text: "Some"), to: &p, at: 0)
        let hiddenTrack = p.locate(hidden)!.track
        p.tracks[hiddenTrack].hidden = true

        let boxes = CanvasLayout.boxes(in: p, at: 1_000_000)
        #expect(boxes.map(\.id) == [main, overlay, text])
        // Foto 4:3 num canvas 16:9: altura inteira (2) e largura 2·(4/3)/(16/9) = 1,5.
        #expect(close(boxes[0].size.width, 1.5) && close(boxes[0].size.height, 2))
        #expect(!boxes[0].isText && boxes[2].isText)
        // Foto em pé 1:4: altura inteira, largura 2·(1/4)/(16/9).
        #expect(close(boxes[1].size.width, 2 * 0.25 / aspect) && close(boxes[1].size.height, 2))
        #expect(boxes[1].center == CGPoint(x: 0.3, y: -0.2) && boxes[1].scale == 0.5 && boxes[1].rotation == 15)
        #expect(boxes[2].center == CGPoint(x: 0, y: -0.7))

        // Depois do fim dos clipes não sobra nada.
        #expect(CanvasLayout.boxes(in: p, at: 60_000_000).isEmpty)
    }

    @Test("Caixa do texto bate com o que é desenhado e cresce com o fundo")
    func textBoxMatchesRender() throws {
        var p = Project()
        p.canvas.aspect = .r16x9
        var style = TextStyle()
        style.shadow = false
        style.backgroundEnabled = true
        style.backgroundColor = RGBA(1, 1, 1)
        style.x = 0.2
        style.y = 0.1
        let id = TimelineEditor.addText(TextContent(text: "Caixa de texto", style: style), to: &p, at: 0)
        let box = CanvasLayout.boxes(in: p, at: 0).first { $0.id == id }!

        // Sem fundo, a caixa diminui exatamente o enchimento do fundo (0,21 em de cada lado).
        var plain = p
        TimelineEditor.update(&plain, segment: id) { $0.text!.style.backgroundEnabled = false }
        let small = CanvasLayout.boxes(in: plain, at: 0).first!
        let padY = 2 * 0.21 * style.fontSize * 2
        #expect(close(box.size.height - small.size.height, padY, 0.004))

        // O fundo branco desenhado ocupa a caixa (até ~2 px de arredondamento a 1280×720).
        let size = CGSize(width: 1280, height: 720)
        let bmp = Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: 0) { _ in nil }, size: size)
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<bmp.height {
            for x in 0..<bmp.width where bmp.data[(y * bmp.width + x) * 4] > 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let expectedW = box.size.width / 2 * size.width
        let expectedH = box.size.height / 2 * size.height
        #expect(abs(Double(maxX - minX + 1) - expectedW) < 3)
        #expect(abs(Double(maxY - minY + 1) - expectedH) < 3)
        let cx = (Double(minX + maxX + 1) / 2) / size.width * 2 - 1
        let cy = 1 - (Double(minY + maxY + 1) / 2) / size.height * 2
        #expect(close(cx, 0.2, 0.005) && close(cy, 0.1, 0.005))
    }

    // MARK: - Cantos e clique

    @Test("Cantos giram em pixels")
    func cornersRotate() {
        let b = box(0.1, 0.2, w: 0.5, h: 0.4, scale: 2)
        let straight = CanvasLayout.corners(of: b, aspect: aspect)
        #expect(close(straight[0].x, 0.1 - 0.5) && close(straight[0].y, 0.2 + 0.4))
        #expect(close(straight[2].x, 0.1 + 0.5) && close(straight[2].y, 0.2 - 0.4))

        // 90° horário: a largura em pixels vira altura. Normalizado: altura = 2·0,5·aspecto, largura = 2·0,4/aspecto.
        var turned = b
        turned.rotation = 90
        let r = CanvasLayout.bounds(of: turned, aspect: aspect)
        #expect(close(r.width, 0.8 / aspect) && close(r.height, 1.0 * aspect))
        // Horário na tela: o canto superior esquerdo vai para a direita, em cima.
        let tl = CanvasLayout.corners(of: turned, aspect: aspect)[0]
        #expect(tl.x > 0.1 && tl.y > 0.2)
    }

    @Test("Clique acerta o elemento mais acima e respeita a rotação")
    func hitTest() {
        let below = box(0, 0, w: 1, h: 1)
        let above = box(0.2, 0, w: 0.4, h: 0.4)
        let boxes = [below, above]
        #expect(CanvasLayout.hitTest(CGPoint(x: 0.2, y: 0), in: boxes, aspect: aspect) == above.id)
        #expect(CanvasLayout.hitTest(CGPoint(x: -0.3, y: 0), in: boxes, aspect: aspect) == below.id)
        #expect(CanvasLayout.hitTest(CGPoint(x: 0.9, y: 0.9), in: boxes, aspect: aspect) == nil)

        // Quadrado em pixels girado 45°: o canto da caixa reta fica de fora, a ponta do losango dentro.
        let diamond = box(0, 0, w: 0.4 / aspect, h: 0.4, rotation: 45)
        #expect(CanvasLayout.hitTest(CGPoint(x: 0.19 / aspect, y: 0.19), in: [diamond], aspect: aspect) == nil)
        #expect(CanvasLayout.hitTest(CGPoint(x: 0, y: 0.27), in: [diamond], aspect: aspect) == diamond.id)
        // Escala aumenta a área de clique.
        var big = box(0, 0, w: 0.2, h: 0.2)
        #expect(CanvasLayout.hitTest(CGPoint(x: 0.15, y: 0), in: [big], aspect: aspect) == nil)
        big.scale = 2
        #expect(CanvasLayout.hitTest(CGPoint(x: 0.15, y: 0), in: [big], aspect: aspect) == big.id)
    }

    // MARK: - Ímã

    @Test("Encaixa no centro do canvas")
    func snapCenter() {
        let b = box(0, 0)
        let r = Snapping.snapMove(b, to: CGPoint(x: 0.01, y: -0.015), others: [], aspect: aspect,
                                  threshold: CGSize(width: 0.02, height: 0.02))
        #expect(r.center == CGPoint(x: 0, y: 0))
        #expect(Set(r.guides) == [SnapGuide(axis: .vertical, position: 0, kind: .canvasCenter),
                                  SnapGuide(axis: .horizontal, position: 0, kind: .canvasCenter)])
    }

    @Test("Sem alvo por perto, nada muda")
    func snapNothing() {
        let r = Snapping.snapMove(box(0, 0), to: CGPoint(x: 0.3, y: 0.25), others: [], aspect: aspect,
                                  threshold: CGSize(width: 0.02, height: 0.02))
        #expect(r.center == CGPoint(x: 0.3, y: 0.25) && r.guides.isEmpty)
    }

    @Test("Bordas encaixam nas bordas e na margem de segurança")
    func snapEdges() {
        // Caixa de 0,4: a borda esquerda em -0,895 vai para a margem -0,9.
        let r = Snapping.snapMove(box(0, 0), to: CGPoint(x: -0.695, y: 0.5), others: [], aspect: aspect,
                                  threshold: CGSize(width: 0.02, height: 0.02))
        #expect(close(r.center.x, -0.7))
        #expect(r.guides == [SnapGuide(axis: .vertical, position: -0.9, kind: .safeMargin)])

        // Borda de cima em 0,99 vai para a borda do canvas.
        let top = Snapping.snapMove(box(0, 0), to: CGPoint(x: 0.5, y: 0.79), others: [], aspect: aspect,
                                    threshold: CGSize(width: 0.02, height: 0.02))
        #expect(close(top.center.y, 0.8))
        #expect(top.guides == [SnapGuide(axis: .horizontal, position: 1, kind: .canvasEdge)])
    }

    @Test("O alvo mais próximo vence e outros elementos servem de alvo")
    func snapElements() {
        let other = box(0.5, 0.3, w: 0.2, h: 0.2)
        // Centro proposto em x 0,505: o centro do outro (0,5) está mais perto que qualquer borda.
        let r = Snapping.snapMove(box(0, 0, w: 0.3, h: 0.3), to: CGPoint(x: 0.505, y: -0.5), others: [other],
                                  aspect: aspect, threshold: CGSize(width: 0.02, height: 0.02))
        #expect(close(r.center.x, 0.5))
        #expect(r.guides == [SnapGuide(axis: .vertical, position: 0.5, kind: .element)])

        // Topo da caixa (y + 0,15) a 0,005 da base do outro (0,2); o centro está a 0,045 do centro do canvas.
        let e = Snapping.snapMove(box(0, 0, w: 0.3, h: 0.3), to: CGPoint(x: -0.4, y: 0.045), others: [other],
                                  aspect: aspect, threshold: CGSize(width: 0.02, height: 0.02))
        #expect(close(e.center.y, 0.05))
        #expect(e.guides.count == 1 && e.guides[0].axis == .horizontal && close(e.guides[0].position, 0.2) && e.guides[0].kind == .element)

        // O próprio elemento na lista de outros é ignorado.
        let me = box(0.3, 0.3)
        let self_ = Snapping.snapMove(me, to: CGPoint(x: 0.305, y: 0.5), others: [me], aspect: aspect,
                                      threshold: CGSize(width: 0.02, height: 0.02))
        #expect(self_.center.x == 0.305)
    }

    @Test("Elemento girado encaixa pela caixa alinhada aos eixos")
    func snapRotatedBounds() {
        let b = box(0, 0, w: 0.4 / aspect, h: 0.4, rotation: 45)
        // Girado 45°, a meia altura vira 0,2·√2 ≈ 0,283: a ponta de cima encosta em 1 com o centro em ~0,717.
        let r = Snapping.snapMove(b, to: CGPoint(x: 0.3, y: 0.71), others: [], aspect: aspect,
                                  threshold: CGSize(width: 0.02, height: 0.02))
        #expect(close(r.center.y, 1 - 0.2 * 2.squareRoot(), 1e-9))
        #expect(r.guides.contains(SnapGuide(axis: .horizontal, position: 1, kind: .canvasEdge)))
    }

    @Test("Guias iguais na mesma posição viram uma só, a mais forte")
    func snapDeduplicates() {
        let other = box(0, 0.5, w: 0.2, h: 0.2)
        let r = Snapping.snapMove(box(0, 0), to: CGPoint(x: 0.01, y: -0.5), others: [other], aspect: aspect,
                                  threshold: CGSize(width: 0.02, height: 0.02))
        #expect(r.guides.filter { $0.axis == .vertical } == [SnapGuide(axis: .vertical, position: 0, kind: .canvasCenter)])
    }

    @Test("Rotação encaixa em múltiplos de 45°")
    func snapRotation() {
        #expect(Snapping.snapRotation(43) == (45, true))
        #expect(Snapping.snapRotation(40) == (40, false))
        #expect(Snapping.snapRotation(-88.5) == (-90, true))
        #expect(Snapping.snapRotation(181) == (180, true))
        #expect(Snapping.snapRotation(2, threshold: 1) == (2, false))
    }

    // MARK: - Posicionamento

    @Test("setPlacement grava no estilo do texto e no transform do visual")
    func setPlacement() throws {
        var p = Project()
        let photo = TimelineEditor.addMedia(try photo(), to: &p)
        let text = TimelineEditor.addText(TextContent(text: "Oi"), to: &p, at: 0)
        TimelineEditor.setPlacement(&p, segment: text, center: CGPoint(x: 0.1, y: 0.2), scale: 1.5, rotation: 30)
        TimelineEditor.setPlacement(&p, segment: photo, center: CGPoint(x: -0.3, y: 0.4), scale: 0.5, rotation: -10)
        let s = p.segment(text)!
        #expect(s.text!.style.x == 0.1 && s.text!.style.y == 0.2 && s.text!.style.scale == 1.5 && s.text!.style.rotation == 30)
        #expect(s.transform == Transform())
        let t = p.segment(photo)!.transform
        #expect(t.x == -0.3 && t.y == 0.4 && t.scale == 0.5 && t.rotation == -10)

        let box = CanvasLayout.boxes(in: p, at: 0).first { $0.id == text }!
        #expect(box.center == CGPoint(x: 0.1, y: 0.2) && box.scale == 1.5 && box.rotation == 30)
    }
}
