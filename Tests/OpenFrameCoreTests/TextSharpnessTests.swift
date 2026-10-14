import CoreImage
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Nitidez do texto ampliado")
struct TextSharpnessTests {
    let size = CGSize(width: 1280, height: 720)

    func project(scale: Double, _ change: (inout Segment) -> Void = { _ in }) -> Project {
        var p = Project()
        p.canvas.aspect = .r16x9
        var style = TextStyle()
        style.shadow = false
        style.fontSize = 0.05
        style.y = 0
        style.scale = scale
        let id = TimelineEditor.addText(TextContent(text: "IHIH", style: style), to: &p, at: 0, duration: 3_000_000)
        TimelineEditor.update(&p, segment: id, change)
        return p
    }

    /// Maior transição de borda (pixels entre 10% e 90% do branco) na linha com mais tinta.
    func widestEdge(_ p: Project, at t: Micros) -> Int {
        let bmp = Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: t) { _ in nil }, size: size)
        func value(_ x: Int, _ y: Int) -> Int { Int(bmp.data[(y * bmp.width + x) * 4]) }
        let row = (0..<bmp.height).max { a, b in
            (0..<bmp.width).filter { value($0, a) > 245 }.count < (0..<bmp.width).filter { value($0, b) > 245 }.count
        }!
        var widest = 0, run = 0
        for x in 0..<bmp.width {
            let v = value(x, row)
            if v > 25, v < 230 { run += 1; widest = max(widest, run) } else { run = 0 }
        }
        return widest
    }

    @Test("Texto com escala 3 tem borda nítida")
    func scaledTextIsSharp() {
        #expect(widestEdge(project(scale: 3), at: 1_000_000) <= 2)
    }

    @Test("Elástico no meio da animação, com escala 3, também")
    func elasticIsSharp() {
        let p = project(scale: 3) { $0.animationIn = SegmentAnimation(kind: .elastic, duration: 1_000_000) }
        #expect(widestEdge(p, at: 800_000) <= 2)
    }

    /// Caixa (minX, minY, maxX, maxY) dos pixels com vermelho acima de 128, com y para cima.
    func inkBounds(_ bmp: Bitmap) -> (Int, Int, Int, Int) {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<bmp.height {
            for x in 0..<bmp.width where bmp.data[(y * bmp.width + x) * 4] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, bmp.height - 1 - y); maxY = max(maxY, bmp.height - 1 - y)
            }
        }
        return (minX, minY, maxX, maxY)
    }

    @Test("Ampliado, o fundo do texto continua batendo com a caixa do CanvasLayout", arguments: [1.0, 2.5, 3.0])
    func boxUnchanged(scale: Double) throws {
        var p = project(scale: scale) {
            $0.text!.style.backgroundEnabled = true
            $0.text!.style.backgroundColor = RGBA(1, 1, 1)
            $0.text!.style.x = 0.1
            $0.text!.style.y = -0.2
        }
        p.canvas.background = .black
        let box = try #require(CanvasLayout.boxes(in: p, at: 0).first)
        let corners = CanvasLayout.corners(of: box, aspect: 16.0 / 9)
        let bmp = Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: 0) { _ in nil }, size: size)
        let (minX, minY, maxX, maxY) = inkBounds(bmp)
        func px(_ v: CGFloat, _ side: CGFloat) -> Double { Double((v + 1) / 2 * side) }
        #expect(abs(Double(minX) - px(corners[0].x, size.width)) < 3)
        #expect(abs(Double(maxX + 1) - px(corners[2].x, size.width)) < 3)
        #expect(abs(Double(maxY + 1) - px(corners[0].y, size.height)) < 3)
        #expect(abs(Double(minY) - px(corners[2].y, size.height)) < 3)
    }

    @Test("Sombra, contorno, fundo e reflexo mantêm o tamanho visual na escala 2")
    func effectsKeepVisualSize() {
        // Escala 2 com fonte f desenha igual a escala 1 com fonte 2f (e largura máxima dobrada):
        // as medidas em em e em fração da caixa acompanham a rasterização maior.
        func styled(scale: Double, font: Double, maxWidth: Double) -> Project {
            project(scale: scale) {
                $0.text!.text = "Brilho\nsombra"
                $0.text!.style.fontSize = font
                $0.text!.style.maxWidth = maxWidth
                $0.text!.style.shadow = true
                $0.text!.style.strokeWidth = 12
                $0.text!.style.underline = true
                $0.text!.style.backgroundEnabled = true
                $0.text!.style.color = RGBA(0.9, 0.4, 0.2)
                $0.animationLoop = LoopAnimation(kind: .shine, intensity: 1)
            }
        }
        let a = styled(scale: 2, font: 0.05, maxWidth: 0.9)
        let b = styled(scale: 1, font: 0.1, maxWidth: 1.8)
        for t: Micros in [600_000, 1_800_000] {
            let ba = Bitmap(FrameRenderer().render(plan: RenderPlan(project: a, renderSize: size), time: t) { _ in nil }, size: size)
            let bb = Bitmap(FrameRenderer().render(plan: RenderPlan(project: b, renderSize: size), time: t) { _ in nil }, size: size)
            #expect(zip(ba.data, bb.data).map { abs(Int($0) - Int($1)) }.max()! <= 3, "t = \(t)")
        }
    }

    @Test("Escala de raster: passos de 1/8 para cima, mínimo 1 e limite de 8192 px")
    func rasterScaleRules() throws {
        var style = TextStyle()
        let canvas = CGSize(width: 1920, height: 1080)
        func r(_ scale: Double, peak: Double = 1, text: String = "Oi") -> CGFloat {
            style.scale = scale
            return TextRenderer.shared.rasterScale(for: TextContent(text: text, style: style), canvas: canvas, peak: peak)
        }
        #expect(r(1) == 1 && r(0.4) == 1)
        #expect(r(2.01) == 2.125 && r(2) == 2)
        #expect(r(2, peak: 1.15) == 2.375) // elástico
        #expect(Animations.peakScale(for: Segment.text(TextContent(text: "a"), at: 0, duration: 1)) == 1)
        let long = String(repeating: "Texto comprido ", count: 4)
        style.scale = 50
        let size = try #require(TextRenderer.shared.imageSize(for: TextContent(text: long, style: style), canvas: canvas))
        let big = r(50, text: long)
        #expect(big < 50 && max(size.width, size.height) * big <= 8192.5)
    }

    @Test("Desempenho ao arrastar a escala (cache por passos de 1/8)")
    func dragPerformance() {
        let hd = CGSize(width: 1920, height: 1080)
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
        var report: [String] = []
        for kind in [nil, AnimationKind.cascade] {
            var p = project(scale: 1) { $0.text!.text = "Quarenta letras animadas em cascata aqui" }
            let id = p.tracks.flatMap(\.segments).first { $0.text != nil }!.id
            if let kind { TimelineEditor.update(&p, segment: id) { $0.animationIn = SegmentAnimation(kind: kind, duration: 500_000) } }
            var times: [Double] = []
            // Arraste de 1× a 3× em 60 quadros, parado no repouso (depois da entrada).
            for i in 0...60 {
                TimelineEditor.update(&p, segment: id) { $0.text!.style.scale = 1 + 2 * Double(i) / 60 }
                let start = Date()
                let img = FrameRenderer.shared.render(plan: RenderPlan(project: p, renderSize: hd), time: 1_000_000) { _ in nil }
                context.render(img, toBitmap: &bytes, rowBytes: 1920 * 4, bounds: CGRect(origin: .zero, size: hd),
                               format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                times.append(Date().timeIntervalSince(start))
            }
            let average = times.reduce(0, +) / Double(times.count)
            report.append("\(kind?.rawValue ?? "estático"): média \(String(format: "%.1f", average * 1000)) ms, primeiro \(String(format: "%.1f", times[0] * 1000)) ms, pior dos demais \(String(format: "%.1f", times.dropFirst().max()! * 1000)) ms")
            #expect(average < 0.1)
        }
        print("ARRASTE DE ESCALA 1080p: " + report.joined(separator: "; "))
    }
}
