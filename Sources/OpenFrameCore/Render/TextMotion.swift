import CoreImage
import CoreText
import Foundation

/// Unidade das animações de texto por partes.
enum TextGranularity: String, Sendable {
    case letter, word, line
}

/// Uma letra, palavra ou linha desenhada à parte, nas coordenadas da imagem do texto
/// (as mesmas da imagem estática, com as margens).
struct TextUnit {
    /// Preenchimento (com sublinhado, negrito sintético e emoji) e contorno, já posicionados.
    let fill: CIImage
    let stroke: CIImage?
    let bounds: CGRect
    /// Primeiro caractere da unidade (para a máquina de escrever).
    let character: Int
    let line: Int
    /// Centro da linha da unidade (animação "espaçamento").
    let lineCenterX: CGFloat
    /// Centro e largura da célula da letra e linha de base (animação "decodificar").
    let cellCenterX: CGFloat
    let cellWidth: CGFloat
    let baseline: CGFloat
}

/// Sprites de um texto quebrado em unidades, guardados em cache por conteúdo, canvas e granularidade.
final class TextUnits: @unchecked Sendable {
    let size: CGSize
    let units: [TextUnit]
    /// Faixa vertical de cada linha (com o contorno), para o recorte do "revelar por máscara".
    let lineBands: [CGRect]
    let background: CIImage?
    let style: TextStyle
    let fontPx: CGFloat
    let shadowOffset: CGSize
    let shadowBlur: CGFloat
    let characterCount: Int

    init(size: CGSize, units: [TextUnit], lineBands: [CGRect], background: CIImage?, style: TextStyle,
         fontPx: CGFloat, shadowOffset: CGSize, shadowBlur: CGFloat, characterCount: Int) {
        self.size = size
        self.units = units
        self.lineBands = lineBands
        self.background = background
        self.style = style
        self.fontPx = fontPx
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
        self.characterCount = characterCount
    }
}

/// Glifo avulso do "decodificar", com a origem na linha de base e no começo do avanço.
struct ScrambleGlyph {
    let fill: CIImage
    let stroke: CIImage?
    let advance: CGFloat
}

final class ScrambleSet {
    let glyphs: [ScrambleGlyph]
    init(_ glyphs: [ScrambleGlyph]) { self.glyphs = glyphs }
}

extension TextRenderer {
    static let scrambleCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&*@$")

    func units(for content: TextContent, canvas: CGSize, granularity: TextGranularity) -> TextUnits? {
        let text = Self.cased(content.text, content.style.textCase)
        guard !text.isEmpty, canvas.height > 0 else { return nil }
        let key = "\(content.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))|\(granularity.rawValue)" as NSString
        if let cached = unitCache.object(forKey: key) { return cached }
        guard let built = buildUnits(text, style: content.style, canvas: canvas, granularity: granularity) else { return nil }
        unitCache.setObject(built, forKey: key)
        return built
    }

