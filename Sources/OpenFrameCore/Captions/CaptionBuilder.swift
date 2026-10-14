import CoreGraphics
import Foundation
import NaturalLanguage

public enum CaptionLayout: String, CaseIterable, Sendable, Identifiable {
    /// Frases: até 2 linhas, ~42 caracteres por linha (no 16:9), até ~5 s.
    case phrases
    /// Destaque: frases de 1 linha (~32 caracteres no 16:9) com destaque da palavra falada.
    case highlight
    /// Impacto: 2 a 4 palavras por vez, fonte grande no centro, com animação de entrada.
    case punch
    /// Empilhado: 2 a 5 palavras em 2 ou 3 linhas curtas (1 ou 2 palavras), com a palavra-chave sozinha
    /// numa linha. É o único em que o texto leva `\n`.
    case stacked

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .phrases: "Frases"
        case .highlight: "Destaque"
        case .punch: "Impacto"
        case .stacked: "Empilhado"
        }
    }
}

/// Uma legenda: o texto e as palavras dela, com tempos da timeline. O texto não tem `\n` (a quebra é a da
/// largura da caixa, com `balanceLines`), exceto no Empilhado; entre um artigo ou preposição e a palavra
/// seguinte vai um espaço sem quebra, para a linha não terminar neles.
public struct CaptionCue: Hashable, Sendable {
    public var text: String
    public var start: Micros
    public var end: Micros
    public var words: [TranscribedWord]

    public init(text: String, start: Micros, end: Micros, words: [TranscribedWord]) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

/// Quebra as palavras transcritas em legendas e as coloca no projeto.
public enum CaptionBuilder {
    /// Limites de cada segmentação.
    struct Limits {
        var lines: Int
        /// Caracteres de uma linha típica no 16:9: definem a largura padrão da caixa. A quebra em si mede as
        /// palavras com a fonte do estilo, na largura da caixa.
        var lineChars: Int
        var maxDuration: Micros
        var maxWords = Int.max
        /// Número de palavras preferido (impacto e empilhado).
        var idealWords: Int?
    }

    static func limits(_ layout: CaptionLayout) -> Limits {
        switch layout {
        case .phrases: Limits(lines: 2, lineChars: 42, maxDuration: 5_000_000)
        case .highlight: Limits(lines: 1, lineChars: 32, maxDuration: 4_000_000)
        case .punch: Limits(lines: 1, lineChars: 20, maxDuration: 2_500_000, maxWords: 4, idealWords: 3)
        case .stacked: Limits(lines: 3, lineChars: 12, maxDuration: 2_500_000, maxWords: 5, idealWords: 4)
        }
    }

    static func limits(preset: CaptionPreset) -> Limits {
        var lim = limits(preset.layout)
        // Cinema: frases curtas.
        if preset == .cinema { lim.maxDuration = 3_500_000 }
        return lim
    }

    /// Pausa que já vale como ponto de quebra.
    static let pause: Micros = 350_000
    /// Silêncio que sempre separa duas legendas (a anterior não fica na tela durante ele).
    static let forcedBreak: Micros = 1_200_000
    static let minDuration: Micros = 700_000
    static let closeGap: Micros = 250_000
    /// Espaço sem quebra: liga um artigo ou preposição à palavra seguinte.
    static let glue = "\u{00A0}"

    // MARK: - Medidas

    /// Medidas da quebra em em (frações do tamanho da fonte): cada palavra, o espaço e a largura da caixa.
    /// Valem para qualquer resolução do canvas com a mesma proporção.
    struct Measure {
        var widths: [Double]
        var space: Double
        var line: Double

        init(_ words: [TranscribedWord], style: TextStyle, aspect: Double) {
            let px: CGFloat = 100
            let r = TextRenderer.shared
            widths = words.map { Double(r.lineWidth($0.text, style: style, fontPx: px) / px) }
            space = Double((r.lineWidth("a a", style: style, fontPx: px) - 2 * r.lineWidth("a", style: style, fontPx: px)) / px)
            // Folga de 3% para a diferença entre as palavras medidas soltas e a linha inteira.
            line = style.fitLines ? .infinity : style.maxWidth * aspect / max(style.fontSize, 0.001) * 0.97
        }

