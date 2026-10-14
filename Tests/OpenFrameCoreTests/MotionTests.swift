import CoreImage
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Animações de motion")
struct MotionTests {
    static let newKinds: [AnimationKind] = [.focus, .cascade, .elastic, .wave, .wordByWord, .maskReveal, .tracking, .decode]
    let size = CGSize(width: 480, height: 270)

    func textProject(_ change: (inout Segment) -> Void = { _ in }) -> (Project, UUID) {
        var p = Project()
        p.canvas.aspect = .r16x9
        var style = TextStyle()
        style.y = 0
        style.fontSize = 0.15
        let id = TimelineEditor.addText(TextContent(text: "Motion 42", style: style), to: &p, at: 0, duration: 3_000_000)
        TimelineEditor.update(&p, segment: id, change)
        return (p, id)
    }

    func render(_ p: Project, at t: Micros) -> Bitmap {
        Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: t) { _ in nil }, size: size)
    }

    /// Soma do brilho (canal vermelho) de todos os pixels.
    func ink(_ b: Bitmap) -> Int {
        stride(from: 0, to: b.data.count, by: 4).reduce(0) { $0 + Int(b.data[$1]) }
    }

    func maxDifference(_ a: Bitmap, _ b: Bitmap) -> Int {
        zip(a.data, b.data).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    func difference(_ a: Bitmap, _ b: Bitmap) -> Int {
        zip(a.data, b.data).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }

    // MARK: - Modelo

    @Test("Tipos novos: nomes, só texto e Codable")
    func newKindsModel() throws {
        #expect(AnimationKind.focus.displayName == "Foco" && !AnimationKind.focus.textOnly)
        for kind in Self.newKinds where kind != .focus { #expect(kind.textOnly) }
        #expect(AnimationKind.decode.displayName == "Decodificar")
        #expect(LoopKind.allCases.map(\.displayName) == ["Flutuar", "Pulsar", "Respirar brilho", "Reflexo de luz"])

        var (p, id) = textProject {
            $0.animationIn = SegmentAnimation(kind: .maskReveal, duration: 700_000)
            $0.animationOut = SegmentAnimation(kind: .decode)
            $0.animationLoop = LoopAnimation(kind: .shine, period: 1_500_000, intensity: 0.8)
        }
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        #expect(back == p)
        #expect(back.segment(id)!.animationLoop == LoopAnimation(kind: .shine, period: 1_500_000, intensity: 0.8))

        // Sem loop, a chave não é gravada.
        TimelineEditor.update(&p, segment: id) { $0.animationLoop = nil }
        let plain = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(!plain.contains("animationLoop"))
    }

    @Test("Projeto antigo sem animationLoop abre")
    func oldProjectOpens() throws {
        let (p, id) = textProject { $0.animationIn = SegmentAnimation(kind: .fade) }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        #expect(!String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self).contains("animationLoop"))
        json["formatVersion"] = 1
        let reopened = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(reopened.segment(id)!.animationLoop == nil)
        #expect(reopened.segment(id)!.animationIn == SegmentAnimation(kind: .fade))
    }

    @Test("Dividir mantém o loop nas duas metades")
    func splitKeepsLoop() {
        var (p, id) = textProject {
            $0.animationIn = SegmentAnimation(kind: .cascade)
            $0.animationOut = SegmentAnimation(kind: .wave)
            $0.animationLoop = LoopAnimation(kind: .float)
        }
        let right = TimelineEditor.split(&p, segment: id, at: 1_500_000)!
        let l = p.segment(id)!, r = p.segment(right)!
        #expect(l.animationLoop?.kind == .float && r.animationLoop?.kind == .float)
        #expect(l.animationIn != nil && l.animationOut == nil && r.animationIn == nil && r.animationOut != nil)
    }

    // MARK: - Render

    @Test("Cada tipo novo começa invisível, termina no repouso e não pula", arguments: newKinds)
    func entryEndsAtRest(kind: AnimationKind) {
        let (p, _) = textProject { $0.animationIn = SegmentAnimation(kind: kind, duration: 500_000) }
        let middle = render(p, at: 1_500_000)
        #expect(ink(render(p, at: 0)) < ink(middle) / 20)
        // Sem pulo: o quadro logo depois da entrada é igual ao do meio do clipe.
        #expect(difference(render(p, at: 500_000), middle) == 0)
        // Vai se aproximando do repouso.
        #expect(difference(render(p, at: 450_000), middle) < difference(render(p, at: 250_000), middle))
    }

    @Test("Cada tipo novo sai até sumir", arguments: newKinds)
    func exitDisappears(kind: AnimationKind) {
        let (p, _) = textProject { $0.animationOut = SegmentAnimation(kind: kind, duration: 500_000) }
        let middle = render(p, at: 1_500_000)
        #expect(difference(render(p, at: 2_500_000), middle) == 0)
        #expect(ink(render(p, at: 2_999_999)) < ink(middle) / 20)
        #expect(difference(render(p, at: 2_750_000), middle) > 0)
    }

    @Test("Em repouso, o caminho por unidade desenha como o estático")
    func unitRestMatchesStatic() {
        func styled(_ change: (inout Segment) -> Void) -> Project {
            textProject {
                $0.text!.text = "Motion\ndesign 42"
                $0.text!.style.strokeWidth = 10
                $0.text!.style.underline = true
                $0.text!.style.backgroundEnabled = true
                $0.text!.style.opacity = 0.8
                change(&$0)
            }.0
        }
        let still = render(styled { _ in }, at: 1_500_000)
        for g in [AnimationKind.cascade, .wordByWord, .maskReveal] {
            let unit = render(styled { $0.animationIn = SegmentAnimation(kind: g) }, at: 1_500_000)
            #expect(maxDifference(still, unit) <= 8, "granularidade de \(g)")
        }
    }

    @Test("Decodificar é determinístico e troca os caracteres com o tempo")
    func decodeDeterministic() {
        let (p, _) = textProject { $0.animationIn = SegmentAnimation(kind: .decode, duration: 1_000_000) }
        #expect(difference(render(p, at: 400_000), render(p, at: 400_000)) == 0)
        #expect(difference(render(p, at: 400_000), render(p, at: 460_000)) > 0)
        #expect(TextMotion.scrambleIndex(index: 3, step: 7, count: 42) == TextMotion.scrambleIndex(index: 3, step: 7, count: 42))
        let picks = Set((0..<40).map { TextMotion.scrambleIndex(index: $0, step: 1, count: 42) })
        #expect(picks.count > 15)
    }

    @Test("Revelar por máscara não desenha fora da faixa da linha")
    func maskRevealStaysInBand() throws {
        var style = TextStyle()
        style.shadow = false
        style.fontSize = 0.15
        let content = TextContent(text: "Linha um\nLinha dois", style: style)
        let canvas = CGSize(width: 960, height: 540)
        let set = try #require(TextRenderer.shared.units(for: content, canvas: canvas, granularity: .line))
        #expect(set.units.count == 2 && set.lineBands.count == 2)
        for progress in [0.2, 0.5, 0.8] {
            var state = AnimationState()
            state.unit = UnitAnimation(kind: .maskReveal, progress: progress, exiting: false)
            let r = try #require(TextMotion.image(content, canvas: canvas, state: state, granularity: .line))
            let rect = CGRect(origin: .zero, size: r.size)
            let bmp = Bitmap(r.image.cropped(to: rect), size: r.size)
            var outside = 0, inside = 0
            for y in 0..<bmp.height {
                let cy = CGFloat(bmp.height - 1 - y) + 0.5 // linha 0 do bitmap = topo
                let inBand = set.lineBands.contains { cy >= $0.minY - 1 && cy <= $0.maxY + 1 }
                for x in 0..<bmp.width where bmp.data[(y * bmp.width + x) * 4] > 8 {
                    if inBand { inside += 1 } else { outside += 1 }
                }
            }
            #expect(outside == 0 && inside > 0, "progresso \(progress)")
        }
    }

    @Test("Máquina de escrever continua revelando no caminho por unidade")
    func typewriterInUnitPath() {
        let (p, _) = textProject {
            $0.animationIn = SegmentAnimation(kind: .typewriter, duration: 1_000_000)
            $0.animationOut = SegmentAnimation(kind: .cascade)
        }
        let inks = [100_000, 400_000, 700_000, 1_500_000].map { ink(render(p, at: Micros($0))) }
        #expect(inks == inks.sorted() && inks[0] < inks[3] / 2)
    }

    @Test("Foco desfoca a foto no começo")
    func focusBlursPhoto() throws {
        var p = Project()
        p.canvas.aspect = .r16x9
        let url = try TestMedia.makePNG(width: 200, height: 200, color: CIColor(red: 1, green: 1, blue: 1))
        let m = Material(kind: .photo, path: url.path, name: "f", duration: 0, width: 200, height: 200, hasAudio: false)
        let id = TimelineEditor.addMedia(m, to: &p)
        TimelineEditor.update(&p, segment: id) {
            $0.transform.scale = 0.5
            $0.animationIn = SegmentAnimation(kind: .focus, duration: 500_000)
        }
        let st = Animations.state(for: p.segment(id)!, local: 0)
        #expect(st.blur > 0.019 && st.alpha == 0 && st.scale > 1.07)
        #expect(Animations.state(for: p.segment(id)!, local: 500_000).blur == 0)

        /// Pixels de transição (nem fundo nem foto) na linha do meio.
        func soft(_ b: Bitmap) -> Int {
            let row = b.height / 2
            let values = (0..<b.width).map { Int(b.data[(row * b.width + $0) * 4]) }
            let top = values.max()!
            return values.filter { $0 > top / 10 && $0 < top * 9 / 10 }.count
        }
        #expect(soft(render(p, at: 60_000)) > soft(render(p, at: 1_000_000)) + 6)
    }

    @Test("Loops mexem na imagem ao longo do tempo", arguments: LoopKind.allCases)
    func loopsChange(kind: LoopKind) {
        // Texto colorido: o reflexo é branco e só aparece sobre o que não é branco.
        let (p, _) = textProject {
            $0.text!.style.color = RGBA(0.9, 0.3, 0.2)
            $0.animationLoop = LoopAnimation(kind: kind, intensity: 1)
        }
        // Um quarto de ciclo depois do início: seno no máximo e faixa de luz no meio do texto.
        #expect(difference(render(p, at: 0), render(p, at: 500_000)) > size.area / 20)
    }

    @Test("Loop numa foto também")
    func loopOnPhoto() throws {
        var p = Project()
        p.canvas.aspect = .r16x9
        let url = try TestMedia.makePNG(width: 200, height: 200, color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
        let m = Material(kind: .photo, path: url.path, name: "f", duration: 0, width: 200, height: 200, hasAudio: false)
        let id = TimelineEditor.addMedia(m, to: &p)
        for kind in LoopKind.allCases {
            TimelineEditor.update(&p, segment: id) {
                $0.transform.scale = 0.5
                $0.animationLoop = LoopAnimation(kind: kind, intensity: 1)
            }
            #expect(difference(render(p, at: 0), render(p, at: 500_000)) > 0, "\(kind)")
        }
    }

    @Test("Desempenho: 40 letras em 1080p")
    func performance() {
        var p = Project()
        p.canvas.aspect = .r16x9
        let text = "Quarenta letras animadas em cascata aqui"
        let id = TimelineEditor.addText(TextContent(text: text), to: &p, at: 0, duration: 3_000_000)
        let size = CGSize(width: 1920, height: 1080)
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
        func frame(_ t: Micros, _ project: Project) {
            let img = FrameRenderer.shared.render(plan: RenderPlan(project: project, renderSize: size), time: t) { _ in nil }
            context.render(img, toBitmap: &bytes, rowBytes: 1920 * 4, bounds: CGRect(origin: .zero, size: size),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        var report: [String] = []
        for kind in [AnimationKind.cascade, .elastic, .decode, .maskReveal] {
            var q = p
            TimelineEditor.update(&q, segment: id) {
                $0.animationIn = SegmentAnimation(kind: kind, duration: 1_000_000)
                $0.animationLoop = LoopAnimation(kind: .shine)
            }
            let first = Date()
            frame(0, q) // monta os sprites
            let build = Date().timeIntervalSince(first)
            let start = Date()
            let frames = 30
            for i in 0..<frames { frame(Micros(i) * 33_333, q) }
            let perFrame = Date().timeIntervalSince(start) / Double(frames)
            report.append("\(kind.rawValue): \(Int(build * 1000)) ms de montagem, \(String(format: "%.1f", perFrame * 1000)) ms/quadro")
            // Folga para a máquina ocupada com os outros testes em paralelo.
            #expect(perFrame < 0.1)
        }
        print("DESEMPENHO 1080p, \(text.count) letras: " + report.joined(separator: "; "))
    }

    @Test("Prévia devolve quadros diferentes, com fundo transparente")
    func previewFrames() throws {
        let content = TextContent(text: "Prévia", style: TextStyle())
        let frames = AnimationPreview.frames(subject: .text(content), part: .entry(.zoomIn), size: CGSize(width: 160, height: 90), count: 12)
        #expect(frames.count == 12)
        #expect(frames.allSatisfy { $0.width == 160 && $0.height == 90 })
        #expect(Set(frames.map(bytes)).count > 6)
        // Canto sem nada: transparente.
        #expect(bytes(frames.last!)[3] == 0)
        // Na entrada, o último quadro já está em repouso e o texto ocupa boa parte da largura.
        let alphaColumns = columnsWithInk(frames.last!)
        #expect(alphaColumns > 160 / 2)

        let cascade = AnimationPreview.frames(subject: .text(content), part: .entry(.cascade), size: CGSize(width: 160, height: 90), count: 12)
        #expect(cascade.count == 12 && Set(cascade.map(bytes)).count > 6)
        let exit = AnimationPreview.frames(subject: .text(content), part: .exit(.fade), size: CGSize(width: 160, height: 90), count: 8)
        #expect(exit.count == 8 && bytes(exit[0]) != bytes(exit[7]))
        // 5 quadros por ciclo: fases que não se repetem dentro do ciclo (com 4, o seno só vale 0, 1, 0 e -1).
        let loop = AnimationPreview.frames(subject: .text(content), part: .loop(.float), size: CGSize(width: 160, height: 90), count: 10)
        #expect(loop.count == 10 && Set(loop.map(bytes)).count >= 5)

        // Imagem: encaixada e animada.
        let cg = CIContext().createCGImage(CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)),
                                           from: CGRect(x: 0, y: 0, width: 64, height: 64))!
        let image = AnimationPreview.frames(subject: .image(cg), part: .entry(.slideLeft), size: CGSize(width: 160, height: 90), count: 10)
        #expect(image.count == 10 && Set(image.map(bytes)).count > 5)
        let last = bytes(image.last!)
        let center = (45 * 160 + 80) * 4
        #expect(last[center + 1] > 240 && last[center + 3] == 255)
        #expect(last[3] == 0) // canto: fora da foto quadrada
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func columnsWithInk(_ image: CGImage) -> Int {
        let data = bytes(image)
        return (0..<image.width).filter { x in
            (0..<image.height).contains { y in data[(y * image.width + x) * 4 + 3] > 128 }
        }.count
    }
}

private extension CGSize {
    var area: Int { Int(width * height) }
}