    private func buildUnits(_ text: String, style: TextStyle, canvas: CGSize, granularity: TextGranularity) -> TextUnits? {
        let l = layout(text, style: style, canvas: canvas)
        let m = metrics(l, style: style)
        let (glyphs, lines) = glyphInfo(l, text: text as NSString, style: style)

        // Caractere (grafema) e palavra de cada posição UTF-16.
        var characterAt = [Int](repeating: 0, count: text.utf16.count + 1)
        var wordOf: [Int] = []
        var word = -1
        var previousBlank = true
        for (c, index) in text.indices.enumerated() {
            let start = index.utf16Offset(in: text)
            let end = text.index(after: index).utf16Offset(in: text)
            for u in start..<end { characterAt[u] = c }
            let blank = text[index].isWhitespace
            if !blank, previousBlank { word += 1 }
            wordOf.append(blank ? -1 : word)
            previousBlank = blank
        }

        func unitKey(_ g: GlyphInfo) -> Int {
            switch granularity {
            case .letter: characterAt[g.utf16]
            case .word: wordOf[characterAt[g.utf16]]
            case .line: g.line
            }
        }

        // Glifos de cada unidade, em ordem de texto.
        var order: [Int] = []
        var members: [Int: [GlyphInfo]] = [:]
        for g in glyphs where !g.blank {
            let k = unitKey(g)
            if members[k] == nil { order.append(k) }
            members[k, default: []].append(g)
        }
        order.sort()

        // Extensão de cada linha e sublinhado: cada unidade leva o trecho até a próxima da mesma linha.
        var lineMin = [CGFloat](repeating: .infinity, count: lines.count)
        var lineMax = [CGFloat](repeating: -.infinity, count: lines.count)
        for g in glyphs where !g.blank {
            lineMin[g.line] = min(lineMin[g.line], g.position.x)
            lineMax[g.line] = max(lineMax[g.line], g.position.x + g.advance - l.kern)
        }
        var underlines: [Int: [CGRect]] = [:]
        if style.underline {
            for line in lines.indices where lineMax[line] > lineMin[line] {
                let starts = order.compactMap { k -> (Int, CGFloat)? in
                    members[k]!.filter { $0.line == line }.map(\.position.x).min().map { (k, $0) }
                }.sorted { $0.1 < $1.1 }
                // Emendas em pixel inteiro (a margem é inteira): sem fresta de antisserrilhado entre os trechos.
                let joins = starts.map { $0.1.rounded() }
                for (j, (k, start)) in starts.enumerated() {
                    let x = j == 0 ? start : joins[j]
                    let end = j + 1 < starts.count ? joins[j + 1] : lineMax[line]
                    guard end > x else { continue }
                    underlines[k, default: []].append(underlineRect(lines[line], from: x, to: end, fontPx: l.fontPx))
                }
            }
        }

        let pad = CGPoint(x: m.padX, y: m.padY)
        let outset = m.strokeOut + (l.face.syntheticBold ? Self.syntheticBold * l.fontPx : 0) + 2
        var units: [TextUnit] = []
        for k in order {
            let group = members[k]!
            let shapes = makeShapes(group, underlines: underlines[k] ?? [], face: l.face)
            guard !shapes.bounds.isNull else { continue }
            let box = shapes.bounds.insetBy(dx: -outset, dy: -outset).integral
            guard let fill = sprite(shapes, box: box, pad: pad, style: style, l, m, stroke: false) else { continue }
            let stroke = m.strokeOut > 0 ? sprite(shapes, box: box, pad: pad, style: style, l, m, stroke: true) : nil
            let first = group[0]
            let line = first.line
            units.append(TextUnit(fill: fill, stroke: stroke, bounds: box.offsetBy(dx: pad.x, dy: pad.y),
                                  character: characterAt[first.utf16], line: line,
                                  lineCenterX: (lineMin[line] + lineMax[line]) / 2 + pad.x,
                                  cellCenterX: first.position.x + (first.advance - l.kern) / 2 + pad.x,
                                  cellWidth: first.advance - l.kern,
                                  baseline: lines[line].origin.y + pad.y))
        }

        let below = max(0.17 * l.fontPx, 0)
        let bands = lines.map { line in
            let bottom = line.origin.y - max(line.descent, below) - outset
            let top = line.origin.y + line.ascent + outset
            return CGRect(x: 0, y: bottom + pad.y, width: CGFloat(m.width), height: top - bottom)
        }

        var background: CIImage?
        if style.backgroundEnabled, let ctx = Self.bitmap(width: m.width, height: m.height) {
            ctx.translateBy(x: m.padX, y: m.padY)
            ctx.setFillColor(style.backgroundColor.cgColor)
            ctx.addPath(backgroundPath(l, m, style: style))
            ctx.fillPath()
            background = ctx.makeImage().map(Self.gammaImage)
        }
        return TextUnits(size: CGSize(width: m.width, height: m.height), units: units, lineBands: bands,
                         background: background, style: style, fontPx: l.fontPx,
                         shadowOffset: m.shadowOffset, shadowBlur: m.shadowBlur, characterCount: text.count)
    }

    /// Desenha as formas recortadas em `box` (coordenadas da caixa de texto) e devolve a imagem
    /// já na posição da imagem do texto.
    private func sprite(_ shapes: Shapes, box: CGRect, pad: CGPoint, style: TextStyle, _ l: Layout, _ m: Metrics,
                        stroke: Bool) -> CIImage? {
        guard let ctx = Self.bitmap(width: Int(box.width), height: Int(box.height)) else { return nil }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        draw(shapes, in: ctx, style: style, l, m, stroke: stroke, fill: !stroke)
        guard let cg = ctx.makeImage() else { return nil }
        return Self.gammaImage(cg).transformed(by: CGAffineTransform(translationX: box.minX + pad.x, y: box.minY + pad.y))
    }