        /// Linhas da quebra gulosa (a do Core Text) das palavras `r`. `glued(k)`: não quebra depois de `k`.
        func lineCount(_ r: Range<Int>, glued: (Int) -> Bool = { _ in false }) -> Int {
            var lines = 1
            var width = -1.0
            var k = r.lowerBound
            while k < r.upperBound {
                var chunk = widths[k]
                while k + 1 < r.upperBound, glued(k) {
                    k += 1
                    chunk += space + widths[k]
                }
                if width < 0 {
                    width = chunk
                } else if width + space + chunk <= line {
                    width += space + chunk
                } else {
                    lines += 1
                    width = chunk
                }
                k += 1
            }
            return lines
        }

        func length(_ r: Range<Int>) -> Double {
            widths[r].reduce(0, +) + space * Double(max(0, r.count - 1))
        }
    }

    // MARK: - Quebra

    /// Quebra natural:
    /// - prefere pausas (≥ ~0,35 s) e pontuação (. ? ! depois , ; :);
    /// - cada legenda cabe nas linhas da segmentação, medida com a fonte do visual na largura da caixa
    ///   (que depende da proporção do canvas: no 9:16 cabe menos numa linha);
    /// - não deixa preposição/artigo solto no fim da legenda nem da linha, quando der;
    /// - duração mínima de ~0,7 s, estendendo até a próxima sem sobrepor;
    /// - fecha vãos menores que ~0,25 s.
    public static func cues(from words: [TranscribedWord], preset: CaptionPreset, aspect: Double = 16.0 / 9) -> [CaptionCue] {
        let words = normalized(words)
        guard !words.isEmpty else { return [] }
        let lim = limits(preset: preset)
        let measure = Measure(words, style: style(preset, aspect: aspect), aspect: aspect)
        let n = words.count

        // Programação dinâmica: best[j] = menor custo para quebrar as palavras 0..<j.
        var best = [Double](repeating: .infinity, count: n + 1)
        var from = [Int](repeating: 0, count: n + 1)
        best[0] = 0
        for j in 1...n {
            var i = j - 1
            while i >= 0 {
                let count = j - i
                // Uma palavra sozinha sempre cabe (mesmo longa demais).
                if count > 1 {
                    if count > lim.maxWords { break }
                    if words[j - 1].end - words[i].start > lim.maxDuration { break }
                    if words[i + 1].start - words[i].end >= forcedBreak { break }
                    if measure.lineCount(i..<j) > lim.lines { break }
                }
                let cost = best[i] + cueCost(words, i, j, limits: lim, measure: measure)
                if cost < best[j] {
                    best[j] = cost
                    from[j] = i
                }
                i -= 1
            }
        }

        var ranges: [Range<Int>] = []
        var j = n
        while j > 0 {
            ranges.append(from[j]..<j)
            j = from[j]
        }
        ranges.reverse()

        let language = preset.layout == .stacked ? language(of: words) : nil
        var cues = ranges.map { r -> CaptionCue in
            let slice = Array(words[r])
            var cue = CaptionCue(text: "", start: slice.first!.start, end: max(slice.last!.end, slice.first!.start + 1),
                                 words: slice)
            if preset.layout == .stacked {
                let lines = stackLines(slice.map(\.text), keywords: Set(keywords(cue, language: language)))
                cue.text = lines.map { slice[$0].map(\.text).joined(separator: " ") }.joined(separator: "\n")
            } else {
                cue.text = text(r, words, measure: measure, limits: lim)
            }
            return cue
        }
        retime(&cues)
        return cues
    }

    /// A segmentação do visual clássico de `layout`.
    public static func cues(from words: [TranscribedWord], layout: CaptionLayout, aspect: Double = 16.0 / 9) -> [CaptionCue] {
        cues(from: words, preset: CaptionPreset(layout), aspect: aspect)
    }

