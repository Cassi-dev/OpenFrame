import AVFoundation
import CoreImage
import Testing
@testable import OpenCutCore

@Suite("Renderização")
struct RenderTests {
    let size = CGSize(width: 320, height: 180)

    func render(_ p: Project, at t: Micros) -> Bitmap {
        let plan = RenderPlan(project: p, renderSize: size)
        let image = FrameRenderer().render(plan: plan, time: t) { _ in nil }
        return Bitmap(image, size: size)
    }

    func photo(_ color: CIColor, width: Int = 400, height: Int = 300) throws -> Material {
        let url = try TestMedia.makePNG(width: width, height: height, color: color)
        return Material(kind: .photo, path: url.path, name: url.lastPathComponent, duration: 0,
                        width: width, height: height, hasAudio: false)
    }

    @Test("Fundo colorido do canvas")
    func backgroundColor() {
        var p = Project()
        p.canvas.background = .color(RGBA(1, 0, 0))
        let c = render(p, at: 0).color(0.5, 0.5)
        #expect(c.r > 240 && c.g < 15 && c.b < 15)
    }

    @Test("Foto 4:3 encaixada num canvas 16:9 deixa barras laterais")
    func photoFit() throws {
        var p = Project()
        p.canvas.aspect = .r16x9
        TimelineEditor.addMedia(try photo(CIColor(red: 0, green: 1, blue: 0)), to: &p)
        let bmp = render(p, at: 0)
        #expect(bmp.color(0.5, 0.5).g > 240)
        #expect(bmp.color(0.03, 0.5).g < 15)
    }

    @Test("Escala, posição e opacidade")
    func transformAndOpacity() throws {
        var p = Project()
        p.canvas.aspect = .r16x9
        let id = TimelineEditor.addMedia(try photo(CIColor(red: 1, green: 1, blue: 1), width: 320, height: 180), to: &p)
        TimelineEditor.update(&p, segment: id) {
            $0.transform.scale = 0.5
            $0.transform.x = 0.5 // centro em 75% da largura
            $0.opacity = 0.5
        }
        let bmp = render(p, at: 0)
        let inside = bmp.color(0.75, 0.5)
        #expect(inside.r > 110 && inside.r < 200) // branco a 50% sobre preto
        #expect(bmp.color(0.25, 0.5).r < 10)
    }

    @Test("Temperatura positiva esquenta a imagem")
    func temperature() throws {
        var p = Project()
        let id = TimelineEditor.addMedia(try photo(CIColor(red: 0.5, green: 0.5, blue: 0.5)), to: &p)
        TimelineEditor.update(&p, segment: id) { $0.adjust.temperature = 0.8 }
        let warm = render(p, at: 0).color(0.5, 0.5)
        TimelineEditor.update(&p, segment: id) { $0.adjust.temperature = -0.8 }
        let cool = render(p, at: 0).color(0.5, 0.5)
        #expect(warm.r - warm.b > 20)
        #expect(cool.b - cool.r > 20)
    }

    @Test("Filtro mono remove a cor")
    func monoFilter() throws {
        var p = Project()
        let id = TimelineEditor.addMedia(try photo(CIColor(red: 0.9, green: 0.2, blue: 0.2)), to: &p)
        TimelineEditor.update(&p, segment: id) { $0.filter = FilterSetting(preset: .mono) }
        let c = render(p, at: 0).color(0.5, 0.5)
        #expect(abs(c.r - c.g) < 6 && abs(c.g - c.b) < 6)
    }

    @Test("Glitch RGB preserva as cores onde os canais se sobrepõem")
    func rgbSplitKeepsColor() throws {
        var p = Project()
        let id = TimelineEditor.addMedia(try photo(CIColor(red: 1, green: 1, blue: 1)), to: &p)
        TimelineEditor.update(&p, segment: id) { $0.effects = [VideoEffect(kind: .rgbSplit, intensity: 1)] }
        let c = render(p, at: 0).color(0.5, 0.5)
        #expect(c.r > 240 && c.g > 240 && c.b > 240)
    }