    /// Sprites sem gerência de cor: os valores sRGB ficam como estão e a composição por unidade
    /// mistura em sRGB, como o Core Graphics no desenho estático (bordas e sombra iguais).
    /// `TextMotion.image` converte para linear no fim.
    static func gammaImage(_ cg: CGImage) -> CIImage {
        CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
    }

    /// Glifos do conjunto do "decodificar" no estilo do texto.
    func scrambleGlyphs(style: TextStyle, canvas: CGSize) -> [ScrambleGlyph] {
        let key = "\(style.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))" as NSString
        if let cached = scrambleCache.object(forKey: key) { return cached.glyphs }
        let l = layout("A", style: style, canvas: canvas)
        let m = metrics(l, style: style)
        let outset = m.strokeOut + (l.face.syntheticBold ? Self.syntheticBold * l.fontPx : 0) + 2
        var result: [ScrambleGlyph] = []
        for ch in Self.scrambleCharacters {
            var unit = Array(String(ch).utf16)
            var glyph: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(l.face.font, &unit, &glyph, 1), glyph != 0 else { continue }
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(l.face.font, .default, &glyph, &advance, 1)
            let info = GlyphInfo(glyph: glyph, font: l.face.font, isColor: false, position: .zero,
                                 advance: advance.width, utf16: 0, line: 0, blank: false)
            let shapes = makeShapes([info], underlines: [], face: l.face)
            guard !shapes.bounds.isNull else { continue }
            let box = shapes.bounds.insetBy(dx: -outset, dy: -outset).integral
            guard let fill = sprite(shapes, box: box, pad: .zero, style: style, l, m, stroke: false) else { continue }
            let stroke = m.strokeOut > 0 ? sprite(shapes, box: box, pad: .zero, style: style, l, m, stroke: true) : nil
            result.append(ScrambleGlyph(fill: fill, stroke: stroke, advance: advance.width))
        }
        scrambleCache.setObject(ScrambleSet(result), forKey: key)
        return result
    }
}

/// Composição por quadro das animações de texto por unidade. Os sprites vêm prontos do
/// cache; aqui só entram deslocamento, escala, alfa, desfoque e recorte no Core Image.
/// A sombra sai uma vez, do conjunto, como no desenho estático.
enum TextMotion {
    /// Pose de uma unidade num instante.
    struct Pose {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var scale: CGFloat = 1
        var alpha: Double = 1
        var blur: CGFloat = 0
        var clip: CGRect?
        var scramble = false
    }

    /// Fração do tempo da animação em que cada unidade anima (com uma unidade só, o tempo todo).
    static func window(_ kind: AnimationKind) -> Double {
        switch kind {
        case .cascade: 0.45
        case .elastic: 0.5
        case .wave: 0.35
        case .wordByWord: 0.55
        case .maskReveal: 0.7
        case .tracking: 1
        case .decode: 0.5
        default: 1
        }
    }

    /// Progresso da unidade `i` de `n`: a janela de largura `w` começa em `(1-w)·i/(n-1)`.
    static func unitProgress(_ p: Double, index i: Int, count n: Int, window w: Double) -> Double {
        guard n > 1, w < 1 else { return Animations.clamp(p) }
        let start = (1 - w) * Double(i) / Double(n - 1)
        return Animations.clamp((p - start) / w)
    }

    static func pose(_ kind: AnimationKind, q: Double, exiting: Bool, unit: TextUnit, band: CGRect?, em: CGFloat) -> Pose {
        var pose = Pose()
        // Entrando, as unidades vêm de baixo; saindo, continuam subindo.
        let up: CGFloat = exiting ? 1 : -1
        switch kind {
        case .cascade:
            let e = Animations.expoOut(q)
            pose.dy = up * CGFloat(1 - e) * 0.6 * em
            pose.blur = CGFloat(1 - e) * 0.25 * em
            pose.alpha = e
        case .elastic:
            pose.scale = CGFloat(0.3 + 0.7 * Animations.spring(q))
            pose.dy = up * CGFloat(1 - Animations.quartOut(q)) * 0.25 * em
            pose.alpha = Animations.quartOut(min(1, q * 3))
        case .wave:
            let hop = sin(q * .pi)
            pose.dy = CGFloat(hop) * 0.35 * em
            pose.scale = 1 + CGFloat(hop) * 0.12
            pose.alpha = Animations.quartOut(min(1, q * 2.5))
        case .wordByWord:
            let e = Animations.expoOut(q)
            pose.dy = up * CGFloat(1 - e) * 0.45 * em
            pose.blur = CGFloat(1 - e) * 0.12 * em
            pose.alpha = e
        case .maskReveal:
            let e = Animations.quintOut(q)
            let travel = (band?.height ?? em) * 1.1
            pose.dy = up * CGFloat(1 - e) * travel
            pose.clip = band
        case .tracking:
            let e = Animations.quartOut(q)
            pose.dx = (unit.bounds.midX - unit.lineCenterX) * 0.6 * CGFloat(1 - e)
            pose.alpha = e
        case .decode:
            pose.alpha = Animations.quartOut(min(1, q * 3))
            pose.scramble = q < 1
        default:
            break
        }
        return pose
    }

