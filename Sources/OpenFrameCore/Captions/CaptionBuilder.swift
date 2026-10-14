import Foundation

public enum CaptionLayout: String, CaseIterable, Sendable, Identifiable {
    /// Frases: até 2 linhas, ~42 caracteres por linha, até ~5 s.
    case phrases
    /// Destaque: frases de 1 linha (~32 caracteres) com destaque da palavra falada.
    case highlight
    /// Impacto: 2 a 4 palavras por vez, fonte grande no centro, com animação de entrada.
    case punch

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .phrases: "Frases"
        case .highlight: "Destaque"
        case .punch: "Impacto"
        }
    }
}

/// Uma legenda: o texto (com `\n` entre as linhas) e as palavras dela, com tempos da timeline.
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
    /// Limites de cada layout.
    struct Limits {
        var lines: Int
        var lineChars: Int
        var maxDuration: Micros
        var maxWords = Int.max
        /// Número de palavras preferido (só no impacto).
        var idealWords: Int?
    }

    static func limits(_ layout: CaptionLayout) -> Limits {
        switch layout {
        case .phrases: Limits(lines: 2, lineChars: 42, maxDuration: 5_000_000)
        case .highlight: Limits(lines: 1, lineChars: 32, maxDuration: 4_000_000)
        case .punch: Limits(lines: 1, lineChars: 20, maxDuration: 2_500_000, maxWords: 4, idealWords: 3)
        }
    }

    /// Pausa que já vale como ponto de quebra.
    static let pause: Micros = 350_000
    /// Silêncio que sempre separa duas legendas (a anterior não fica na tela durante ele).
    static let forcedBreak: Micros = 1_200_000
    static let minDuration: Micros = 700_000
    static let closeGap: Micros = 250_000

    // MARK: - Quebra

    /// Quebra natural:
    /// - prefere pausas (≥ ~0,35 s) e pontuação (. ? ! depois , ; :);
    /// - não deixa preposição/artigo solto no fim da linha, quando der;
    /// - equilibra as duas linhas;
    /// - duração mínima de ~0,7 s, estendendo até a próxima sem sobrepor;
    /// - fecha vãos menores que ~0,25 s.
    public static func cues(from words: [TranscribedWord], layout: CaptionLayout) -> [CaptionCue] {
        let words = normalized(words)
        guard !words.isEmpty else { return [] }
        let lim = limits(layout)
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
                    if !lineSplit(words[i..<j], limits: lim).fits { break }
                }
                let cost = best[i] + cueCost(words, i, j, limits: lim)
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

        var cues = ranges.map { r -> CaptionCue in
            let slice = words[r]
            let text = render(slice, limits: lim)
            return CaptionCue(text: text, start: slice.first!.start, end: max(slice.last!.end, slice.first!.start + 1),
                              words: Array(slice))
        }
        retime(&cues)
        return cues
    }

    /// Custo de uma legenda com as palavras `i..<j`: uma base (menos legendas é melhor), o ponto de
    /// quebra no fim e o quanto ela fica curta ou mistura frases.
    static func cueCost(_ w: [TranscribedWord], _ i: Int, _ j: Int, limits: Limits) -> Double {
        var cost = 1.0
        if j < w.count { cost += breakCost(after: w[j - 1], next: w[j]) }
        let count = j - i
        let chars = length(w[i..<j])
        if let ideal = limits.idealWords {
            cost += 0.25 * Double(abs(count - ideal))
            if count == 1, j < w.count, i > 0 { cost += 0.8 }
        } else {
            // Legendas curtas demais piscam: só valem com pausa dos dois lados.
            let capacity = Double(limits.lines * limits.lineChars)
            let fill = Double(chars) / capacity
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

    /// Se cabe nas linhas do layout e onde quebrar a linha: o índice da primeira palavra da
    /// segunda linha, ou `nil` se cabe numa só.
    static func lineSplit(_ words: ArraySlice<TranscribedWord>, limits: Limits) -> (fits: Bool, at: Int?) {
        let total = length(words)
        if total <= limits.lineChars { return (true, nil) }
        guard limits.lines >= 2, words.count >= 2 else { return (false, nil) }
        var best: (cost: Double, at: Int)?
        var first = 0
        for k in words.indices.dropLast() {
            first += (k == words.startIndex ? 0 : 1) + words[k].text.count
            let second = total - first - 1
            guard first <= limits.lineChars, second <= limits.lineChars else { continue }
            var cost = Double(abs(first - second))
            let w = words[k]
            if endsSentence(w.text) { cost -= 10 }
            else if endsClause(w.text) { cost -= 6 }
            else if isFunctionWord(w.text) { cost += 12 }
            if words[k + 1].start - w.end >= pause { cost -= 4 }
            if best == nil || cost < best!.cost { best = (cost, k + 1) }
        }
        return best.map { (true, $0.at) } ?? (false, nil)
    }

    static func render(_ words: ArraySlice<TranscribedWord>, limits: Limits) -> String {
        guard let split = lineSplit(words, limits: limits).at else {
            return words.map(\.text).joined(separator: " ")
        }
        return words[..<split].map(\.text).joined(separator: " ") + "\n" + words[split...].map(\.text).joined(separator: " ")
    }

    static func length(_ words: ArraySlice<TranscribedWord>) -> Int {
        words.reduce(0) { $0 + $1.text.count } + max(0, words.count - 1)
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
    /// Cada legenda vira um segmento de texto com o estilo do layout, `words` (relativo ao segmento) e
    /// `highlight` (no layout destaque). O impacto ganha uma entrada curta (Elástico).
    @discardableResult
    public static func apply(_ cues: [CaptionCue], layout: CaptionLayout, style: TextStyle?, to project: inout Project,
                             replacing: Bool) -> UUID {
        let style = style ?? defaultStyle(layout)
        let segments = cues.map { cue -> Segment in
            var content = TextContent(text: cue.text, style: style)
            content.words = cue.words.map {
                CaptionWord(text: $0.text, start: $0.start - cue.start, end: $0.end - cue.start)
            }
            if layout == .highlight { content.highlight = WordHighlight() }
            let duration = max(TimelineEditor.minDuration, cue.end - cue.start)
            var seg = Segment.text(content, at: max(0, cue.start), duration: duration)
            if layout == .punch {
                seg.animationIn = SegmentAnimation(kind: .elastic, duration: min(350_000, duration / 2))
            }
            return seg
        }
        if replacing, let t = project.tracks.firstIndex(where: { $0.isAutoCaptions }) {
            project.tracks[t].segments = segments
            // Outras faixas automáticas antigas somem: fica uma só.
            let keep = project.tracks[t].id
            project.tracks.removeAll { $0.isAutoCaptions && $0.id != keep }
            return keep
        }
        var track = Track(kind: .text)
        track.isAutoCaptions = true
        track.segments = segments
        project.tracks.append(track)
        return track.id
    }

    /// Estilo padrão de cada layout (fonte, tamanho, posição, contorno/fundo), usado também nas prévias.
    public static func defaultStyle(_ layout: CaptionLayout) -> TextStyle {
        var s = TextStyle()
        s.fontName = "Helvetica Neue"
        s.bold = true
        s.color = .white
        switch layout {
        case .phrases:
            // Legenda clássica: branca, contorno fino e sombra, embaixo.
            s.fontSize = 0.055
            s.strokeWidth = 8
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.6)
            s.y = -0.78
            s.maxWidth = 0.9
        case .highlight:
            s.fontSize = 0.07
            s.strokeWidth = 12
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.5)
            s.y = -0.55
            s.maxWidth = 0.9
        case .punch:
            s.fontSize = 0.11
            s.textCase = .upper
            s.strokeWidth = 14
            s.strokeColor = .black
            s.shadow = true
            s.shadowColor = RGBA(0, 0, 0, 0.55)
            s.shadowDistance = 0.06
            s.y = 0
            s.maxWidth = 0.85
        }
        return s
    }
}
