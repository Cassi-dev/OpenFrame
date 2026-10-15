import CoreImage
import CoreText
import Foundation

/// Rasteriza texto com Core Text (seguro fora da main thread) e guarda o
/// resultado em cache por conteúdo, estilo, resolução e progresso da animação.
///
/// As letras viram contornos (`CTFontCreatePathForGlyph`), o que permite
/// desenhar o contorno só para fora com cantos arredondados, negrito e itálico
/// sintéticos quando a família não tem esses estilos, e uma sombra única para
/// o conjunto letras + contorno + sublinhado.
final class TextRenderer: @unchecked Sendable {
    static let shared = TextRenderer()

    private let cache = NSCache<NSString, CIImage>()
    /// Sprites por unidade (`TextMotion`) e glifos do "decodificar".
    let unitCache = NSCache<NSString, TextUnits>()
    let scrambleCache = NSCache<NSString, ScrambleSet>()

    init() {
        cache.countLimit = 256
        unitCache.countLimit = 32
        scrambleCache.countLimit = 8
    }

    func image(for content: TextContent, canvas: CGSize, reveal: Double) -> CIImage? {
        let text = Self.cased(content.text, content.style.textCase)
        let characters = text.count
        guard characters > 0, canvas.height > 0 else { return nil }
        let visible = reveal >= 1 ? characters : Int((Double(characters) * reveal).rounded(.up))
        // `content` é Hashable por inteiro: qualquer campo novo do estilo entra na chave.
        let key = "\(content.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))|\(visible)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = render(text, style: content.style, emphasis: content.emphasis, canvas: canvas,
                                 visibleCharacters: visible) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func cased(_ text: String, _ textCase: TextCase) -> String {
        switch textCase {
        case .none: text
        case .upper: text.uppercased(with: .current)
        case .lower: text.lowercased(with: .current)
        case .title: text.capitalized(with: .current)
        }
    }

    // MARK: - Desenho

    /// Inclinação do itálico sintético (12°).
    static let syntheticSlant = CGFloat(tan(12 * Double.pi / 180))
    /// Espessura extra do negrito sintético, em em.
    static let syntheticBold: CGFloat = 0.03

