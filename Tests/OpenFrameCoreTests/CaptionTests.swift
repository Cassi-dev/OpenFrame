import CoreImage
import Foundation
import Testing
@testable import OpenFrameCore

/// Palavras com tempos sintéticos: ~0,3 s cada, 0,05 s entre elas e 0,5 s depois de . ? !
/// `|` no texto força uma pausa de 0,6 s.
func spokenWords(_ text: String, start: Micros = 0) -> [TranscribedWord] {
    var t = start
    var words: [TranscribedWord] = []
    for token in text.split(separator: " ") {
        if token == "|" {
            t += 600_000
            continue
        }
        let w = String(token)
        let end = t + 200_000 + Micros(w.count) * 20_000
        words.append(TranscribedWord(text: w, start: t, end: end, probability: 0.9))
        t = end + (CaptionBuilder.endsSentence(w) ? 500_000 : 50_000)
    }
    return words
}

@Suite("Legendas automáticas: modelo")
struct CaptionModelTests {
    @Test("Sem palavras, as chaves novas não são gravadas e projetos antigos abrem")
    func optionalKeys() throws {
        var p = Project()
        TimelineEditor.addText(TextContent(text: "Oi"), to: &p, at: 0)
        let json = String(decoding: try ProjectStore.encode(p), as: UTF8.self)
        // ("highlights" é do Ajustar.)
        #expect(!json.contains("\"words\"") && !json.contains("\"highlight\"") && !json.contains("isAutoCaptions"))
        #expect(try ProjectStore.decode(ProjectStore.encode(p)) == p)
    }

    @Test("Palavras, destaque e faixa automática vão e voltam no JSON")
    func roundTrip() throws {
        var p = Project()
        let cues = CaptionBuilder.cues(from: spokenWords("Olá mundo. Tudo bem com você?"), layout: .highlight)
        let track = CaptionBuilder.apply(cues, layout: .highlight, style: nil, to: &p, replacing: false)
        let back = try ProjectStore.decode(ProjectStore.encode(p))
        #expect(back == p)
        let t = try #require(back.tracks.first { $0.id == track })
        #expect(t.isAutoCaptions)
        #expect(t.segments.allSatisfy { $0.text?.words != nil && $0.text?.highlight != nil })
    }

