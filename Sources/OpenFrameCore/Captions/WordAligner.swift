import Foundation

/// Ajusta os tempos das palavras pela energia do áudio. Os tempos do Whisper (DTW) acertam a
/// ordem e a região, mas chegam atrasados (~0,3 s no `say`) e não enxergam as pausas. Aqui cada
/// fronteira entre palavras escolhe um candidato perto da estimativa: uma pausa (a anterior
/// termina onde ela começa e a seguinte começa onde ela acaba) ou um vale de energia. A escolha é
/// feita em conjunto (programação dinâmica), pesando a distância à estimativa e a duração de cada
/// palavra contra o número de letras dela.
enum WordAligner {
    static let hop = 0.01
    static let window = 0.02
    /// Atraso típico do DTW e a dispersão aceita em torno dele.
    static let bias = 0.3
    static let spread = 0.4
    /// Janela de busca de cada fronteira em torno da estimativa.
    static let before = 0.9
    static let after = 0.3
    static let minWord = 0.05

    /// Energia (dB) por quadro de 10 ms.
    static func energy(_ samples: [Float], sampleRate: Double) -> [Double] {
        let hopN = Int(hop * sampleRate)
        let winN = Int(window * sampleRate)
        guard hopN > 0, samples.count >= winN else { return [] }
        let frames = (samples.count - winN) / hopN + 1
        var out = [Double](repeating: -100, count: frames)
        samples.withUnsafeBufferPointer { s in
            for f in 0..<frames {
                var sum: Float = 0
                let base = f * hopN
                for i in 0..<winN { sum += s[base + i] * s[base + i] }
                out[f] = 10 * log10(Double(sum) / Double(winN) + 1e-10)
            }
        }
        return out
    }

    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        return sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))]
    }

    /// Uma opção de fronteira: a palavra anterior termina em `end` e a seguinte começa em `start`.
    struct Candidate {
        var end: Double
        var start: Double
        var cost: Double
    }

    /// `words` com tempos em segundos desde a amostra 0.
    static func refine(_ words: [WhisperEngine.Word], samples: [Float], sampleRate: Double) -> [WhisperEngine.Word] {
        guard !words.isEmpty else { return words }
        let e = energy(samples, sampleRate: sampleRate)
        guard e.count > 10 else { return words }
        let floor = percentile(e, 0.1)
        let level = percentile(e, 0.9)
        // Sem contraste entre fala e fundo (música alta, ruído), os vales não querem dizer nada.
        guard level - floor > 12 else { return words }
        let silence = floor + 0.3 * (level - floor)
        let lastFrame = e.count - 1
        func frame(_ t: Double) -> Int { min(lastFrame, max(0, Int((t / hop).rounded()))) }
        // Centro do quadro.
        func time(_ f: Int) -> Double { Double(f) * hop + window / 2 }
        let quiet = e.map { $0 < silence }

        // Pausas: trechos contínuos de silêncio.
        var pauses: [(a: Int, b: Int)] = []
        var f = 0
        while f <= lastFrame {
            if quiet[f] {
                var g = f
                while g < lastFrame, quiet[g + 1] { g += 1 }
                pauses.append((f, g))
                f = g + 1
            } else {
                f += 1
            }
        }

        // Ritmo da fala: segundos com voz por letra, no trecho das palavras.
        let letters = words.map { max(1, $0.text.filter(\.isLetter).count) }
        let span = frame(max(0, words[0].start - 0.5))...frame(words[words.count - 1].end + 0.5)
        let voiced = Double(span.filter { !quiet[$0] }.count) * hop
        let perLetter = min(0.2, max(0.04, voiced / Double(letters.reduce(0, +))))
        func durationCost(_ d: Double, word: Int) -> Double {
            guard d >= minWord else { return .infinity }
            let expected = perLetter * Double(letters[word]) + 0.05
            let x = log(d / expected) / 0.6
            return x * x
        }

        // Início da primeira: a primeira voz depois de um silêncio, perto da estimativa.
        let firstStart: Double = {
            let lo = frame(words[0].start - before)
            let hi = frame(words[0].start + after)
            guard lo < hi else { return words[0].start }
            return (lo...hi).first(where: { !quiet[$0] }).map(time) ?? words[0].start
        }()
        // Fim da última: a última voz antes do fim estimado (com folga).
        let n = words.count
        let lastEnd: Double = {
            let lo = frame(words[n - 1].start)
            let hi = frame(words[n - 1].end + 0.4)
            guard lo < hi else { return words[n - 1].end }
            return (lo...hi).reversed().first(where: { !quiet[$0] }).map { time($0) } ?? words[n - 1].end
        }()

        // Candidatos de cada fronteira i (início da palavra i, i ≥ 1).
        func position(_ t: Double, _ rough: Double) -> Double {
            let x = (t - (rough - bias)) / spread
            return x * x
        }
        var candidates: [[Candidate]] = [[Candidate(end: firstStart, start: firstStart, cost: 0)]]
        for i in 1..<max(n, 1) where n > 1 {
            let rough = words[i].start
            let lo = frame(rough - before)
            let hi = frame(rough + after)
            var list = [Candidate(end: rough, start: rough, cost: 2.5)]
            for p in pauses where p.b >= lo && p.a <= hi && p.a > 0 {
                list.append(Candidate(end: time(p.a), start: time(p.b), cost: position(time(p.b), rough)))
            }
            // Vales de energia sem silêncio (fala emendada).
            if lo + 2 < hi {
                for g in (lo + 1)..<hi where !quiet[g] && e[g] < e[g - 1] && e[g] <= e[g + 1] {
                    let depth = (min(e[max(lo, g - 8)...g].max()!, e[g...min(hi, g + 8)].max()!) - e[g]) / 6
                    guard depth > 0.3 else { continue }
                    list.append(Candidate(end: time(g), start: time(g), cost: 1 + 1 / depth + position(time(g), rough)))
                }
            }
            candidates.append(list)
        }

        // Programação dinâmica: custo da fronteira + duração da palavra entre duas fronteiras.
        var best = [[Double]](repeating: [], count: candidates.count)
        var back = [[Int]](repeating: [], count: candidates.count)
        best[0] = [0]
        back[0] = [0]
        for i in 1..<candidates.count {
            best[i] = [Double](repeating: .infinity, count: candidates[i].count)
            back[i] = [Int](repeating: 0, count: candidates[i].count)
            for (c, cand) in candidates[i].enumerated() {
                for (k, prev) in candidates[i - 1].enumerated() where best[i - 1][k] < .infinity {
                    let total = best[i - 1][k] + cand.cost + durationCost(cand.end - prev.start, word: i - 1)
                    if total < best[i][c] {
                        best[i][c] = total
                        back[i][c] = k
                    }
                }
            }
        }
        let lastIndex = candidates.count - 1
        var pick = best[lastIndex].indices.min {
            best[lastIndex][$0] + durationCost(lastEnd - candidates[lastIndex][$0].start, word: lastIndex)
                < best[lastIndex][$1] + durationCost(lastEnd - candidates[lastIndex][$1].start, word: lastIndex)
        } ?? 0
        guard best[lastIndex][pick] < .infinity else { return words }
        var chosen = [Candidate](repeating: candidates[0][0], count: candidates.count)
        for i in stride(from: lastIndex, through: 0, by: -1) {
            chosen[i] = candidates[i][pick]
            pick = back[i][pick]
        }

        var out = words
        for i in out.indices {
            out[i].start = chosen[i].start
            out[i].end = i + 1 < out.count ? chosen[i + 1].end : max(lastEnd, chosen[i].start + minWord)
            out[i].end = max(out[i].end, out[i].start)
        }
        return out
    }
}
