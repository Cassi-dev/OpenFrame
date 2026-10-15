import CoreGraphics
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Legendas: largura da caixa e quebra equilibrada")
struct TextWidthTests {
    let canvas = CGSize(width: 1920, height: 1080)

    @Test("setTextWidth limita à faixa e ignora valores inválidos")
    func clamps() {
        var p = Project()
        let id = TimelineEditor.addText(TextContent(text: "Oi"), to: &p, at: 0)
        TimelineEditor.setTextWidth(&p, segment: id, maxWidth: 0.01)
        #expect(p.segment(id)!.text!.style.maxWidth == TextStyle.maxWidthRange.lowerBound)
        TimelineEditor.setTextWidth(&p, segment: id, maxWidth: 10)
        #expect(p.segment(id)!.text!.style.maxWidth == TextStyle.maxWidthRange.upperBound)
        TimelineEditor.setTextWidth(&p, segment: id, maxWidth: 1.4)
        #expect(p.segment(id)!.text!.style.maxWidth == 1.4)
        TimelineEditor.setTextWidth(&p, segment: id, maxWidth: .nan)
        TimelineEditor.setTextWidth(&p, segment: id, maxWidth: .infinity)
        #expect(p.segment(id)!.text!.style.maxWidth == 1.4)
        // Segmento que não é texto: nada muda.
        let before = p
        TimelineEditor.setTextWidth(&p, segment: UUID(), maxWidth: 0.5)
        #expect(p == before)
    }

    @Test("Numa faixa automática, a largura vale para todos os textos dela e só dela")
    func wholeTrack() throws {
        var p = Project()
        let user = TimelineEditor.addText(TextContent(text: "Título"), to: &p, at: 0)
        let cues = CaptionBuilder.cues(from: spokenWords("Olá mundo. Tudo bem com você? Vamos lá."), layout: .highlight)
        let first = CaptionBuilder.apply(cues, preset: .highlight, accent: nil, to: &p, replacing: false)
        let second = CaptionBuilder.apply(cues, preset: .phrases, accent: nil, to: &p, replacing: false)
        let segs = try #require(p.tracks.first { $0.id == first }).segments
        #expect(segs.count > 1)
        TimelineEditor.setTextWidth(&p, segment: segs[1].id, maxWidth: 1.2)
        #expect(p.tracks.first { $0.id == first }!.segments.allSatisfy { $0.text!.style.maxWidth == 1.2 })
        #expect(p.tracks.first { $0.id == second }!.segments.allSatisfy { $0.text!.style.maxWidth != 1.2 })
        #expect(p.segment(user)!.text!.style.maxWidth == TextStyle().maxWidth)

        // Texto comum: só ele.
        TimelineEditor.setTextWidth(&p, segment: user, maxWidth: 0.5)
        #expect(p.segment(user)!.text!.style.maxWidth == 0.5)
        #expect(p.tracks.first { $0.id == first }!.segments.allSatisfy { $0.text!.style.maxWidth == 1.2 })
    }

    @Test("Equilibrar: o mesmo número de linhas, com a mais longa menor ou igual",
          arguments: [0.3, 0.45, 0.6, 0.9])
    func balance(width: Double) {
        let text = "O rato roeu a roupa do rei de Roma e a rainha, com raiva, resolveu remendar tudo sozinha"
        var style = TextStyle()
        style.fontSize = 0.06
        style.maxWidth = width
        var balanced = style
        balanced.balanceLines = true
        let r = TextRenderer.shared
        let plain = r.lineTexts(for: TextContent(text: text, style: style), canvas: canvas)
        let even = r.lineTexts(for: TextContent(text: text, style: balanced), canvas: canvas)
        #expect(plain.count == even.count)
        #expect(even.joined(separator: " ") == plain.joined(separator: " "))
        let widest = { (lines: [String]) in lines.map { r.lineWidth($0, style: style, fontPx: 100) }.max()! }
        #expect(widest(even) <= widest(plain) + 0.01)
        if plain.count > 1 {
            // A caixa encolhe junto (é ela que o preview mostra).
            let a = r.boxSize(for: TextContent(text: text, style: style), canvas: canvas)!
            let b = r.boxSize(for: TextContent(text: text, style: balanced), canvas: canvas)!
            #expect(b.width <= a.width && b.height == a.height)
        }
        // Uma linha só: nada muda.
        let short = TextContent(text: "curto", style: balanced)
        #expect(r.lineTexts(for: short, canvas: canvas) == ["curto"])
    }