    /// Índices dos glifos sorteáveis para uma célula: os que cabem com até 30% de folga; se forem
    /// menos de 4, os 4 de largura mais próxima. A ordem segue a do conjunto (determinístico).
    static func scrambleCandidates(_ glyphs: [ScrambleGlyph], cellWidth: CGFloat) -> [Int] {
        let fitting = glyphs.indices.filter { glyphs[$0].advance <= cellWidth * 1.3 }
        if fitting.count >= 4 { return fitting }
        let nearest = glyphs.indices.sorted {
            (abs(glyphs[$0].advance - cellWidth), $0) < (abs(glyphs[$1].advance - cellWidth), $1)
        }
        return Array(nearest.prefix(4)).sorted()
    }

    /// Caractere aleatório determinístico da unidade `index` no passo de tempo `step` (~20 trocas/s).
    static func scrambleIndex(index: Int, step: Int, count: Int) -> Int {
        var z = UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(step)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % UInt64(max(count, 1)))
    }

    /// Imagem do texto no instante, com o mesmo tamanho nominal (e o mesmo centro) da estática.
    static func image(_ content: TextContent, canvas: CGSize, state: AnimationState,
                      granularity: TextGranularity) -> (image: CIImage, size: CGSize)? {
        guard let set = TextRenderer.shared.units(for: content, canvas: canvas, granularity: granularity) else { return nil }
        let em = set.fontPx
        let visible = state.reveal >= 1 ? Int.max : Int((Double(set.characterCount) * state.reveal).rounded(.up))
        let step = Int(Double(state.local) / 50_000)
        var scramble: [ScrambleGlyph] = []
        if state.unit?.kind == .decode {
            scramble = TextRenderer.shared.scrambleGlyphs(style: content.style, canvas: canvas)
        }

        var strokes = CIImage.empty()
        var fills = CIImage.empty()
        let n = set.units.count
        for (i, unit) in set.units.enumerated() where unit.character < visible {
            var pose = Pose()
            if let u = state.unit {
                let q = unitProgress(u.progress, index: i, count: n, window: window(u.kind))
                let band = set.lineBands.indices.contains(unit.line) ? set.lineBands[unit.line] : nil
                pose = self.pose(u.kind, q: q, exiting: u.exiting, unit: unit, band: band, em: em)
            }
            guard pose.alpha > 0.001 else { continue }
            var fill = unit.fill
            var stroke = unit.stroke
            if pose.scramble, !scramble.isEmpty {
                // Mesmo tamanho de fonte e mesma linha de base da letra, centralizado na célula.
                // O sorteio só usa glifos de largura parecida, para não encavalar nas vizinhas.
                let pool = scrambleCandidates(scramble, cellWidth: unit.cellWidth)
                let g = scramble[pool[scrambleIndex(index: i, step: step, count: pool.count)]]
                let move = CGAffineTransform(translationX: unit.cellCenterX - g.advance / 2, y: unit.baseline)
                fill = g.fill.transformed(by: move)
                stroke = g.stroke?.transformed(by: move)
            }
            func posed(_ img: CIImage) -> CIImage {
                var out = img
                if pose.scale != 1 || pose.dx != 0 || pose.dy != 0 {
                    let c = CGPoint(x: unit.bounds.midX, y: unit.bounds.midY)
                    out = out.transformed(by: CGAffineTransform(translationX: -c.x, y: -c.y)
                        .concatenating(CGAffineTransform(scaleX: max(pose.scale, 0.001), y: max(pose.scale, 0.001)))
                        .concatenating(CGAffineTransform(translationX: c.x + pose.dx, y: c.y + pose.dy)))
                }
                if pose.blur > 0.3 { out = out.applyingGaussianBlur(sigma: Double(pose.blur)) }
                if let clip = pose.clip { out = out.cropped(to: clip) }
                return alpha(out, pose.alpha)
            }
            fills = posed(fill).composited(over: fills)
            if let stroke { strokes = posed(stroke).composited(over: strokes) }
        }
        let glyphs = fills.composited(over: strokes)
        let rect = CGRect(origin: .zero, size: set.size)

        // Loops que dependem das letras separadas da sombra (a sombra sai só das letras).
        let k = canvas.height
        var out = glyphs
        if let shine = state.shine { out = applyShine(out, in: rect, position: shine.position, strength: shine.strength) }
        if state.glow > 0 { out = applyGlow(out, amount: state.glow, sigma: 0.012 * k) }
        let style = set.style
        if style.shadow, style.shadowColor.a > 0 {
            let c = style.shadowColor
            var shadow = glyphs.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: c.a),
                "inputBiasVector": CIVector(x: c.r, y: c.g, z: c.b, w: 0),
            ])
            // O `blur` da sombra do Core Graphics equivale a um desvio-padrão de ~metade dele.
            if set.shadowBlur > 0.5 { shadow = shadow.applyingGaussianBlur(sigma: Double(set.shadowBlur) / 2) }
            shadow = shadow.transformed(by: CGAffineTransform(translationX: set.shadowOffset.width, y: set.shadowOffset.height))
            out = out.composited(over: shadow)
        }
        if let bg = set.background {
            out = out.composited(over: alpha(bg, state.backgroundAlpha))
        }
        out = out.applyingFilter("CISRGBToneCurveToLinear")
        return (alpha(out, min(1, max(0, style.opacity))), set.size)
    }

    static func alpha(_ img: CIImage, _ a: Double) -> CIImage {
        guard a < 0.999 else { return img }
        return img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, a))])
    }

    /// Halo: a própria camada desfocada, por baixo dela.
    static func applyGlow(_ img: CIImage, amount: Double, sigma: CGFloat) -> CIImage {
        guard amount > 0.001, !img.extent.isEmpty else { return img }
        let halo = img.applyingGaussianBlur(sigma: Double(max(sigma, 0.5)))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.8 * amount)])
        return img.composited(over: halo)
    }

    /// Reflexo de luz: faixa diagonal (~20°) que atravessa `rect` da esquerda para a direita
    /// conforme `position` vai de 0 a 1. Dentro da camada, a luz levemente quente entra em
    /// source-atop (aparece até em texto branco, pelo tom); fora dela, um brilho vaza ao longo
    /// da faixa (a faixa recortada pela camada desfocada), por baixo da camada.
    static func applyShine(_ img: CIImage, in rect: CGRect, position: Double, strength: Double) -> CIImage {
        guard strength > 0.001, rect.width > 0, rect.height > 0, !img.extent.isEmpty else { return img }
        let angle = 20 * Double.pi / 180
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let projections = corners.map { $0.x * dir.x + $0.y * dir.y }
        let short = min(rect.width, rect.height)
        let band = 0.55 * short + 0.08 * max(rect.width, rect.height)
        // Começa e termina com a faixa ainda tocando a caixa: a passagem aparece em mais quadros.
        let from = projections.min()! - band * 0.3
        let to = projections.max()! + band * 0.3
        let c = from + (to - from) * position
        func point(_ t: CGFloat) -> CIVector { CIVector(x: t * dir.x, y: t * dir.y) }
        // Tom levemente quente: em texto branco, a faixa aparece pela cor.
        let warm = CIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        let clear = CIColor(red: 1, green: 0.93, blue: 0.8, alpha: 0)
        // Rampas suaves (smoothstep) dos dois lados do centro: o mínimo das duas é a faixa.
        let rise = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": point(c - band / 2), "inputPoint1": point(c), "inputColor0": clear, "inputColor1": warm,
        ])!.outputImage!
        let fall = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": point(c), "inputPoint1": point(c + band / 2), "inputColor0": warm, "inputColor1": clear,
        ])!.outputImage!
        let light = rise.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: fall])
        func scaled(_ image: CIImage, _ a: Double) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
        }
        let inside = scaled(light, 0.85 * strength).cropped(to: img.extent)
            .applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: img])
        // Brilho que vaza: só onde a camada desfocada tem alfa, e mais forte que ela perto das letras.
        let spread = img.applyingGaussianBlur(sigma: Double(0.06 * short + 2))
        let halo = scaled(light, min(1, 1.1 * strength))
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: spread])
        return inside.composited(over: halo)
    }
}