    struct Layout {
        let face: FontFace
        let fontPx: CGFloat
        /// Maior fonte do texto (palavra-chave e linhas ampliadas pelo `fitLines`): as margens contam com ela.
        let peakFontPx: CGFloat
        let textSize: CGSize
        let frame: CTFrame
        /// Espaço extra entre letras, em pixels.
        let kern: CGFloat
        /// Trechos (UTF-16) das palavras-chave e a cor delas (`nil` = a do texto).
        let accentRanges: [NSRange]
        let accentColor: RGBA?
    }

    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)
    private static let paragraphKey = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)

    /// Monta o texto: fonte, palavras-chave (`emphasis`), linhas ajustadas à largura (`fitLines`) e quebra
    /// (comum, equilibrada ou só nos `\n`).
    func layout(_ text: String, style: TextStyle, canvas: CGSize, emphasis: WordEmphasis? = nil) -> Layout {
        let fontPx = max(4, CGFloat(style.fontSize) * canvas.height)
        let face = makeFont(style, size: fontPx)

        let string = NSMutableAttributedString(string: text, attributes: [
            Self.fontKey: face.font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,
            Self.paragraphKey: makeParagraphStyle(style.alignment, lineHeight: lineHeight(face.font, style: style, fontPx: fontPx)),
        ])
        let all = NSRange(location: 0, length: string.length)
        if style.letterSpacing != 0 { string.addAttribute(Self.kernKey, value: CGFloat(style.letterSpacing) * fontPx, range: all) }

        // Palavras-chave: outra fonte, maior, desenhada com a cor da ênfase.
        var accent: [NSRange] = []
        var peak = fontPx
        if let emphasis, !emphasis.words.isEmpty {
            var es = style
            es.fontName = emphasis.fontName
            es.fontFace = emphasis.fontFace
            es.bold = false
            es.italic = false
            let size = fontPx * CGFloat(min(max(emphasis.scale, 0.2), 5))
            let font = makeFont(es, size: size).font
            let words = Self.wordRanges(text)
            for i in Set(emphasis.words).sorted() where words.indices.contains(i) {
                string.addAttribute(Self.fontKey, value: font, range: words[i])
                if style.letterSpacing != 0 { string.addAttribute(Self.kernKey, value: CGFloat(style.letterSpacing) * size, range: words[i]) }
                accent.append(words[i])
            }
            if !accent.isEmpty { peak = max(peak, size) }
        }
        if style.fitLines {
            peak = max(peak, fitLines(string, style: style, face: face, fontPx: fontPx,
                                      width: max(fontPx, CGFloat(style.maxWidth) * canvas.width)))
        }

        let framesetter = CTFramesetterCreateWithAttributedString(string)
        var wrap = max(fontPx, CGFloat(style.maxWidth) * canvas.width)
        if style.fitLines {
            // As linhas já têm a largura da caixa: só os `\n` quebram (o que passar dos limites de escala, sai).
            wrap = 1_000_000
        } else if style.balanceLines {
            wrap = Self.balancedWidth(framesetter, length: string.length, maxWidth: wrap)
        }
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: wrap, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(suggested.width) + 1, height: ceil(suggested.height) + 1)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(origin: .zero, size: textSize), transform: nil), nil)
        return Layout(face: face, fontPx: fontPx, peakFontPx: peak, textSize: textSize, frame: frame,
                      kern: CGFloat(style.letterSpacing) * fontPx, accentRanges: accent,
                      accentColor: accent.isEmpty ? nil : emphasis?.color)
    }

    /// Trechos (UTF-16) das palavras do texto: a divisão de `TextContent.words(of:)`.
    static func wordRanges(_ text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?
        var offset = 0
        for ch in text {
            let n = ch.utf16.count
            if ch.isWhitespace {
                if let s = start { ranges.append(NSRange(location: s, length: offset - s)) }
                start = nil
            } else if start == nil {
                start = offset
            }
            offset += n
        }
        if let s = start { ranges.append(NSRange(location: s, length: offset - s)) }
        return ranges
    }

    /// Faixa de escala de cada linha no `fitLines`.
    static let fitRange: ClosedRange<CGFloat> = 0.6...2.5

    /// Escala cada linha (separada por `\n`) para ocupar `width`, dentro de `fitRange`, com a altura de linha
    /// da própria fonte. Devolve o maior tamanho de fonte.
    private func fitLines(_ string: NSMutableAttributedString, style: TextStyle, face: FontFace, fontPx: CGFloat,
                          width: CGFloat) -> CGFloat {
        let ns = string.string as NSString
        var peak = fontPx
        var start = 0
        while start < ns.length {
            let newline = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start)).location
            let end = newline == NSNotFound ? ns.length : newline
            let range = NSRange(location: start, length: end - start)
            start = end + 1
            guard range.length > 0 else { continue }
            let line = CTLineCreateWithAttributedString(string.attributedSubstring(from: range))
            let natural = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
                - CGFloat(style.letterSpacing) * fontPx
            guard natural > 0 else { continue }
            let k = min(max(width / natural, Self.fitRange.lowerBound), Self.fitRange.upperBound)
            string.enumerateAttribute(Self.fontKey, in: range) { value, r, _ in
                guard let value else { return }
                let font = value as! CTFont
                string.addAttribute(Self.fontKey, value: CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * k, nil, nil),
                                    range: r)
            }
            if style.letterSpacing != 0 {
                string.enumerateAttribute(Self.kernKey, in: range) { value, r, _ in
                    if let kern = value as? CGFloat { string.addAttribute(Self.kernKey, value: kern * k, range: r) }
                }
            }
            let size = fontPx * k
            let scaled = CTFontCreateCopyWithAttributes(face.font, size, nil, nil)
            let paragraph = NSRange(location: range.location, length: min(range.length + 1, ns.length - range.location))
            string.addAttribute(Self.paragraphKey,
                                value: makeParagraphStyle(style.alignment, lineHeight: lineHeight(scaled, style: style, fontPx: size)),
                                range: paragraph)
            peak = max(peak, size)
        }
        return peak
    }

    /// Número de linhas da quebra automática na largura `width`.
    static func lineCount(_ typesetter: CTTypesetter, length: Int, width: CGFloat) -> Int {
        var start = 0
        var count = 0
        while start < length {
            start += max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            count += 1
        }
        return count
    }

    /// Menor largura de quebra com o mesmo número de linhas de `maxWidth` (`text-wrap: balance`): as linhas
    /// ficam parecidas e a mais longa, a menor possível. Busca binária até meio pixel.
    static func balancedWidth(_ framesetter: CTFramesetter, length: Int, maxWidth: CGFloat) -> CGFloat {
        let typesetter = CTFramesetterGetTypesetter(framesetter)
        let lines = lineCount(typesetter, length: length, width: maxWidth)
        guard lines > 1 else { return maxWidth }
        var lo: CGFloat = 0
        var hi = maxWidth
        while hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if lineCount(typesetter, length: length, width: mid) <= lines { hi = mid } else { lo = mid }
        }
        return hi
    }

    /// Largura do texto numa linha só, com a fonte, a caixa e o espaçamento do estilo, para a fonte de
    /// `fontPx` pixels. Usado pela quebra das legendas.
    func lineWidth(_ text: String, style: TextStyle, fontPx: CGFloat) -> CGFloat {
        let face = makeFont(style, size: fontPx)
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): face.font]
        if style.letterSpacing != 0 {
            attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = CGFloat(style.letterSpacing) * fontPx
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: Self.cased(text, style.textCase),
                                                                       attributes: attrs))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Texto de cada linha do layout (as quebras automáticas e as de `\n`), sem os espaços das pontas.
    func lineTexts(for content: TextContent, canvas: CGSize) -> [String] {
        let text = Self.cased(content.text, content.style.textCase)
        guard !text.isEmpty, canvas.height > 0 else { return [] }
        let l = layout(text, style: content.style, canvas: canvas, emphasis: content.emphasis)
        let ns = text as NSString
        return (CTFrameGetLines(l.frame) as! [CTLine]).map { line in
            let r = CTLineGetStringRange(line)
            return ns.substring(with: NSRange(location: r.location, length: r.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let sizes = NSCache<NSString, NSValue>()

    /// Tamanho em pixels da caixa do texto mais o fundo (se ligado), sem as
    /// margens de sombra. A imagem de `image(for:)` tem o mesmo centro.
    func boxSize(for content: TextContent, canvas: CGSize) -> CGSize? {
        let text = Self.cased(content.text, content.style.textCase)
        guard !text.isEmpty, canvas.height > 0 else { return nil }
        let key = "\(content.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))" as NSString
        if let cached = sizes.object(forKey: key) { return cached.sizeValue }
        let style = content.style
        let l = layout(text, style: style, canvas: canvas, emphasis: content.emphasis)
        let bgX = style.backgroundEnabled ? max(0, CGFloat(style.backgroundPaddingX)) * l.fontPx : 0
        let bgY = style.backgroundEnabled ? max(0, CGFloat(style.backgroundPaddingY)) * l.fontPx : 0
        let size = CGSize(width: l.textSize.width + bgX * 2, height: l.textSize.height + bgY * 2)
        sizes.setObject(NSValue(size: size), forKey: key)
        return size
    }

    /// Margens e medidas do desenho, iguais no caminho estático e no por unidade.
    struct Metrics {
        let strokeOut: CGFloat
        let bgX: CGFloat
        let bgY: CGFloat
        let shadowOffset: CGSize
        let shadowBlur: CGFloat
        let padX: CGFloat
        let padY: CGFloat
        let width: Int
        let height: Int
    }

    func metrics(_ l: Layout, style: TextStyle) -> Metrics {
        let fontPx = l.fontPx
        // Margens: o bastante para contorno, fundo, sombra e partes das letras
        // que passam da caixa tipográfica (itálico, linhas apertadas).
        let strokeOut = max(0, CGFloat(style.strokeWidth)) / 100 * fontPx / 2
            + (l.face.syntheticBold ? Self.syntheticBold * fontPx / 2 : 0)
        let bgX = style.backgroundEnabled ? max(0, CGFloat(style.backgroundPaddingX)) * fontPx : 0
        let bgY = style.backgroundEnabled ? max(0, CGFloat(style.backgroundPaddingY)) * fontPx : 0
        let shadowOffset = shadowOffset(style, fontPx: fontPx)
        let shadowBlur = style.shadow ? max(0, CGFloat(style.shadowBlur)) * fontPx : 0
        let shadowX = style.shadow ? abs(shadowOffset.width) + shadowBlur * 1.5 : 0
        let shadowY = style.shadow ? abs(shadowOffset.height) + shadowBlur * 1.5 : 0
        // A palavra-chave (às vezes itálica) e as linhas ampliadas pedem margens pela maior fonte.
        let peak = l.peakFontPx
        let slant = (style.italic || l.face.syntheticItalic || !l.accentRanges.isEmpty) ? peak * 0.25 : 0
        let tight = max(0, -CGFloat(style.lineSpacing)) * peak
        let base = ceil(peak * 0.35)
        let padX = max(base, ceil(fontPx * 0.12 + max(strokeOut, bgX) + shadowX + slant))
        let padY = max(base, ceil(fontPx * 0.12 + max(strokeOut, bgY) + shadowY + tight))
        return Metrics(strokeOut: strokeOut, bgX: bgX, bgY: bgY, shadowOffset: shadowOffset, shadowBlur: shadowBlur,
                       padX: padX, padY: padY,
                       width: Int(l.textSize.width + padX * 2), height: Int(l.textSize.height + padY * 2))
    }

    /// Tamanho em pixels da imagem de `image(for:)` (com as margens), sem desenhar.
    func imageSize(for content: TextContent, canvas: CGSize) -> CGSize? {
        let text = Self.cased(content.text, content.style.textCase)
        guard !text.isEmpty, canvas.height > 0 else { return nil }
        let key = "img|\(content.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))" as NSString
        if let cached = sizes.object(forKey: key) { return cached.sizeValue }
        let m = metrics(layout(text, style: content.style, canvas: canvas, emphasis: content.emphasis), style: content.style)
        let size = CGSize(width: m.width, height: m.height)
        sizes.setObject(NSValue(size: size), forKey: key)
        return size
    }

    /// Lado maior máximo da imagem rasterizada de um texto.
    static let maxRasterSide: CGFloat = 8192

    /// Fator de rasterização do texto: a escala efetiva (estilo × pico da animação), em passos
    /// de 1/8 arredondados para cima (o cache não explode ao arrastar as alças), nunca abaixo
    /// de 1 e limitado para a imagem não passar de `maxRasterSide`.
    func rasterScale(for content: TextContent, canvas: CGSize, peak: Double) -> CGFloat {
        let wanted = max(1, (abs(content.style.scale) * peak * 8).rounded(.up) / 8)
        guard let size = imageSize(for: content, canvas: canvas), max(size.width, size.height) > 0 else { return CGFloat(wanted) }
        return min(CGFloat(wanted), Self.maxRasterSide / max(size.width, size.height))
    }

    private func render(_ text: String, style: TextStyle, emphasis: WordEmphasis?, canvas: CGSize,
                        visibleCharacters: Int) -> CIImage? {
        let l = layout(text, style: style, canvas: canvas, emphasis: emphasis)
        let fontPx = l.fontPx
        let m = metrics(l, style: style)
        let cut = text.index(text.startIndex, offsetBy: min(visibleCharacters, text.count)).utf16Offset(in: text)
        let (glyphs, lines) = glyphInfo(l, text: text as NSString, style: style)
        let visible = glyphs.filter { $0.utf16 < cut }
        var underlines: [CGRect] = []
        if style.underline {
            for line in lines.indices {
                let onLine = visible.filter { $0.line == line && !$0.blank }
                guard let minX = onLine.map(\.position.x).min(),
                      let maxX = onLine.map({ $0.position.x + $0.advance - l.kern }).max(), maxX > minX else { continue }
                underlines.append(underlineRect(lines[line], from: minX, to: maxX, fontPx: fontPx))
            }
        }
        let shapes = makeShapes(visible, underlines: underlines, face: l.face)

        guard let ctx = Self.bitmap(width: m.width, height: m.height) else { return nil }
        ctx.translateBy(x: m.padX, y: m.padY)
        ctx.setAlpha(CGFloat(min(1, max(0, style.opacity))))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        if style.backgroundEnabled {
            ctx.setFillColor(style.backgroundColor.cgColor)
            ctx.addPath(backgroundPath(l, m, style: style))
            ctx.fillPath()
        }

        // Letras, contorno e sublinhado numa camada só: a sombra sai uma vez, do conjunto.
        if style.shadow {
            ctx.setShadow(offset: m.shadowOffset, blur: m.shadowBlur, color: style.shadowColor.cgColor)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(shapes, in: ctx, style: style, l, m, stroke: true, fill: true)
        ctx.endTransparencyLayer()
        ctx.endTransparencyLayer()

        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }

    static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    func backgroundPath(_ l: Layout, _ m: Metrics, style: TextStyle) -> CGPath {
        let box = CGRect(origin: .zero, size: l.textSize).insetBy(dx: -m.bgX, dy: -m.bgY)
        let radius = min(max(0, CGFloat(style.backgroundRadius)) * l.fontPx, min(box.width, box.height) / 2)
        return CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// Desenha contorno e/ou preenchimento (com o negrito sintético e os emoji) no contexto.
    func draw(_ shapes: Shapes, in ctx: CGContext, style: TextStyle, _ l: Layout, _ m: Metrics, stroke: Bool, fill: Bool) {
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        if stroke, m.strokeOut > 0 {
            ctx.setStrokeColor(style.strokeColor.cgColor)
            ctx.setLineWidth(m.strokeOut * 2)
            for path in [shapes.glyphs, shapes.accentGlyphs, shapes.underlines] where !path.isEmpty {
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        guard fill else { return }
        ctx.setFillColor(style.color.cgColor)
        if l.face.syntheticBold, !shapes.glyphs.isEmpty {
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(Self.syntheticBold * l.fontPx)
            ctx.addPath(shapes.glyphs)
            ctx.strokePath()
        }
        for path in [shapes.glyphs, shapes.underlines] where !path.isEmpty {
            ctx.addPath(path)
            ctx.fillPath()
        }
        if !shapes.accentGlyphs.isEmpty {
            ctx.setFillColor((l.accentColor ?? style.color).cgColor)
            ctx.addPath(shapes.accentGlyphs)
            ctx.fillPath()
        }
        // Glifos coloridos (emoji) não têm contorno vetorial: são desenhados como estão.
        for run in shapes.colorGlyphs {
            run.positions.withUnsafeBufferPointer { positions in
                CTFontDrawGlyphs(run.font, run.glyphs, positions.baseAddress!, run.glyphs.count, ctx)
            }
        }
    }

    struct ColorGlyphs {
        let font: CTFont
        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
    }

    struct Shapes {
        let glyphs: CGPath
        /// Glifos das palavras-chave (outra cor, sem o negrito e o itálico sintéticos do texto).
        let accentGlyphs: CGPath
        let underlines: CGPath
        let colorGlyphs: [ColorGlyphs]
        /// Caixa de tudo, sem o contorno.
        let bounds: CGRect
    }

    /// Um glifo posicionado, nas coordenadas da caixa de texto.
    struct GlyphInfo {
        let glyph: CGGlyph
        let font: CTFont
        let isColor: Bool
        let position: CGPoint
        let advance: CGFloat
        /// Posição no texto (UTF-16).
        let utf16: Int
        let line: Int
        /// Espaço ou quebra de linha.
        let blank: Bool
        /// Parte de uma palavra-chave.
        var accent = false
    }

    struct LineInfo {
        let origin: CGPoint
        let ascent: CGFloat
        let descent: CGFloat
    }

    /// Glifos e linhas do layout. O Core Text põe o espaço extra depois de toda letra,
    /// inclusive a última da linha: as posições já descontam essa sobra para centralizar.
    func glyphInfo(_ l: Layout, text: NSString, style: TextStyle) -> ([GlyphInfo], [LineInfo]) {
        let blanks = CharacterSet.whitespacesAndNewlines
        let lines = CTFrameGetLines(l.frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(l.frame, CFRange(location: 0, length: 0), &origins)
        let shift: CGFloat = switch style.alignment {
        case .left: 0
        case .center: l.kern / 2
        case .right: l.kern
        }
        var result: [GlyphInfo] = []
        var lineInfo: [LineInfo] = []
        for (n, (line, lineOrigin)) in zip(lines, origins).enumerated() {
            let origin = CGPoint(x: lineOrigin.x + shift, y: lineOrigin.y)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            lineInfo.append(LineInfo(origin: origin, ascent: ascent, descent: descent))
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let runAttrs = CTRunGetAttributes(run) as NSDictionary
                let font = runAttrs[kCTFontAttributeName].map { $0 as! CTFont } ?? l.face.font
                let isColor = CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                let all = CFRange(location: 0, length: 0)
                CTRunGetGlyphs(run, all, &glyphs)
                CTRunGetPositions(run, all, &positions)
                CTRunGetAdvances(run, all, &advances)
                CTRunGetStringIndices(run, all, &indices)
                for i in 0..<count {
                    let blank = Unicode.Scalar(text.character(at: indices[i])).map { blanks.contains($0) } ?? false
                    let accent = l.accentRanges.contains { NSLocationInRange(indices[i], $0) }
                    result.append(GlyphInfo(glyph: glyphs[i], font: font, isColor: isColor,
                                            position: CGPoint(x: origin.x + positions[i].x, y: origin.y + positions[i].y),
                                            advance: advances[i].width, utf16: indices[i], line: n, blank: blank,
                                            accent: accent))
                }
            }
        }
        return (result, lineInfo)
    }

    /// Posição e espessura em em, como `underline_offset`/`underline_width` do CapCut.
    func underlineRect(_ line: LineInfo, from minX: CGFloat, to maxX: CGFloat, fontPx: CGFloat) -> CGRect {
        let thickness = fontPx * 0.05
        let top = line.origin.y - fontPx * 0.12
        return CGRect(x: minX, y: top - thickness, width: maxX - minX, height: thickness)
    }

    /// Junta os contornos dos glifos e os retângulos do sublinhado, nas coordenadas da caixa de texto.
    func makeShapes(_ glyphs: [GlyphInfo], underlines: [CGRect], face: FontFace) -> Shapes {
        let glyphPath = CGMutablePath()
        let accentPath = CGMutablePath()
        let underlinePath = CGMutablePath()
        var colorGlyphs: [ColorGlyphs] = []
        var bounds = CGRect.null
        let skew = CGAffineTransform(a: 1, b: 0, c: face.syntheticItalic ? Self.syntheticSlant : 0, d: 1, tx: 0, ty: 0)
        for g in glyphs {
            if g.isColor {
                if colorGlyphs.last.map({ $0.font != g.font }) ?? true { colorGlyphs.append(ColorGlyphs(font: g.font)) }
                colorGlyphs[colorGlyphs.count - 1].glyphs.append(g.glyph)
                colorGlyphs[colorGlyphs.count - 1].positions.append(g.position)
                var glyph = g.glyph
                var rect = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(g.font, .default, &glyph, &rect, 1)
                bounds = bounds.union(rect.offsetBy(dx: g.position.x, dy: g.position.y))
            } else if let outline = CTFontCreatePathForGlyph(g.font, g.glyph, nil) {
                let move = CGAffineTransform(translationX: g.position.x, y: g.position.y)
                if g.accent {
                    accentPath.addPath(outline, transform: move)
                } else {
                    glyphPath.addPath(outline, transform: skew.concatenating(move))
                }
            }
        }
        for rect in underlines { underlinePath.addRect(rect) }
        if !glyphPath.isEmpty { bounds = bounds.union(glyphPath.boundingBoxOfPath) }
        if !accentPath.isEmpty { bounds = bounds.union(accentPath.boundingBoxOfPath) }
        if !underlinePath.isEmpty { bounds = bounds.union(underlinePath.boundingBoxOfPath) }
        return Shapes(glyphs: glyphPath, accentGlyphs: accentPath, underlines: underlinePath, colorGlyphs: colorGlyphs,
                      bounds: bounds)
    }

    private func shadowOffset(_ style: TextStyle, fontPx: CGFloat) -> CGSize {
        let distance = max(0, CGFloat(style.shadowDistance)) * fontPx
        let angle = CGFloat(style.shadowAngle) * .pi / 180
        return CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
    }

    // MARK: - Fonte e parágrafo

    struct FontFace {
        let font: CTFont
        let syntheticBold: Bool
        let syntheticItalic: Bool
    }

    /// Compartilhado por todos os renderizadores e pelo `FontCatalog`.
    static let fontLock = NSLock()
    nonisolated(unsafe) private static var fonts: [String: FontFace] = [:]

    /// A busca de fontes passa pelo registro de fontes do sistema (XPC). Pedidos
    /// simultâneos de traços que a família não tem chegaram a travar os testes,
    /// então a criação é serializada e o resultado fica guardado.
    private func makeFont(_ style: TextStyle, size: CGFloat) -> FontFace {
        let key = "\(style.fontName)|\(style.fontFace)|\(style.bold)|\(style.italic)|\(size)"
        Self.fontLock.lock()
        defer { Self.fontLock.unlock() }
        if let cached = Self.fonts[key] { return cached }
        let face = lookUpFont(style, size: size)
        if Self.fonts.count > 128 { Self.fonts.removeAll() }
        Self.fonts[key] = face
        return face
    }

    private func lookUpFont(_ style: TextStyle, size: CGFloat) -> FontFace {
        var base = CTFontCreateWithName(style.fontName as CFString, size, nil)
        if !style.fontFace.isEmpty {
            let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: style.fontName,
                                               kCTFontStyleNameAttribute: style.fontFace]
            let wanted = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            let mandatory: Set<CFString> = [kCTFontFamilyNameAttribute, kCTFontStyleNameAttribute]
            if let match = CTFontDescriptorCreateMatchingFontDescriptor(wanted, mandatory as CFSet) {
                base = CTFontCreateWithFontDescriptor(match, size, nil)
            }
        }
        var font = base
        var syntheticBold = false
        var syntheticItalic = false
        let has = CTFontGetSymbolicTraits(base)
        for (wanted, trait) in [(style.bold, CTFontSymbolicTraits.traitBold), (style.italic, .traitItalic)]
        where wanted && !has.contains(trait) {
            if let copy = CTFontCreateCopyWithSymbolicTraits(font, size, nil, trait, trait) {
                font = copy
            } else if trait == .traitBold {
                syntheticBold = true
            } else {
                syntheticItalic = true
            }
        }
        return FontFace(font: font, syntheticBold: syntheticBold, syntheticItalic: syntheticItalic)
    }

    /// Altura fixa de linha quando há espaçamento extra; `nil` = altura natural da fonte.
    private func lineHeight(_ font: CTFont, style: TextStyle, fontPx: CGFloat) -> CGFloat? {
        guard style.lineSpacing != 0 else { return nil }
        let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        return max(fontPx * 0.3, natural + CGFloat(style.lineSpacing) * fontPx)
    }

    private func makeParagraphStyle(_ alignment: TextAlignmentKind, lineHeight: CGFloat?) -> CTParagraphStyle {
        var value: CTTextAlignment = switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        var height = lineHeight ?? 0
        return withUnsafeBytes(of: &value) { align in
            withUnsafeBytes(of: &height) { h in
                var settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                                        value: align.baseAddress!)]
                if lineHeight != nil {
                    settings.append(CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size,
                                                            value: h.baseAddress!))
                    settings.append(CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size,
                                                            value: h.baseAddress!))
                }
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }
}

/// Famílias e estilos de fonte instalados, para os menus do inspetor.
public enum FontCatalog {
    /// Famílias visíveis (sem as de sistema que começam com ".").
    public static func families() -> [String] {
        TextRenderer.fontLock.lock()
        defer { TextRenderer.fontLock.unlock() }
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Estilos de uma família ("Light", "Regular", "Bold Italic"…), do mais fino ao mais grosso.
    public static func faces(of family: String) -> [String] {
        TextRenderer.fontLock.lock()
        defer { TextRenderer.fontLock.unlock() }
        let wanted = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        let mandatory: Set<CFString> = [kCTFontFamilyNameAttribute]
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(wanted, mandatory as CFSet) as? [CTFontDescriptor] ?? []
        var seen = Set<String>()
        let faces = matches.compactMap { d -> (name: String, weight: Double, italic: Bool)? in
            guard let name = CTFontDescriptorCopyAttribute(d, kCTFontStyleNameAttribute) as? String,
                  seen.insert(name).inserted else { return nil }
            let traits = CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
            let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
            let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            return (name, weight, CTFontSymbolicTraits(rawValue: symbolic).contains(.traitItalic))
        }
        return faces.sorted { ($0.italic ? 1 : 0, $0.weight) < ($1.italic ? 1 : 0, $1.weight) }.map(\.name)
    }
}
