import CoreImage
import CoreText
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Legendas: revelação pela fala")
struct CaptionRevealTests {
    let size = CGSize(width: 640, height: 360)
    static let accent = RGBA(0, 0.4, 1)

    /// "MAR SOL CEU": palavras de 0,9 s a cada 1 s, a partir de 0; o segmento dura 3,4 s.
    func project(text: String = "MAR SOL CEU", reveal: WordReveal, _ change: (inout WordHighlight) -> Void = { _ in },
                 highlight: Bool = true) -> Project {
        var p = Project()
        p.canvas.aspect = .r16x9
        var style = TextStyle()
        style.y = 0
        style.fontSize = 0.16
        style.shadow = false
        var content = TextContent(text: text, style: style)
        content.words = (0..<3).map { CaptionWord(text: "w\($0)", start: Micros($0) * 1_000_000, end: Micros($0 + 1) * 1_000_000 - 100_000) }
        if highlight {
            var h = WordHighlight()
            h.color = Self.accent
            h.scale = 1
            h.reveal = reveal
            change(&h)
            content.highlight = h
        }
        TimelineEditor.addText(content, to: &p, at: 0, duration: 3_400_000)
        return p
    }

    func render(_ p: Project, at t: Micros) -> Bitmap {
        Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: t) { _ in nil }, size: size)
    }

    /// Colunas com tinta de cada palavra (pelo desenho estático, todas visíveis).
    func wordSpans() -> [ClosedRange<Int>] {
        let b = render(project(reveal: .none, highlight: false), at: 1_500_000)
        let ink = (0..<b.width).map { x in (0..<b.height).contains { y in b.data[(y * b.width + x) * 4] > 60 } }
        var spans: [ClosedRange<Int>] = []
        var start: Int?
        var gap = 0
        for x in 0..<b.width {
            if ink[x] {
                if start == nil { start = x }
                gap = 0
            } else if let s = start {
                gap += 1
                if gap > 8 {
                    spans.append(s...(x - gap))
                    start = nil
                }
            }
        }
        return spans
    }

    func count(_ b: Bitmap, in span: ClosedRange<Int>, _ test: (Int, Int, Int) -> Bool) -> Int {
        var n = 0
        for y in 0..<b.height {
            for x in span {
                let i = (y * b.width + x) * 4
                if test(Int(b.data[i]), Int(b.data[i + 1]), Int(b.data[i + 2])) { n += 1 }
            }
        }
        return n
    }

    /// Soma do brilho no trecho.
    func light(_ b: Bitmap, in span: ClosedRange<Int>) -> Int {
        var sum = 0
        for y in 0..<b.height { for x in span { let i = (y * b.width + x) * 4; sum += max(Int(b.data[i]), Int(b.data[i + 1]), Int(b.data[i + 2])) } }
        return sum
    }

    func maxDiff(_ a: Bitmap, _ b: Bitmap, in span: ClosedRange<Int>) -> Int {
        var worst = 0
        for y in 0..<a.height {
            for x in span {
                let i = (y * a.width + x) * 4
                for c in 0..<3 { worst = max(worst, abs(Int(a.data[i + c]) - Int(b.data[i + c]))) }
            }
        }
        return worst
    }

    let ink = { (r: Int, g: Int, b: Int) in max(r, g, b) > 40 }
    let blue = { (r: Int, g: Int, b: Int) in b > 150 && r < 90 }
    let white = { (r: Int, g: Int, b: Int) in r > 200 && g > 200 && b > 200 }

    @Test("Surgir: a palavra não aparece antes de ser dita; ~300 ms depois, igual ao estático")
    func rise() {
        let spans = wordSpans()
        #expect(spans.count == 3)
        let p = project(reveal: .rise)
        let before = render(p, at: 950_000)
        #expect(count(before, in: spans[0], ink) > 300)
        #expect(count(before, in: spans[1], ink) == 0)
        #expect(count(before, in: spans[2], ink) == 0)
        // No meio da entrada, a palavra está aparecendo (menos luz que no fim).
        let settled = render(p, at: 1_300_000)
        let mid = light(render(p, at: 1_010_000), in: spans[1])
        #expect(mid > 0 && Double(mid) < 0.9 * Double(light(settled, in: spans[1])))
        // Sem pulo: depois da entrada, igual ao destaque sem revelação (a terceira ainda não foi dita).
        let still = render(project(reveal: .none), at: 1_300_000)
        for span in spans.prefix(2) { #expect(maxDiff(settled, still, in: span) <= 3) }
    }

    @Test("Leitura guiada: as não ditas com a opacidade escolhida; a dita acende")
    func dim() {
        let spans = wordSpans()
        let dimmed = render(project(reveal: .dim) { $0.color = .white }, at: 500_000)
        func brightest(_ span: ClosedRange<Int>, _ b: Bitmap? = nil) -> Double {
            let b = b ?? dimmed
            var m = 0
            for y in 0..<b.height { for x in span { m = max(m, Int(b.data[(y * b.width + x) * 4])) } }
            // O texto branco sobre o preto, com alfa a, sai com a luz linear a.
            let v = Double(m) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        #expect(brightest(spans[0]) > 0.97)
        #expect(abs(brightest(spans[2]) - 0.35) < 0.05, "\(brightest(spans[2]))")
        #expect(abs(brightest(spans[1]) - 0.35) < 0.05)
        let half = render(project(reveal: .dim) { $0.dimOpacity = 0.6; $0.color = .white }, at: 500_000)
        #expect(abs(brightest(spans[2], half) - 0.6) < 0.05)
    }

    @Test("Preenchimento: no meio da palavra, a metade esquerda na cor e a direita não")
    func fill() {
        let spans = wordSpans()
        let p = project(reveal: .fill)
        let b = render(p, at: 1_450_000)
        let sol = spans[1]
        let left = sol.lowerBound...(sol.lowerBound + sol.count / 3)
        let right = (sol.upperBound - sol.count / 3)...sol.upperBound
        #expect(count(b, in: left, blue) > 100)
        #expect(count(b, in: left, white) < 20)
        #expect(count(b, in: right, blue) == 0)
        #expect(count(b, in: right, white) > 100)
        // A já dita fica cheia; a futura, sem cor.
        #expect(count(b, in: spans[0], white) < 20 && count(b, in: spans[0], blue) > 200)
        #expect(count(b, in: spans[2], blue) == 0)
        // Antes de começar, sem cor nenhuma; depois do fim, cheia.
        #expect(count(render(p, at: 950_000), in: sol, blue) == 0)
        #expect(count(render(p, at: 1_950_000), in: sol, white) < 20)
    }

    @Test("Digitação: as letras aparecem em ordem e no fim da legenda não há cursor")
    func typing() {
        let spans = wordSpans()
        let p = project(reveal: .type)
        // SOL: S em 1,0 s, O em 1,3 s e L em 1,6 s.
        func rightmostInk(_ t: Micros) -> Int {
            let b = render(p, at: t)
            return spans[1].last { x in (0..<b.height).contains { y in white(Int(b.data[(y * b.width + x) * 4]), Int(b.data[(y * b.width + x) * 4 + 1]), Int(b.data[(y * b.width + x) * 4 + 2])) } } ?? 0
        }
        let s = rightmostInk(1_050_000)
        let so = rightmostInk(1_350_000)
        let sol = rightmostInk(1_650_000)
        #expect(s > 0 && s < so && so < sol, "\(s) \(so) \(sol)")
        #expect(count(render(p, at: 950_000), in: spans[1], white) == 0)
        #expect(count(render(p, at: 950_000), in: spans[2], white) == 0)
        // Cursor na cor do destaque enquanto digita; a palavra não é tingida.
        let typingNow = render(p, at: 1_350_000)
        #expect(count(typingNow, in: spans[1], blue) > 10)
        #expect(count(typingNow, in: spans[0], blue) == 0)
        // No fim da legenda, tudo digitado e sem cursor.
        let end = render(p, at: 3_350_000)
        #expect(count(end, in: 0...(size.width.toInt - 1), blue) == 0)
        for span in spans { #expect(count(end, in: span, white) > 200) }
    }

    @Test("Digitação: o fundo cresce com o texto digitado, sem pulo, e termina igual ao estático")
    func typingBackground() {
        let spans = wordSpans()
        func boxed(_ reveal: WordReveal, highlight: Bool = true) -> Project {
            var p = project(reveal: reveal, highlight: highlight)
            let t = p.tracks.firstIndex { $0.kind == .text }!
            p.tracks[t].segments[0].text!.style.backgroundEnabled = true
            p.tracks[t].segments[0].text!.style.backgroundColor = RGBA(1, 0, 0)
            p.tracks[t].segments[0].text!.style.backgroundPaddingX = 0.3
            return p
        }
        let p = boxed(.type)
        let red = { (r: Int, g: Int, b: Int) in r > 200 && g < 60 && b < 60 }
        func last(_ b: Bitmap, _ test: (Int, Int, Int) -> Bool) -> Int {
            (0..<b.width).last { x in count(b, in: x...x, test) > 0 } ?? -1
        }
        func rightEdge(_ t: Micros) -> Int { last(render(p, at: t), red) }
        // Digitando SOL (S e O já apareceram): o fundo cobre MAR e o começo de SOL, mas não chega ao CEU.
        let mid = render(p, at: 1_400_000)
        #expect(count(mid, in: spans[0], red) > 300)
        #expect(count(mid, in: spans[1].lowerBound...(spans[1].lowerBound + spans[1].count / 3), red) > 100)
        #expect(count(mid, in: spans[2], red) == 0)
        // A borda direita só avança e passa por posições intermediárias em volta de cada letra (O em 1,3 s).
        let times = Array(stride(from: Micros(1_200_000), through: 1_500_000, by: 16_667))
        let edges = times.map(rightEdge)
        #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 <= $1 }, "\(edges)")
        let before = rightEdge(1_200_000)
        let after = rightEdge(1_500_000)
        #expect(after - before > 10, "\(before) \(after)")
        #expect(edges.filter { $0 > before && $0 < after }.count >= 2, "\(before) \(edges) \(after)")
        // O cursor (na cor do destaque) fica sempre dentro do fundo.
        for t in Array(stride(from: Micros(0), through: 2_700_000, by: 33_333)) {
            let b = render(p, at: t)
            #expect(last(b, blue) < last(b, red) - 2, "\(t): \(last(b, blue)) \(last(b, red))")
        }
        // As letras já digitadas não se mexem: MAR igual ao do fim.
        let end = render(p, at: 3_350_000)
        #expect(maxDiff(mid, end, in: spans[0]) <= 3)
        // No fim, o fundo é o da imagem estática.
        #expect(maxDiff(end, render(boxed(.none, highlight: false), at: 3_350_000), in: 0...(end.width - 1)) <= 3)
    }

    @Test("Texto editado (a contagem não bate): tudo visível, sem revelação", arguments: WordReveal.allCases)
    func edited(reveal: WordReveal) {
        let p = project(text: "MAR SOL CEU AZUL", reveal: reveal)
        let plain = project(text: "MAR SOL CEU AZUL", reveal: .none, highlight: false)
        let a = render(p, at: 100_000)
        let b = render(plain, at: 100_000)
        #expect(maxDiff(a, b, in: 0...(a.width - 1)) <= 3)
    }

    @Test("A revelação some sem destaque e convive com a pílula")
    func pillTogether() {
        let spans = wordSpans()
        let b = render(project(reveal: .rise) { $0.backgroundEnabled = true; $0.backgroundColor = RGBA(1, 0, 0) }, at: 500_000)
        #expect(count(b, in: spans[0], { r, g, b in r > 200 && g < 60 && b < 60 }) > 100)
        #expect(count(b, in: spans[2], ink) == 0)
    }
}

private extension CGFloat {
    var toInt: Int { Int(self) }
}

@Suite("Legendas: palavra-chave e linhas ajustadas")
struct CaptionEmphasisTests {
    let canvas = CGSize(width: 1280, height: 720)

    @Test("A palavra enfatizada é mais larga e sai na cor; índices inválidos não quebram")
    func emphasis() throws {
        var style = TextStyle()
        style.fontSize = 0.08
        style.shadow = false
        style.y = 0
        let plain = TextContent(text: "um teste bonito", style: style)
        var marked = plain
        var e = WordEmphasis(words: [2])
        e.color = RGBA(1, 0, 0)
        marked.emphasis = e
        let r = TextRenderer.shared
        let a = try #require(r.boxSize(for: plain, canvas: canvas))
        let b = try #require(r.boxSize(for: marked, canvas: canvas))
        #expect(b.width > a.width + 10)
        // A palavra em si: a mesma palavra sozinha, com e sem ênfase.
        var alone = TextContent(text: "bonito", style: style)
        let word = try #require(r.boxSize(for: alone, canvas: canvas)).width
        alone.emphasis = WordEmphasis(words: [0])
        #expect(try #require(r.boxSize(for: alone, canvas: canvas)).width > word * 1.1)

        var invalid = plain
        invalid.emphasis = WordEmphasis(words: [-1, 7, 99])
        #expect(r.boxSize(for: invalid, canvas: canvas) == a)
        #expect(r.lineTexts(for: invalid, canvas: canvas) == ["um teste bonito"])

        // Desenho: estático e por unidade, com a cor da ênfase só na palavra.
        for highlight in [false, true] {
            var p = Project()
            p.canvas.aspect = .r16x9
            var content = marked
            if highlight {
                content.words = (0..<3).map { CaptionWord(text: "", start: Micros($0) * 500_000, end: Micros($0 + 1) * 500_000) }
                var h = WordHighlight()
                h.color = .white
                h.scale = 1
                content.highlight = h
            }
            TimelineEditor.addText(content, to: &p, at: 0, duration: 2_000_000)
            let bmp = Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: canvas), time: 100_000) { _ in nil },
                             size: canvas)
            var red = 0, redX = 0
            for y in 0..<bmp.height {
                for x in 0..<bmp.width {
                    let i = (y * bmp.width + x) * 4
                    if bmp.data[i] > 200 && bmp.data[i + 1] < 60 { red += 1; redX += x }
                }
            }
            #expect(red > 300)
            #expect(Double(redX) / Double(max(red, 1)) > Double(canvas.width) * 0.55, "highlight \(highlight)")
        }
    }

    @Test("fitLines: linhas de larguras diferentes saem com a mesma largura (±2 px)")
    func fitLines() {
        var style = TextStyle()
        style.fontName = "Helvetica Neue"
        style.fontFace = "Condensed Black"
        style.fontSize = 0.1
        style.textCase = .upper
        style.fitLines = true
        style.maxWidth = 0.4
        style.lineSpacing = -0.15
        let content = TextContent(text: "sozinho\nmontanha\nrio azul", style: style)
        let r = TextRenderer.shared
        let text = TextRenderer.cased(content.text, style.textCase)
        let l = r.layout(text, style: style, canvas: canvas)
        let lines = CTFrameGetLines(l.frame) as! [CTLine]
        #expect(lines.count == 3)
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth($0)) }
        let target = CGFloat(style.maxWidth) * canvas.width
        for w in widths { #expect(abs(w - target) <= 2, "\(widths) alvo \(target)") }
        // A caixa acompanha a largura pedida; estreitar redimensiona tudo.
        let box = r.boxSize(for: content, canvas: canvas)!
        #expect(abs(box.width - target) <= 3)
        var narrow = content
        narrow.style.maxWidth = 0.3
        #expect(r.boxSize(for: narrow, canvas: canvas)!.height < box.height)

        // Desenho: a tinta de cada linha ocupa quase a mesma largura.
        var p = Project()
        p.canvas.aspect = .r16x9
        var drawn = content
        drawn.style.shadow = false
        drawn.style.y = 0
        TimelineEditor.addText(drawn, to: &p, at: 0, duration: 1_000_000)
        let bmp = Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: canvas), time: 0) { _ in nil }, size: canvas)
        var bands: [(minX: Int, maxX: Int)] = []
        var inBand = false
        for y in 0..<bmp.height {
            let xs = (0..<bmp.width).filter { bmp.data[(y * bmp.width + $0) * 4] > 128 }
            if let a = xs.first, let b = xs.last {
                if !inBand { bands.append((a, b)); inBand = true }
                else { bands[bands.count - 1] = (min(bands.last!.minX, a), max(bands.last!.maxX, b)) }
            } else {
                inBand = false
            }
        }
        #expect(bands.count == 3)
        let inkWidths = bands.map { $0.maxX - $0.minX }
        // A tinta perde só as margens laterais das letras.
        #expect(inkWidths.allSatisfy { abs(CGFloat($0) - target) < 0.06 * target }, "\(inkWidths)")
    }

    @Test("Empilhado e Surgir em 1080p: no padrão de desempenho dos outros textos")
    func performance() async throws {
        try await HeavyWork.run { measure() }
    }

    private func measure() {
        let words = spokenWords("Hoje eu vou mostrar para vocês como gerar legendas automáticas no editor sem internet")
        let size = CGSize(width: 1920, height: 1080)
        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
        var report: [String] = []
        for preset in [CaptionPreset.rise, .stacked, .fill, .typing, .editorial] {
            var p = Project()
            p.canvas.aspect = .r16x9
            let cues = CaptionBuilder.cues(from: words, preset: preset)
            CaptionBuilder.apply(cues, preset: preset, accent: RGBA(1, 0.8, 0.1), to: &p, replacing: false)
            let seg = p.tracks.last!.segments[0]
            func frame(_ t: Micros) {
                let img = FrameRenderer.shared.render(plan: RenderPlan(project: p, renderSize: size), time: t) { _ in nil }
                context.render(img, toBitmap: &bytes, rowBytes: 1920 * 4, bounds: CGRect(origin: .zero, size: size),
                               format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
            let span = seg.targetEnd - seg.targetStart
            for i in 0..<3 { frame(seg.targetStart + Micros(i) * span / 3) }
            var times: [Double] = []
            for i in 0..<30 {
                let start = Date()
                frame(seg.targetStart + Micros(i) * span / 30)
                times.append(Date().timeIntervalSince(start))
            }
            let perFrame = median(times)
            report.append("\(preset.rawValue): mediana \(String(format: "%.1f", perFrame * 1000)) ms/quadro, pior \(String(format: "%.1f", times.max()! * 1000)) ms")
            #expect(perFrame < 0.1)
        }
        print("Desempenho das legendas (1080p):\n" + report.joined(separator: "\n"))
    }
}