    @Test("A caixa passa da largura do quadro: texto longo numa linha só")
    func wideBox() {
        var style = TextStyle()
        style.fontSize = 0.07
        style.balanceLines = true
        let content = { (w: Double) -> TextContent in
            style.maxWidth = w
            return TextContent(text: "uma legenda bem comprida que normalmente quebraria em duas linhas ou mais", style: style)
        }
        #expect(TextRenderer.shared.lineTexts(for: content(0.9), canvas: canvas).count > 1)
        #expect(TextRenderer.shared.lineTexts(for: content(3), canvas: canvas).count == 1)
        #expect(TextRenderer.shared.boxSize(for: content(3), canvas: canvas)!.width > canvas.width)
    }
}

@Suite("Legendas: campos novos no JSON")
struct CaptionStyleCodingTests {
    @Test("Um JSON antigo abre igual: os campos novos ficam com o padrão")
    func oldJSON() throws {
        let json = #"""
        {"text": "um dois", "style": {"fontName": "Helvetica Neue", "maxWidth": 0.8},
         "words": [{"text": "um", "start": 0, "end": 10}, {"text": "dois", "start": 10, "end": 20}],
         "highlight": {"color": {"r": 1, "g": 0, "b": 0, "a": 1}, "scale": 1.2}}
        """#
        let c = try JSONDecoder().decode(TextContent.self, from: Data(json.utf8))
        #expect(c.style.maxWidth == 0.8)
        #expect(!c.style.balanceLines && !c.style.fitLines)
        #expect(c.emphasis == nil)
        #expect(c.highlight?.reveal == WordReveal.none)
        #expect(c.highlight?.dimOpacity == 0.35)
        #expect(c.highlight?.scale == 1.2)
    }

    @Test("Revelação desconhecida vira nenhuma; palavra-chave incompleta usa o padrão")
    func tolerant() throws {
        let h = try JSONDecoder().decode(WordHighlight.self, from: Data(#"{"reveal": "holograma", "dimOpacity": 0.5}"#.utf8))
        #expect(h.reveal == WordReveal.none)
        #expect(h.dimOpacity == 0.5)
        let e = try JSONDecoder().decode(WordEmphasis.self, from: Data(#"{"words": [2]}"#.utf8))
        var expected = WordEmphasis(words: [2])
        expected.color = nil
        #expect(e == expected)
        #expect(try JSONDecoder().decode(WordEmphasis.self, from: Data("{}".utf8)) == WordEmphasis())
    }

    @Test("Visuais novos vão e voltam no JSON", arguments: CaptionPreset.allCases)
    func roundTrip(preset: CaptionPreset) throws {
        var p = Project()
        let cues = CaptionBuilder.cues(from: spokenWords("Hoje vamos construir legendas incríveis. Tudo bem?"), preset: preset)
        CaptionBuilder.apply(cues, preset: preset, accent: RGBA(0.2, 0.8, 1), to: &p, replacing: false)
        let back = try ProjectStore.decode(ProjectStore.encode(p))
        #expect(back == p)
    }

    @Test("Sem palavra-chave, a chave não é gravada")
    func noEmphasisKey() throws {
        var p = Project()
        TimelineEditor.addText(TextContent(text: "Oi"), to: &p, at: 0)
        let json = String(decoding: try ProjectStore.encode(p), as: UTF8.self)
        #expect(!json.contains("\"emphasis\""))
    }
}

@Suite("Legendas: predefinições")
struct CaptionPresetTests {
    let speech = """
    Hoje eu vou mostrar para vocês como gerar legendas automáticas no editor, sem internet e sem complicação. \
    Primeiro escolha o idioma da fala; depois escolha a precisão do modelo e o estilo que combina com o vídeo.
    """

    @Test("Nomes, grupos e segmentação")
    func catalog() {
        #expect(CaptionPreset.allCases.map(\.displayName) == ["Frases", "Destaque", "Impacto", "Surgir", "Leitura guiada",
                                                              "Preenchimento", "Digitação", "Editorial", "Cinema", "Empilhado"])
        #expect(CaptionPresetGroup.allCases.map(\.displayName) == ["Clássicos", "Revelação", "Editorial"])
        #expect(CaptionPreset.allCases.filter { $0.group == .reveal } == [.rise, .guided, .fill, .typing])
        #expect(CaptionPreset.allCases.allSatisfy { !$0.detail.isEmpty })
        #expect(CaptionPreset.allCases.filter { !$0.usesAccent } == [.phrases, .punch, .cinema])
        #expect(CaptionPreset.stacked.layout == .stacked)
        #expect(WordReveal.allCases.map(\.displayName) == ["Nenhuma", "Surgir", "Leitura guiada", "Preenchimento", "Digitação"])
        for layout in CaptionLayout.allCases { #expect(CaptionPreset(layout).layout == layout) }
    }

    @Test("Os clássicos continuam iguais pela API antiga e pela nova")
    func classicsMatch() {
        let words = spokenWords(speech)
        for layout in [CaptionLayout.phrases, .highlight, .punch] {
            var a = Project()
            var b = Project()
            CaptionBuilder.apply(CaptionBuilder.cues(from: words, layout: layout), layout: layout, style: nil, to: &a,
                                 replacing: false)
            CaptionBuilder.apply(CaptionBuilder.cues(from: words, preset: CaptionPreset(layout)), preset: CaptionPreset(layout),
                                 accent: nil, to: &b, replacing: false)
            let segsA = a.tracks.last!.segments
            let segsB = b.tracks.last!.segments
            #expect(segsA.map(\.text) == segsB.map(\.text))
            #expect(segsA.map(\.animationIn) == segsB.map(\.animationIn))
            #expect(segsA.map(\.targetStart) == segsB.map(\.targetStart))
        }
    }

    @Test("Cada visual leva o destaque, a palavra-chave e a cor nos lugares certos", arguments: CaptionPreset.allCases)
    func applies(preset: CaptionPreset) throws {
        var p = Project()
        let accent = RGBA(0.1, 0.9, 0.4)
        let cues = CaptionBuilder.cues(from: spokenWords(speech), preset: preset)
        let id = CaptionBuilder.apply(cues, preset: preset, accent: accent, to: &p, replacing: false)
        let segs = try #require(p.tracks.first { $0.id == id }).segments
        #expect(segs.count == cues.count)
        for seg in segs {
            let text = try #require(seg.text)
            #expect(text.style == CaptionBuilder.defaultStyle(preset))
            #expect(text.words?.count == TextContent.words(of: text.text).count)
            switch preset {
            case .highlight, .rise, .guided, .fill, .typing:
                #expect(text.highlight?.color == accent)
            default:
                #expect(text.highlight == nil)
            }
            if preset == .editorial || preset == .stacked {
                let e = try #require(text.emphasis)
                #expect(e.color == accent)
                #expect(e.words.count <= (text.words!.count > 6 ? 2 : 1))
            } else {
                #expect(text.emphasis == nil)
            }
        }
        let reveal: [CaptionPreset: WordReveal] = [.rise: .rise, .guided: .dim, .fill: .fill, .typing: .type]
        if let r = reveal[preset] { #expect(segs[0].text!.highlight!.reveal == r) }
        #expect(segs.contains { $0.text!.emphasis.map { !$0.words.isEmpty } ?? false } == (preset == .editorial || preset == .stacked))
    }

    @Test("Empilhado: 2 ou 3 linhas de 1 ou 2 palavras, a palavra-chave sozinha na linha")
    func stacked() {
        let cues = CaptionBuilder.cues(from: spokenWords(speech), preset: .stacked)
        let language = CaptionBuilder.language(of: cues.flatMap(\.words))
        #expect(cues.allSatisfy { (1...5).contains($0.words.count) })
        for cue in cues where cue.words.count > 1 {
            let lines = cue.text.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
            #expect((2...3).contains(lines.count), "\(cue.text)")
            #expect(lines.flatMap { $0 } == cue.words.map(\.text))
            var index = 0
            let keywords = Set(CaptionBuilder.keywords(cue, language: language))
            for line in lines {
                let range = index..<(index + line.count)
                if line.count > 1 { #expect(keywords.isDisjoint(with: range), "\(cue.text)") }
                index += line.count
            }
        }
        // Linhas pelo `\n`: o estilo não equilibra nem quebra pela largura.
        let style = CaptionBuilder.defaultStyle(.stacked)
        #expect(style.fitLines && !style.balanceLines && style.textCase == .upper)
    }

    @Test("Empilhado: o bloco mais alto fica em ~45% da altura do quadro em qualquer proporção",
          arguments: [(16.0 / 9, CGSize(width: 1920, height: 1080)), (9.0 / 16, CGSize(width: 1080, height: 1920)),
                      (1.0, CGSize(width: 1080, height: 1080))])
    func stackedHeight(aspect: Double, canvas: CGSize) {
        let style = CaptionBuilder.defaultStyle(.stacked, aspect: aspect)
        let cues = CaptionBuilder.cues(from: spokenWords(speech + " Pronto: as legendas aparecem na timeline, uma faixa só delas."),
                                       preset: .stacked, aspect: aspect)
        let heights = cues.map { cue -> CGFloat in
            var content = TextContent(text: cue.text, style: style)
            content.emphasis = WordEmphasis(words: CaptionBuilder.keywords(cue))
            return TextRenderer.shared.boxSize(for: content, canvas: canvas)!.height / canvas.height
        }
        #expect(heights.max()! <= 0.47, "\(heights.max()!)")
        #expect(heights.max()! >= 0.35)
        // Em pé, o mesmo de antes (caixa de 64% da largura, fonte de 0,13 do lado menor).
        if aspect < 1 {
            #expect(abs(style.maxWidth - 0.64) < 0.001)
            #expect(abs(style.fontSize * canvas.height - 0.13 * canvas.width) < 0.1)
        }
        #expect(CaptionBuilder.defaultStyle(.stacked, aspect: 16.0 / 9) == CaptionBuilder.defaultStyle(.stacked))
    }

    @Test("Palavra-chave: nunca uma palavra funcional, no máximo uma (duas com mais de 6 palavras); determinística")
    func keywords() {
        let texts = [
            "o problema de verdade é a velocidade",
            "eu acho que vocês vão adorar essa novidade",
            "de para com sem sobre entre",
            "The quick brown fox jumps over the lazy dog because everything matters",
            "mas porque então também",
            "a",
        ]
        for text in texts {
            let cue = CaptionCue(text: text, start: 0, end: 1, words: spokenWords(text))
            let picked = CaptionBuilder.keywords(cue)
            #expect(picked.count <= (cue.words.count > 6 ? 2 : 1))
            for i in picked {
                let word = cue.words[i].text
                #expect(!CaptionBuilder.isFunctionWord(word))
                #expect(word.filter(\.isLetter).count >= 5, "\(word)")
            }
            #expect(CaptionBuilder.keywords(cue) == picked)
        }
        let none = CaptionCue(text: "", start: 0, end: 1, words: spokenWords("de para com sem sobre entre"))
        #expect(CaptionBuilder.keywords(none).isEmpty)
        let speed = CaptionCue(text: "", start: 0, end: 1, words: spokenWords("o problema real é a velocidade"))
        #expect(CaptionBuilder.keywords(speed).map { speed.words[$0].text } == ["velocidade"])
    }
}