    /// Custo de uma legenda com as palavras `i..<j`: uma base (menos legendas é melhor), o ponto de
    /// quebra no fim e o quanto ela fica curta ou mistura frases.
    static func cueCost(_ w: [TranscribedWord], _ i: Int, _ j: Int, limits: Limits, measure: Measure) -> Double {
        var cost = 1.0
        if j < w.count { cost += breakCost(after: w[j - 1], next: w[j]) }
        let count = j - i
        if let ideal = limits.idealWords {
            cost += 0.25 * Double(abs(count - ideal))
            if count == 1, j < w.count, i > 0 { cost += 0.8 }
        } else {
            // Legendas curtas demais piscam: só valem com pausa dos dois lados.
            let fill = measure.length(i..<j) / (Double(limits.lines) * measure.line)
            if fill < 0.5 { cost += (0.5 - fill) * 2.5 }
        }
        // Fim de frase seguido de pausa no meio da legenda: melhor quebrar ali.
        if count > 1 {
            for k in i..<(j - 1) {
                let gap = w[k + 1].start - w[k].end
                if endsSentence(w[k].text) { cost += gap >= pause ? 2.5 : 0.3 }
                else if gap >= 2 * pause { cost += 0.6 }
            }
        }
        return cost
    }

    /// Quanto custa terminar uma legenda depois de `word` (0 = ótimo ponto de quebra).
    static func breakCost(after word: TranscribedWord, next: TranscribedWord) -> Double {
        let gap = next.start - word.end
        if endsSentence(word.text) { return 0 }
        if gap >= pause { return endsClause(word.text) ? 0 : 0.2 }
        if endsClause(word.text) { return 0.4 }
        return isFunctionWord(word.text) ? 4 : 1.5
    }

    /// Texto da legenda numa linha só: a caixa quebra. O artigo ou preposição vai ligado à palavra seguinte
    /// por um espaço sem quebra, se o trecho ligado couber numa linha e a legenda ainda couber nas linhas
    /// da segmentação.
    static func text(_ r: Range<Int>, _ words: [TranscribedWord], measure: Measure, limits: Limits) -> String {
        var glued = Set<Int>()
        var chunk = 0.0
        for k in r {
            chunk = glued.contains(k - 1) ? chunk + measure.space + measure.widths[k] : measure.widths[k]
            guard k + 1 < r.upperBound, isFunctionWord(words[k].text) else { continue }
            if chunk + measure.space + measure.widths[k + 1] <= measure.line { glued.insert(k) }
        }
        if measure.lineCount(r, glued: glued.contains) > limits.lines { glued.removeAll() }
        var out = ""
        for k in r {
            out += words[k].text
            if k + 1 < r.upperBound { out += glued.contains(k) ? glue : " " }
        }
        return out
    }

    /// Linhas do Empilhado: grupos seguidos de 1 ou 2 palavras, em 2 ou 3 linhas. A palavra-chave fica sozinha
    /// na linha; artigo ou preposição não fica sozinho nem no fim da linha; e as linhas têm comprimentos
    /// parecidos (o `fitLines` amplia as curtas e reduz as longas, com limites).
    static func stackLines(_ words: [String], keywords: Set<Int>) -> [Range<Int>] {
        let n = words.count
        guard n > 1 else { return [0..<n] }
        let maxPart = max(2, (n + 2) / 3)
        func cost(_ parts: [Range<Int>]) -> Double {
            var c = 0.0
            for part in parts {
                if part.count > 1 {
                    c += 6 * Double(part.filter(keywords.contains).count)
                    if isFunctionWord(words[part.last! ]) { c += 2.5 }
                    // Fim de frase no meio da linha junta duas ideias.
                    if part.dropLast().contains(where: { endsSentence(words[$0]) || endsClause(words[$0]) }) { c += 1.5 }
                } else if isFunctionWord(words[part.first!]) {
                    c += 5
                }
            }
            let lengths = parts.map { p in Double(p.map { words[$0].count }.reduce(0, +) + p.count - 1) }
            let mean = lengths.reduce(0, +) / Double(lengths.count)
            c += 1.5 * lengths.map { abs(log(max($0, 1) / max(mean, 1))) }.reduce(0, +)
            return c
        }
        var best: (cost: Double, parts: [Range<Int>])?
        func visit(_ start: Int, _ parts: [Range<Int>]) {
            if start == n {
                guard parts.count >= 2 else { return }
                let c = cost(parts)
                if best == nil || c < best!.cost { best = (c, parts) }
                return
            }
            guard parts.count < 3 else { return }
            for size in 1...min(maxPart, n - start) { visit(start + size, parts + [start..<(start + size)]) }
        }
        visit(0, [])
        return best?.parts ?? [0..<n]
    }