    @Test("Destaque com campos faltando ou modo desconhecido usa o padrão")
    func tolerantHighlight() throws {
        let partial = try JSONDecoder().decode(WordHighlight.self, from: Data(#"{"scale": 1.3, "mode": "futuro"}"#.utf8))
        var expected = WordHighlight()
        expected.scale = 1.3
        #expect(partial == expected)
        let empty = try JSONDecoder().decode(WordHighlight.self, from: Data("{}".utf8))
        #expect(empty == WordHighlight())
    }

    @Test("O destaque só vale quando a contagem de palavras bate com o texto")
    func activeHighlight() {
        var c = TextContent(text: "um dois\ntrês")
        c.words = [CaptionWord(text: "um", start: 0, end: 1), CaptionWord(text: "dois", start: 1, end: 2),
                   CaptionWord(text: "três", start: 2, end: 3)]
        #expect(c.activeHighlight == nil) // sem `highlight`
        c.highlight = WordHighlight()
        #expect(c.activeHighlight?.words.count == 3)
        c.text = "um dois três quatro"
        #expect(c.activeHighlight == nil)
    }

    @Test("Texto novo não entra na faixa das legendas automáticas")
    func autoTrackIsReserved() {
        var p = Project()
        let cues = CaptionBuilder.cues(from: spokenWords("uma frase curta"), layout: .phrases)
        let auto = CaptionBuilder.apply(cues, layout: .phrases, style: nil, to: &p, replacing: false)
        let id = TimelineEditor.addText(TextContent(text: "Título"), to: &p, at: 10_000_000)
        #expect(p.tracks[p.locate(id)!.track].id != auto)
    }

    @Test("Aparar e dividir mantêm as palavras no mesmo instante da timeline")
    func editsKeepWordTimes() throws {
        var p = Project()
        let words = spokenWords("primeira segunda terceira quarta", start: 1_000_000)
        let cues = CaptionBuilder.cues(from: words, layout: .highlight)
        #expect(cues.count == 1)
        CaptionBuilder.apply(cues, layout: .highlight, style: nil, to: &p, replacing: false)
        let id = p.tracks.last!.segments[0].id
        func absolute(_ seg: Segment) -> [Micros] { seg.text!.words!.map { seg.targetStart + $0.start } }
        let original = absolute(p.segment(id)!)
        #expect(original == words.map(\.start))

        TimelineEditor.trimStart(&p, segment: id, to: 1_200_000)
        #expect(absolute(p.segment(id)!) == original)
        let right = try #require(TimelineEditor.split(&p, segment: id, at: words[2].start))
        #expect(absolute(p.segment(right)!) == original)
        #expect(absolute(p.segment(id)!) == original)
    }
}

@Suite("Legendas automáticas: quebra")
struct CaptionBuilderTests {
    let speech = """
    Olá, pessoal! Hoje eu vou mostrar para vocês como gerar legendas automáticas no editor, sem internet e sem \
    complicação. | Primeiro escolha o idioma da fala; depois escolha a precisão do modelo e o estilo que combina \
    com o seu vídeo. Pronto: as legendas aparecem na timeline, uma faixa só delas, e você pode editar cada uma \
    quando quiser.
    """

    func check(_ cues: [CaptionCue], layout: CaptionLayout, words: [TranscribedWord]) {
        let lim = CaptionBuilder.limits(layout)
        // Todas as palavras, na ordem, uma vez só.
        #expect(cues.flatMap(\.words).map(\.text) == words.map(\.text))
        for (k, cue) in cues.enumerated() {
            let lines = cue.text.split(separator: "\n")
            #expect(lines.count <= lim.lines, "\(cue.text)")
            for line in lines where cue.words.count > 1 { #expect(line.count <= lim.lineChars, "\(line)") }
            #expect(TextContent.words(of: cue.text).count == cue.words.count)
            #expect(cue.words.last!.end - cue.words.first!.start <= lim.maxDuration)
            #expect(cue.end > cue.start)
            if k + 1 < cues.count {
                let next = cues[k + 1]
                #expect(cue.end <= next.start, "sobreposição em \(k)")
                // Duração mínima, a não ser que a próxima comece antes.
                #expect(cue.end - cue.start >= CaptionBuilder.minDuration || cue.end == next.start)
                // Vãos curtos fechados.
                #expect(next.start - cue.end == 0 || next.start - cue.end >= CaptionBuilder.closeGap)
            }
        }
    }

    @Test("Frases: duas linhas equilibradas, até 42 caracteres e 5 s", arguments: CaptionLayout.allCases)
    func limitsRespected(layout: CaptionLayout) {
        let words = spokenWords(speech)
        let cues = CaptionBuilder.cues(from: words, layout: layout)
        #expect(cues.count > 2)
        check(cues, layout: layout, words: words)
    }

    @Test("Quebra nas pausas e na pontuação")
    func breaksAtPunctuation() {
        let cues = CaptionBuilder.cues(from: spokenWords(speech), layout: .phrases)
        let texts = cues.map { $0.text.replacingOccurrences(of: "\n", with: " ") }
        // O fim de frase com pausa sempre fecha uma legenda.
        #expect(texts.contains { $0.hasSuffix("complicação.") })
        #expect(texts.contains { $0.hasPrefix("Primeiro") })
        // A maior parte das legendas termina em pontuação ou pausa.
        let clean = cues.dropLast().filter { c in
            let last = c.words.last!.text
            return CaptionBuilder.endsSentence(last) || CaptionBuilder.endsClause(last)
        }
        #expect(clean.count * 2 >= cues.count - 1, "\(texts)")
    }

    @Test("Nenhuma linha termina em artigo ou preposição quando há outra opção")
    func noDanglingFunctionWords() {
        let cues = CaptionBuilder.cues(from: spokenWords(speech), layout: .phrases)
        for cue in cues {
            for line in cue.text.split(separator: "\n").dropLast() {
                let last = String(line.split(separator: " ").last!)
                #expect(!CaptionBuilder.isFunctionWord(last), "\(cue.text)")
            }
        }
        let ends = cues.dropLast().map { $0.words.last!.text }
        #expect(ends.filter(CaptionBuilder.isFunctionWord).isEmpty, "\(ends)")
    }

    @Test("As duas linhas ficam equilibradas")
    func balancedLines() {
        let words = spokenWords("este é um exemplo de legenda longa que precisa de duas linhas na tela")
        let cues = CaptionBuilder.cues(from: words, layout: .phrases)
        #expect(cues.count == 1)
        let lines = cues[0].text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(abs(lines[0].count - lines[1].count) <= 12, "\(lines)")
    }

    @Test("Impacto: de 1 a 4 palavras, quase sempre de 2 a 4")
    func punchWordCounts() {
        let cues = CaptionBuilder.cues(from: spokenWords(speech), layout: .punch)
        #expect(cues.allSatisfy { (1...4).contains($0.words.count) })
        let singles = cues.filter { $0.words.count == 1 }.count
        #expect(singles * 5 <= cues.count, "\(cues.map(\.text))")
    }

    @Test("Silêncio longo separa as legendas; legenda curta dura pelo menos 0,7 s sem invadir a próxima")
    func timing() {
        var words = spokenWords("Oi.")
        words += spokenWords("Tudo bem?", start: 3_000_000)
        let cues = CaptionBuilder.cues(from: words, layout: .phrases)
        #expect(cues.count == 2)
        #expect(cues[0].end - cues[0].start == CaptionBuilder.minDuration)

        // Próxima muito perto: estende só até ela.
        let close = [TranscribedWord(text: "Sim.", start: 0, end: 200_000),
                     TranscribedWord(text: "Não.", start: 2_000_000, end: 2_300_000),
                     TranscribedWord(text: "Talvez", start: 2_400_000, end: 2_600_000)]
        let c2 = CaptionBuilder.cues(from: close, layout: .punch)
        #expect(c2.first!.end == 700_000)
        for (a, b) in zip(c2, c2.dropFirst()) { #expect(a.end <= b.start) }
    }

    @Test("Pontuação solta vai para a palavra anterior; espaços somem")
    func normalizes() {
        let words = [TranscribedWord(text: " Olá", start: 0, end: 300_000),
                     TranscribedWord(text: ",", start: 300_000, end: 310_000),
                     TranscribedWord(text: " mundo", start: 400_000, end: 700_000),
                     TranscribedWord(text: "!", start: 700_000, end: 720_000),
                     TranscribedWord(text: "  ", start: 800_000, end: 900_000)]
        let cues = CaptionBuilder.cues(from: words, layout: .phrases)
        #expect(cues.map(\.text) == ["Olá, mundo!"])
        #expect(cues[0].words.map(\.text) == ["Olá,", "mundo!"])
        #expect(cues[0].words[1].end == 720_000)
        #expect(CaptionBuilder.cues(from: [], layout: .phrases).isEmpty)
    }

    @Test("Aplicar cria a faixa automática; substituir troca as legendas sem mexer no resto")
    func applyAndReplace() throws {
        var p = Project()
        let user = TimelineEditor.addText(TextContent(text: "Meu título"), to: &p, at: 0)
        let cues = CaptionBuilder.cues(from: spokenWords(speech), layout: .punch)
        let first = CaptionBuilder.apply(cues, layout: .punch, style: nil, to: &p, replacing: false)
        let track = try #require(p.tracks.first { $0.id == first })
        #expect(track.kind == .text && track.isAutoCaptions)
        #expect(track.segments.count == cues.count)
        let seg = track.segments[1]
        #expect(seg.targetStart == cues[1].start)
        #expect(seg.text!.words!.first!.start == cues[1].words[0].start - cues[1].start)
        #expect(seg.text!.highlight == nil)
        #expect(seg.text!.style == CaptionBuilder.defaultStyle(.punch))
        #expect(seg.animationIn?.kind == .elastic)

        // Substituir: mesma faixa, legendas novas; o texto do usuário continua.
        let again = CaptionBuilder.cues(from: spokenWords("outra fala"), layout: .highlight)
        var style = CaptionBuilder.defaultStyle(.highlight)
        style.color = RGBA(0, 1, 0)
        // A timeline inteira foi transcrita de novo.
        let second = CaptionBuilder.apply(again, layout: .highlight, style: style, to: &p, replacing: true,
                                          range: TimeRange(start: 0, duration: p.duration))
        #expect(second == first)
        #expect(p.tracks.filter(\.isAutoCaptions).count == 1)
        let replaced = p.tracks.first { $0.id == second }!
        #expect(replaced.segments.map { $0.text!.text } == again.map(\.text))
        #expect(replaced.segments[0].text!.highlight == WordHighlight())
        #expect(replaced.segments[0].text!.style.color == RGBA(0, 1, 0))
        #expect(p.segment(user) != nil)

        // Substituir só o trecho transcrito: as legendas de fora ficam.
        let late = CaptionBuilder.cues(from: spokenWords("mais tarde", start: 60_000_000), layout: .highlight)
        CaptionBuilder.apply(late, layout: .highlight, style: nil, to: &p, replacing: true,
                             range: TimeRange(start: 59_000_000, duration: 5_000_000))
        let both = p.tracks.first { $0.id == second }!.segments.map { $0.text!.text }
        #expect(both == again.map(\.text) + late.map(\.text))
        let lateAgain = CaptionBuilder.cues(from: spokenWords("de novo", start: 60_000_000), layout: .highlight)
        CaptionBuilder.apply(lateAgain, layout: .highlight, style: nil, to: &p, replacing: true,
                             range: TimeRange(start: 59_000_000, duration: 5_000_000))
        #expect(p.tracks.first { $0.id == second }!.segments.map { $0.text!.text } == again.map(\.text) + lateAgain.map(\.text))

        // Sem substituir: faixa nova.
        let third = CaptionBuilder.apply(again, layout: .phrases, style: nil, to: &p, replacing: false)
        #expect(third != first)
        #expect(p.tracks.filter(\.isAutoCaptions).count == 2)
    }

    @Test("Layouts: nomes e estilos")
    func layouts() {
        #expect(CaptionLayout.allCases.map(\.displayName) == ["Frases", "Destaque", "Impacto"])
        #expect(CaptionBuilder.defaultStyle(.punch).fontSize > CaptionBuilder.defaultStyle(.phrases).fontSize)
        #expect(CaptionBuilder.defaultStyle(.punch).y == 0)
        #expect(CaptionBuilder.defaultStyle(.phrases).y < -0.5)
    }
}

@Suite("Legendas automáticas: destaque da palavra")
struct WordHighlightRenderTests {
    let size = CGSize(width: 640, height: 360)

    /// Três palavras de 1 s cada, a partir de 0.
    func project(text: String = "MAR SOL CEU", _ change: (inout WordHighlight) -> Void = { _ in },
                 segment: (inout Segment) -> Void = { _ in }) -> Project {
        var p = Project()
        p.canvas.aspect = .r16x9
        var style = TextStyle()
        style.y = 0
        style.fontSize = 0.16
        style.shadow = false
        var content = TextContent(text: text, style: style)
        content.words = (0..<3).map { CaptionWord(text: "w\($0)", start: Micros($0) * 1_000_000, end: Micros($0 + 1) * 1_000_000 - 100_000) }
        var h = WordHighlight()
        change(&h)
        content.highlight = h
        let id = TimelineEditor.addText(content, to: &p, at: 0, duration: 3_000_000)
        TimelineEditor.update(&p, segment: id, segment)
        return p
    }

    func render(_ p: Project, at t: Micros) -> Bitmap {
        Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: t) { _ in nil }, size: size)
    }

    /// Pixels que passam no teste e a média de x deles (0...1).
    func pixels(_ b: Bitmap, _ test: (Int, Int, Int) -> Bool) -> (count: Int, meanX: Double) {
        var count = 0
        var sum = 0
        for y in 0..<b.height {
            for x in 0..<b.width {
                let i = (y * b.width + x) * 4
                if test(Int(b.data[i]), Int(b.data[i + 1]), Int(b.data[i + 2])) {
                    count += 1
                    sum += x
                }
            }
        }
        return (count, count > 0 ? Double(sum) / Double(count) / Double(b.width) : 0)
    }

    func yellow(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && g > 160 && b < 90 }
    func blue(_ r: Int, _ g: Int, _ b: Int) -> Bool { b > 200 && r < 90 }

    func inkRows(_ b: Bitmap) -> Int {
        (0..<b.height).filter { y in (0..<b.width).contains { x in b.data[(y * b.width + x) * 4] > 128 } }.count
    }

    @Test("A cor segue a palavra falada")
    func colorFollowsWord() {
        let p = project()
        let a = pixels(render(p, at: 500_000), yellow)
        let b = pixels(render(p, at: 1_500_000), yellow)
        let c = pixels(render(p, at: 2_500_000), yellow)
        #expect(a.count > 200 && b.count > 200 && c.count > 200)
        #expect(a.meanX < 0.42 && (0.44...0.56).contains(b.meanX) && c.meanX > 0.58, "\(a) \(b) \(c)")
        // No vão depois do fim da palavra (0,9 s a 1 s), a anterior continua destacada.
        #expect(pixels(render(p, at: 950_000), yellow).meanX < 0.42)
    }

    @Test("Modo progressivo deixa as já faladas destacadas")
    func progressive() {
        let p = project { $0.mode = .progressive }
        let current = pixels(render(project(), at: 2_500_000), yellow)
        let progressive = pixels(render(p, at: 2_500_000), yellow)
        #expect(progressive.count > current.count * 2)
        #expect((0.44...0.56).contains(progressive.meanX))
    }

    @Test("A palavra atual cresce e a pílula aparece atrás dela")
    func scaleAndPill() {
        let still = project { $0.scale = 1 }
        let grown = project { $0.scale = 1.4 }
        #expect(inkRows(render(grown, at: 1_500_000)) > inkRows(render(still, at: 1_500_000)) + 8)

        #expect(pixels(render(project(), at: 1_500_000), blue).count == 0)
        let pill = pixels(render(project { $0.backgroundEnabled = true }, at: 1_500_000), blue)
        #expect(pill.count > 500)
        #expect((0.44...0.56).contains(pill.meanX))
    }

    @Test("Antes da primeira palavra e com contagem diferente, nada é destacado")
    func inactive() {
        var p = project()
        p.tracks[p.tracks.count - 1].segments[0].text!.words![0].start = 400_000
        #expect(pixels(render(p, at: 100_000), yellow).count == 0)
        let mismatch = project(text: "MAR SOL CEU AZUL")
        #expect(pixels(render(mismatch, at: 1_500_000), yellow).count == 0)
    }

    @Test("Transição suave de ~80 ms entre palavras")
    func smoothTransition() {
        let words = [CaptionWord(text: "a", start: 0, end: 900_000), CaptionWord(text: "b", start: 1_000_000, end: 2_000_000)]
        func at(_ t: Micros) -> [Double] { TextMotion.highlightAmounts(words, mode: .current, local: t).emphasis }
        #expect(at(-50_000) == [0, 0])
        #expect(at(40_000) == [1, 0])
        #expect(at(950_000) == [1, 0])
        let mid = at(1_000_000)
        #expect(abs(mid[0] - 0.5) < 1e-9 && abs(mid[1] - 0.5) < 1e-9)
        #expect(at(1_040_000) == [0, 1])
        let progressive = TextMotion.highlightAmounts(words, mode: .progressive, local: 1_500_000)
        #expect(progressive.color == [1, 1] && progressive.emphasis == [0, 1])
    }

    @Test("Funciona junto com entrada, saída e loop", arguments: [AnimationKind.cascade, .wordByWord, .maskReveal, .fade])
    func withAnimations(kind: AnimationKind) {
        let p = project(segment: {
            $0.animationIn = SegmentAnimation(kind: kind, duration: 600_000)
            $0.animationOut = SegmentAnimation(kind: .cascade, duration: 600_000)
            $0.animationLoop = LoopAnimation(kind: .pulse)
        })
        // No meio da entrada, já com a primeira palavra destacada.
        let entering = pixels(render(p, at: 300_000), yellow)
        #expect(entering.count > 0)
        // Em repouso, igual ao destaque sem animações (a menos do pulsar).
        let rest = pixels(render(p, at: 1_500_000), yellow)
        #expect((0.42...0.58).contains(rest.meanX))
        // No começo da saída, a última palavra.
        #expect(pixels(render(p, at: 2_450_000), yellow).meanX > 0.55)
    }

    @Test("O texto destacado é rasterizado na escala do destaque")
    func peakIncludesHighlight() {
        let p = project { $0.scale = 1.3 }
        #expect(Animations.peakScale(for: p.tracks.last!.segments[0]) == 1.3)
        #expect(Animations.usesUnits(p.tracks.last!.segments[0]))
    }
}

@Suite("Legendas automáticas: modelos")
struct ModelStoreTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenFrameModels-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Catálogo: nomes, tamanhos e endereços")
    func catalog() {
        #expect(WhisperModel.allCases.map(\.displayName) == ["Rápido", "Equilibrado", "Máxima precisão"])
        for m in WhisperModel.allCases {
            #expect(m.sha256.count == 64)
            #expect(m.byteSize > 100_000_000)
            #expect(m.downloadURL.host == "huggingface.co")
            #expect(m.downloadURL.lastPathComponent == m.fileName)
        }
    }

    @Test("Baixa, confere o sha256 e só então instala")
    func downloadVerifies() async throws {
        let dir = tempDir()
        let payload = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let source = dir.appendingPathComponent("origem.bin")
        try payload.write(to: source)
        let store = ModelStore(directory: dir.appendingPathComponent("Models"))
        let dest = store.directory.appendingPathComponent("modelo.bin")
        let sha = try ModelStore.sha256(of: source)

        // Hash errado: nada fica instalado.
        await #expect(throws: ModelStoreError.checksumMismatch) {
            try await store.download(from: source, to: dest, size: Int64(payload.count), sha256: String(repeating: "0", count: 64)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))

        let reports = Reports()
        try await store.download(from: source, to: dest, size: Int64(payload.count), sha256: sha) { reports.add($0) }
        #expect(try Data(contentsOf: dest) == payload)
        #expect(reports.values.last == 1)
        #expect(!FileManager.default.fileExists(atPath: store.partialURL(dest).path))

        // Tamanho diferente do anunciado.
        await #expect(throws: ModelStoreError.sizeMismatch(expected: 10, got: Int64(payload.count))) {
            try await store.download(from: source, to: dir.appendingPathComponent("x.bin"), size: 10, sha256: sha) { _ in }
        }
    }

    @Test("Instalado e apagar")
    func installedAndDelete() throws {
        let store = ModelStore(directory: tempDir())
        #expect(!store.isInstalled(.base))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        // Arquivo com o tamanho errado não conta como instalado.
        try Data(count: 10).write(to: store.url(for: .base))
        #expect(!store.isInstalled(.base))
        try store.delete(.base)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: .base).path))
        #expect(store.url(for: .turbo).lastPathComponent == "ggml-large-v3-turbo-q5_0.bin")
    }

    @Test("Idiomas e erros da transcrição")
    func transcriberBasics() async throws {
        #expect(Transcriber.languages.first?.code == "pt")
        #expect(Set(Transcriber.languages.map(\.code)).isSuperset(of: ["pt", "en", "es", "fr", "de", "it", "ja", "ko", "zh"]))
        #expect(throws: TranscriptionError.noAudio) { try Transcriber.sourceRange(project: Project(), source: .timeline) }
        #expect(throws: TranscriptionError.noAudio) {
            try Transcriber.sourceRange(project: Project(), source: .segment(UUID()))
        }
        let reports = Reports()
        let words = try await Transcriber.fakeWords(in: TimeRange(start: 1_000_000, duration: 10_000_000)) { reports.add($0.overall) }
        #expect(words.count > 15)
        #expect(reports.values.last == 1 && reports.values == reports.values.sorted())
        #expect(TranscriptionProgress(phase: .mixing, fraction: 1).overall == TranscriptionProgress.mixingWeight)
        #expect(TranscriptionProgress(phase: .transcribing, fraction: 0.5).overall == 0.55)
        #expect(words.allSatisfy { $0.start >= 1_000_000 && $0.end <= 11_000_000 && $0.end > $0.start })
    }
}

final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Double] = []
    func add(_ v: Double) { lock.lock(); list.append(v); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return list }
}