    @Test("Efeitos não mudam o tamanho do clipe nem deixam transparência")
    func effectsKeepExtent() throws {
        var p = Project()
        p.canvas.background = .color(RGBA(1, 0, 1))
        let id = TimelineEditor.addMedia(try photo(CIColor(red: 0.2, green: 0.6, blue: 0.3), width: 320, height: 180), to: &p)
        for kind in VideoEffectKind.allCases where kind != .shake && kind != .zoomPulse {
            TimelineEditor.update(&p, segment: id) { $0.effects = [VideoEffect(kind: kind, intensity: 1)] }
            // O fundo magenta não pode vazar perto das bordas do clipe.
            let edge = render(p, at: 0).color(0.02, 0.5)
            #expect(!(edge.r > 200 && edge.b > 200 && edge.g < 60), "\(kind) deixou o fundo aparecer")
        }
    }

    @Test("Animação de entrada começa invisível")
    func fadeIn() throws {
        var p = Project()
        let id = TimelineEditor.addMedia(try photo(CIColor(red: 1, green: 1, blue: 1)), to: &p)
        TimelineEditor.update(&p, segment: id) { $0.animationIn = SegmentAnimation(kind: .fade, duration: Time.second) }
        #expect(render(p, at: 0).color(0.5, 0.5).r < 10)
        #expect(render(p, at: Time.seconds(1.5)).color(0.5, 0.5).r > 240)
    }

    @Test("Transição dissolver mistura os dois clipes")
    func dissolve() throws {
        var p = Project()
        let a = TimelineEditor.addMedia(try photo(CIColor(red: 1, green: 0, blue: 0)), to: &p)
        TimelineEditor.addMedia(try photo(CIColor(red: 0, green: 0, blue: 1)), to: &p)
        TimelineEditor.update(&p, segment: a) { $0.transition = Transition(kind: .dissolve, duration: Time.second) }
        // Clipe A: 0–3 s; B começa em 2 s; meio da transição = 2,5 s.
        let mid = render(p, at: Time.seconds(2.5)).color(0.5, 0.5)
        #expect(mid.r > 60 && mid.b > 60)
        #expect(render(p, at: Time.seconds(1)).color(0.5, 0.5).b < 10)
        #expect(render(p, at: Time.seconds(4)).color(0.5, 0.5).r < 10)
    }

    @Test("Texto aparece na posição definida")
    func text() {
        var p = Project()
        var style = TextStyle()
        style.y = 0
        style.fontSize = 0.3
        style.shadow = false
        style.backgroundEnabled = true
        style.backgroundColor = RGBA(1, 1, 0)
        TimelineEditor.addText(TextContent(text: "OPEN", style: style), to: &p, at: 0)
        let bmp = render(p, at: 0)
        let yellowish = (0..<10).contains { i in
            let c = bmp.color(0.3 + Double(i) * 0.04, 0.5)
            return c.r > 200 && c.g > 200 && c.b < 60
        }
        #expect(yellowish)
        #expect(bmp.color(0.02, 0.95).r < 10)
        // Fora do intervalo do segmento, nada é desenhado.
        #expect(render(p, at: Time.seconds(5)).color(0.5, 0.5).r < 10)
    }

    @Test("Vídeo gravado em pé é exibido na orientação correta")
    func rotatedVideo() async throws {
        let url = try await TestMedia.makeVideo(width: 320, height: 180, seconds: 1, audio: false,
                                                transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0))
        let m = try await MediaProbe.probe(url)
        #expect(m.width == 180 && m.height == 320)

        var p = Project()
        TimelineEditor.addMedia(m, to: &p)
        let renderSize = p.canvasSize(shortSide: 180)
        #expect(renderSize == CGSize(width: 180, height: 320))
        let built = try await CompositionBuilder.build(project: p, renderSize: renderSize,
                                                       frameDuration: CMTime(value: 1, timescale: 30))
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (cg, _) = try await generator.image(at: CMTime(value: 1, timescale: 2))
        let bmp = Bitmap(CIImage(cgImage: cg), size: renderSize)
        // O topo do quadro original (vermelho) vai para a direita ao girar 90° no sentido horário.
        let right = bmp.color(0.8, 0.3)
        let left = bmp.color(0.2, 0.3)
        #expect(right.r > 150 && right.b < 100)
        #expect(left.b > 150 && left.r < 100)
    }
}