    // MARK: - Palavra-chave

    /// Palavras-chave de uma legenda (Editorial e Empilhado): no máximo uma (duas com mais de 6 palavras,
    /// não vizinhas). Só valem palavras de 5 letras ou mais que não sejam artigo, preposição, conjunção,
    /// pronome ou determinante. O peso favorece substantivos e verbos, palavras longas e o fim de frase.
    /// Determinística.
    static func keywords(_ cue: CaptionCue) -> [Int] {
        keywords(cue, language: nil)
    }

    static func keywords(_ cue: CaptionCue, language: NLLanguage?) -> [Int] {
        let words = cue.words.map(\.text)
        guard !words.isEmpty else { return [] }
        let classes = lexicalClasses(words, language: language)
        let excluded: Set<NLTag> = [.pronoun, .determiner, .preposition, .conjunction, .particle, .classifier,
                                    .interjection, .number]
        var scored: [(score: Double, index: Int)] = []
        for (i, word) in words.enumerated() {
            let core = word.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            let letters = core.filter(\.isLetter).count
            guard letters >= 5, !isFunctionWord(core), !weakWords.contains(core.lowercased()) else { continue }
            if let tag = classes[i], excluded.contains(tag) { continue }
            var score = Double(min(letters, 12))
            switch classes[i] {
            case .noun?: score += 4
            case .verb?: score += 3
            case .adjective?: score += 1.5
            case .adverb?: score -= 3
            default: break
            }
            if endsSentence(word) || endsClause(word) || i == words.count - 1 { score += 2 }
            scored.append((score, i))
        }
        scored.sort { ($0.score, -$0.index) > ($1.score, -$1.index) }
        guard let first = scored.first?.index else { return [] }
        var picked = [first]
        if words.count > 6, let second = scored.dropFirst().first(where: { abs($0.index - first) > 1 })?.index {
            picked.append(second)
        }
        return picked.sorted()
    }

    /// Palavras de 5 letras ou mais sem peso (advérbios e pronomes comuns), caso a classe gramatical falhe.
    static let weakWords: Set<String> = [
        "porque", "quando", "também", "então", "muito", "muita", "muitos", "muitas", "sempre", "agora", "depois",
        "antes", "assim", "ainda", "apenas", "mesmo", "mesma", "outro", "outra", "outros", "outras", "todos",
        "todas", "vocês", "aquilo", "aquele", "aquela", "nossos", "nossas", "dessa", "desse", "deste", "desta",
        "nesse", "nessa", "neste", "nesta", "sobre", "entre", "estou", "estava", "seria", "tinha", "vamos",
        "there", "where", "which", "about", "because", "their", "these", "those", "would", "could", "should",
        "really", "after", "before", "other", "every", "being", "going",
        "porque", "cuando", "también", "entonces", "siempre", "ahora", "después", "parce", "quand", "toujours",
    ]

    /// Classe gramatical de cada palavra (a da primeira parte, se o etiquetador a dividir).
    static func lexicalClasses(_ words: [String], language: NLLanguage?) -> [NLTag?] {
        let text = words.joined(separator: " ")
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        for (k, w) in words.enumerated() {
            let end = text.index(index, offsetBy: w.count)
            ranges.append(index..<end)
            index = k + 1 < words.count ? text.index(after: end) : end
        }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        if let language { tagger.setLanguage(language, range: text.startIndex..<text.endIndex) }
        var result = [NLTag?](repeating: nil, count: words.count)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if let i = ranges.firstIndex(where: { $0.contains(range.lowerBound) }), result[i] == nil { result[i] = tag }
            return true
        }
        return result
    }

    /// Idioma predominante das palavras (para a classe gramatical).
    static func language(of words: [TranscribedWord]) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(words.prefix(400).map(\.text).joined(separator: " "))
        return recognizer.dominantLanguage
    }

    /// Duração mínima (estendendo até a próxima, sem sobrepor) e vãos curtos fechados.
    static func retime(_ cues: inout [CaptionCue]) {
        for k in cues.indices {
            let next = k + 1 < cues.count ? cues[k + 1].start : Micros.max
            var end = cues[k].end
            if end - cues[k].start < minDuration { end = cues[k].start + minDuration }
            if next - end < closeGap { end = next }
            cues[k].end = max(cues[k].start + 1, min(end, next))
        }
    }

    /// Tira espaços, junta pontuação solta à palavra anterior (o Whisper às vezes separa) e
    /// garante a ordem dos tempos. As palavras não têm espaço dentro: a contagem casa com o texto.
    static func normalized(_ words: [TranscribedWord]) -> [TranscribedWord] {
        var out: [TranscribedWord] = []
        for var w in words.sorted(by: { $0.start < $1.start }) {
            let pieces = w.text.split(whereSeparator: \.isWhitespace)
            guard !pieces.isEmpty else { continue }
            w.text = pieces.joined()
            w.end = max(w.end, w.start)
            if w.text.allSatisfy({ $0.isPunctuation || $0.isSymbol }), !out.isEmpty, !isOpening(w.text) {
                out[out.count - 1].text += w.text
                out[out.count - 1].end = max(out[out.count - 1].end, w.end)
                continue
            }
            out.append(w)
        }
        return out
    }

    private static func isOpening(_ s: String) -> Bool {
        s.allSatisfy { "¿¡([{«“\"'".contains($0) }
    }

    static func endsSentence(_ word: String) -> Bool {
        let t = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’»)]"))
        guard let last = t.last else { return false }
        return ".?!…".contains(last)
    }

    static func endsClause(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ",;:—–".contains(last)
    }

    /// Artigos, preposições e conjunções curtas (pt, en, es, fr, it, de): não ficam soltos no fim.
    static let functionWords: Set<String> = [
        // português
        "a", "o", "as", "os", "um", "uma", "uns", "umas", "de", "do", "da", "dos", "das", "em", "no", "na", "nos",
        "nas", "por", "pelo", "pela", "pelos", "pelas", "para", "pra", "pro", "com", "sem", "sob", "sobre", "entre",
        "até", "e", "ou", "mas", "que", "se", "ao", "aos", "à", "às", "num", "numa", "meu", "minha", "seu", "sua",
        "nosso", "nossa", "este", "esta", "esse", "essa", "aquele", "aquela", "eu", "tu", "ele", "ela", "nós",
        // inglês
        "the", "an", "of", "to", "in", "on", "at", "for", "with", "by", "from", "and", "or", "but", "as", "into",
        "my", "your", "his", "her", "our", "their", "this", "that", "is", "i",
        // espanhol, francês, italiano e alemão
        "el", "la", "los", "las", "una", "del", "con", "y", "al", "le", "les", "une", "des", "du", "au", "aux",
        "et", "pour", "avec", "sur", "il", "lo", "gli", "di", "per", "der", "die", "das", "ein", "eine", "und",
        "mit", "von", "zu",
    ]

    static func isFunctionWord(_ word: String) -> Bool {
        functionWords.contains(word.lowercased())
    }

    // MARK: - Projeto

    /// Cria (ou substitui, se `replacing`) uma faixa de texto só das legendas automáticas e devolve o id dela.
    /// Cada legenda vira um segmento de texto com o estilo, o destaque, a palavra-chave e as animações da
    /// predefinição, e `words` (relativo ao segmento). `accent` vai para onde a predefinição usa a cor
    /// (sem ela, amarelo). A caixa do estilo se ajusta à proporção do canvas do projeto.
    ///
    /// Substituir troca só as legendas automáticas que tocam `range` (o trecho transcrito; sem ele, o
    /// trecho das legendas novas): gerar de um clipe não apaga as dos outros clipes.
    @discardableResult
    public static func apply(_ cues: [CaptionCue], preset: CaptionPreset, accent: RGBA?, to project: inout Project,
                             replacing: Bool, range: TimeRange? = nil) -> UUID {
        let style = style(preset, aspect: project.aspectValue)
        return insert(segments(cues, preset: preset, style: style, accent: accent), cues: cues, into: &project,
                      replacing: replacing, range: range)
    }

    /// Igual a `apply(_:preset:…)` com o visual clássico de `layout` e, se dado, outro estilo.
    @discardableResult
    public static func apply(_ cues: [CaptionCue], layout: CaptionLayout, style: TextStyle?, to project: inout Project,
                             replacing: Bool, range: TimeRange? = nil) -> UUID {
        let preset = CaptionPreset(layout)
        let style = style ?? self.style(preset, aspect: project.aspectValue)
        return insert(segments(cues, preset: preset, style: style, accent: nil), cues: cues, into: &project,
                      replacing: replacing, range: range)
    }

    static func segments(_ cues: [CaptionCue], preset: CaptionPreset, style: TextStyle, accent: RGBA?) -> [Segment] {
        let usesKeywords = preset == .editorial || preset == .stacked
        let language = usesKeywords ? language(of: cues.flatMap(\.words)) : nil
        return cues.map { cue -> Segment in
            var content = TextContent(text: cue.text, style: style)
            content.words = cue.words.map {
                CaptionWord(text: $0.text, start: $0.start - cue.start, end: $0.end - cue.start)
            }
            content.highlight = highlight(preset, accent: accent)
            if usesKeywords {
                var emphasis = emphasis(preset, style: style, accent: accent)
                emphasis?.words = keywords(cue, language: language)
                content.emphasis = emphasis
            }
            let duration = max(TimelineEditor.minDuration, cue.end - cue.start)
            var seg = Segment.text(content, at: max(0, cue.start), duration: duration)
            animate(&seg, preset: preset, duration: duration)
            return seg
        }
    }

    /// Destaque da palavra falada de cada visual (`nil` = sem destaque).
    static func highlight(_ preset: CaptionPreset, accent: RGBA?) -> WordHighlight? {
        var h = WordHighlight()
        h.color = accent ?? .yellow
        switch preset {
        case .highlight:
            break
        case .rise:
            h.reveal = .rise
            h.scale = 1
        case .guided:
            h.reveal = .dim
            h.dimOpacity = 0.35
            h.scale = 1
        case .fill:
            h.reveal = .fill
            h.mode = .progressive
            h.scale = 1.05
        case .typing:
            h.reveal = .type
            h.scale = 1
        case .phrases, .punch, .editorial, .cinema, .stacked:
            return nil
        }
        return h
    }

    /// Estilo da palavra-chave de cada visual, sem os índices (`nil` = sem palavra-chave).
    static func emphasis(_ preset: CaptionPreset, style: TextStyle, accent: RGBA?) -> WordEmphasis? {
        var e = WordEmphasis()
        e.color = accent ?? .yellow
        switch preset {
        case .editorial:
            break
        case .stacked:
            // A mesma fonte do bloco: só a cor muda (e a linha própria).
            e.fontName = style.fontName
            e.fontFace = style.fontFace
            e.scale = 1
        default:
            return nil
        }
        return e
    }

    /// Entrada e saída de cada visual.
    static func animate(_ seg: inout Segment, preset: CaptionPreset, duration: Micros) {
        switch preset {
        case .punch:
            seg.animationIn = SegmentAnimation(kind: .elastic, duration: min(350_000, duration / 2))
        case .rise:
            seg.animationOut = SegmentAnimation(kind: .fade, duration: min(150_000, duration / 4))
        case .editorial:
            seg.animationIn = SegmentAnimation(kind: .focus, duration: min(300_000, duration / 3))
        case .cinema:
            seg.animationIn = SegmentAnimation(kind: .focus, duration: min(400_000, duration / 3))
            seg.animationOut = SegmentAnimation(kind: .fade, duration: min(300_000, duration / 4))
        case .stacked:
            seg.animationIn = SegmentAnimation(kind: .cascade, duration: min(400_000, duration / 2))
        case .phrases, .highlight, .guided, .fill, .typing:
            break
        }
    }

    static func insert(_ segments: [Segment], cues: [CaptionCue], into project: inout Project, replacing: Bool,
                       range: TimeRange?) -> UUID {
        if replacing, let t = project.tracks.firstIndex(where: { $0.isAutoCaptions }) {
            let keep = project.tracks[t].id
            if let span = range ?? cues.first.map({ TimeRange(start: $0.start, duration: cues.last!.end - $0.start) }) {
                for k in project.tracks.indices where project.tracks[k].isAutoCaptions {
                    project.tracks[k].segments.removeAll { $0.targetStart < span.end && span.start < $0.targetEnd }
                }
            }
            project.tracks[t].segments += segments
            project.tracks[t].segments.sort { $0.targetStart < $1.targetStart }
            // Faixas automáticas que ficaram vazias somem.
            project.tracks.removeAll { $0.isAutoCaptions && $0.id != keep && $0.segments.isEmpty }
            return keep
        }
        var track = Track(kind: .text)
        track.isAutoCaptions = true
        track.segments = segments
        project.tracks.append(track)
        return track.id
    }

    // MARK: - Estilos

    /// Largura máxima da caixa das legendas (fração do quadro), em qualquer proporção.
    static let widestBox = 0.9

    /// O estilo padrão na proporção do canvas: a caixa mantém a largura em em do 16:9 (a mesma quebra),
    /// sem passar de 90% do quadro. No 9:16 cabe menos numa linha, e a segmentação já conta com isso.
    static func style(_ preset: CaptionPreset, aspect: Double) -> TextStyle {
        var s = defaultStyle(preset)
        guard aspect > 0, aspect.isFinite else { return s }
        s.maxWidth = min(max(s.maxWidth, widestBox), s.maxWidth * ((16.0 / 9) / aspect))
        return s
    }

    /// Estilo padrão de cada visual no 16:9 (fonte, tamanho, posição, contorno/fundo e largura da caixa),
    /// usado também nas prévias. A caixa comporta ~`lineChars` caracteres por linha.
    public static func defaultStyle(_ preset: CaptionPreset) -> TextStyle {
        var s = TextStyle()
        s.fontName = "Helvetica Neue"
        s.bold = true
        s.color = .white
        s.balanceLines = true
        switch preset {
        case .phrases:
            // Legenda clássica: branca, contorno fino e sombra, embaixo.
            s.fontSize = 0.055
            s.strokeWidth = 8
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.6)
            s.y = -0.78
            s.maxWidth = 0.66
        case .highlight:
            s.fontSize = 0.07
            s.strokeWidth = 12
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.5)
            s.y = -0.55
            s.maxWidth = 0.64
        case .punch:
            s.fontSize = 0.11
            s.textCase = .upper
            s.strokeWidth = 14
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.55)
            s.shadowDistance = 0.06
            s.y = 0
            s.maxWidth = 0.76
        case .rise:
            s.fontSize = 0.07
            s.strokeWidth = 5
            s.strokeColor = RGBA(0, 0, 0, 0.85)
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.55)
            s.shadowBlur = 0.25
            s.y = -0.55
            s.maxWidth = 0.64
        case .guided:
            s.fontSize = 0.055
            s.strokeWidth = 0
            s.shadow = false
            s.backgroundEnabled = true
            s.backgroundColor = RGBA(0, 0, 0, 0.55)
            s.backgroundRadius = 0.35
            s.backgroundPaddingX = 0.45
            s.backgroundPaddingY = 0.25
            s.y = -0.72
            s.maxWidth = 0.66
        case .fill:
            s.fontSize = 0.075
            s.strokeWidth = 18
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.5)
            s.y = -0.5
            s.maxWidth = 0.68
        case .typing:
            s.fontName = "Menlo"
            s.fontSize = 0.06
            s.strokeWidth = 0
            s.shadow = false
            s.backgroundEnabled = true
            s.backgroundColor = RGBA(0.05, 0.05, 0.07, 0.8)
            s.backgroundRadius = 0.2
            s.backgroundPaddingX = 0.5
            s.backgroundPaddingY = 0.3
            s.y = -0.6
            s.maxWidth = 0.66
        case .editorial:
            s.fontFace = "Light"
            s.bold = false
            s.fontSize = 0.058
            s.strokeWidth = 0
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.45)
            s.shadowDistance = 0.03
            s.shadowBlur = 0.3
            s.y = -0.68
            s.maxWidth = 0.64
        case .cinema:
            s.fontFace = "Light"
            s.bold = false
            s.fontSize = 0.042
            s.letterSpacing = 0.15
            s.strokeWidth = 0
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.5)
            s.shadowDistance = 0.02
            s.shadowBlur = 0.25
            s.y = -0.82
            s.maxWidth = 0.5
        case .stacked:
            s.fontFace = "Condensed Black"
            s.fontSize = 0.1
            s.textCase = .upper
            s.fitLines = true
            s.balanceLines = false
            s.lineSpacing = -0.15
            s.strokeWidth = 0
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.5)
            s.shadowBlur = 0.2
            s.y = 0
            s.maxWidth = 0.36
        }
        return s
    }
}
