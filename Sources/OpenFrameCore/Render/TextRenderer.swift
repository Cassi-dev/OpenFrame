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

    init() {
        cache.countLimit = 256
    }

    func image(for content: TextContent, canvas: CGSize, reveal: Double) -> CIImage? {
        let text = Self.cased(content.text, content.style.textCase)
        let characters = text.count
        guard characters > 0, canvas.height > 0 else { return nil }
        let visible = reveal >= 1 ? characters : Int((Double(characters) * reveal).rounded(.up))
        // `content` é Hashable por inteiro: qualquer campo novo do estilo entra na chave.
        let key = "\(content.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))|\(visible)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = render(text, style: content.style, canvas: canvas, visibleCharacters: visible) else { return nil }
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
    private static let syntheticSlant = CGFloat(tan(12 * Double.pi / 180))
    /// Espessura extra do negrito sintético, em em.
    private static let syntheticBold: CGFloat = 0.03

    private func render(_ text: String, style: TextStyle, canvas: CGSize, visibleCharacters: Int) -> CIImage? {
        let fontPx = max(4, CGFloat(style.fontSize) * canvas.height)
        let face = makeFont(style, size: fontPx)

        var attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): face.font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String):
                makeParagraphStyle(style.alignment, lineHeight: lineHeight(face.font, style: style, fontPx: fontPx)),
        ]
        if style.letterSpacing != 0 {
            attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = CGFloat(style.letterSpacing) * fontPx
        }
        let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let maxWidth = max(fontPx, CGFloat(style.maxWidth) * canvas.width)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(suggested.width) + 1, height: ceil(suggested.height) + 1)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(origin: .zero, size: textSize), transform: nil), nil)
        let cut = text.index(text.startIndex, offsetBy: min(visibleCharacters, text.count)).utf16Offset(in: text)
        let shapes = collectShapes(frame, text: text as NSString, visibleUTF16: cut, style: style, face: face, fontPx: fontPx)

        // Margens: o bastante para contorno, fundo, sombra e partes das letras
        // que passam da caixa tipográfica (itálico, linhas apertadas).
        let strokeOut = max(0, CGFloat(style.strokeWidth)) / 100 * fontPx / 2
            + (face.syntheticBold ? Self.syntheticBold * fontPx / 2 : 0)
        let bgX = style.backgroundEnabled ? max(0, CGFloat(style.backgroundPaddingX)) * fontPx : 0
        let bgY = style.backgroundEnabled ? max(0, CGFloat(style.backgroundPaddingY)) * fontPx : 0
        let shadowOffset = shadowOffset(style, fontPx: fontPx)
        let shadowBlur = style.shadow ? max(0, CGFloat(style.shadowBlur)) * fontPx : 0
        let shadowX = style.shadow ? abs(shadowOffset.width) + shadowBlur * 1.5 : 0
        let shadowY = style.shadow ? abs(shadowOffset.height) + shadowBlur * 1.5 : 0
        let slant = (style.italic || face.syntheticItalic) ? fontPx * 0.25 : 0
        let tight = max(0, -CGFloat(style.lineSpacing)) * fontPx
        let base = ceil(fontPx * 0.35)
        let padX = max(base, ceil(fontPx * 0.12 + max(strokeOut, bgX) + shadowX + slant))
        let padY = max(base, ceil(fontPx * 0.12 + max(strokeOut, bgY) + shadowY + tight))
        let width = Int(textSize.width + padX * 2)
        let height = Int(textSize.height + padY * 2)

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: padX, y: padY)
        ctx.setAlpha(CGFloat(min(1, max(0, style.opacity))))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        if style.backgroundEnabled {
            let box = CGRect(origin: .zero, size: textSize).insetBy(dx: -bgX, dy: -bgY)
            let radius = min(max(0, CGFloat(style.backgroundRadius)) * fontPx, min(box.width, box.height) / 2)
            ctx.setFillColor(style.backgroundColor.cgColor)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }

        // Letras, contorno e sublinhado numa camada só: a sombra sai uma vez, do conjunto.
        if style.shadow {
            ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: style.shadowColor.cgColor)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        if strokeOut > 0 {
            ctx.setStrokeColor(style.strokeColor.cgColor)
            ctx.setLineWidth(strokeOut * 2)
            for path in [shapes.glyphs, shapes.underlines] where !path.isEmpty {
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        ctx.setFillColor(style.color.cgColor)
        if face.syntheticBold {
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(Self.syntheticBold * fontPx)
            ctx.addPath(shapes.glyphs)
            ctx.strokePath()
        }
        for path in [shapes.glyphs, shapes.underlines] where !path.isEmpty {
            ctx.addPath(path)
            ctx.fillPath()
        }
        // Glifos coloridos (emoji) não têm contorno vetorial: são desenhados como estão.
        for run in shapes.colorGlyphs {
            run.positions.withUnsafeBufferPointer { positions in
                CTFontDrawGlyphs(run.font, run.glyphs, positions.baseAddress!, run.glyphs.count, ctx)
            }
        }
        ctx.endTransparencyLayer()
        ctx.endTransparencyLayer()

        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }

    private struct ColorGlyphs {
        let font: CTFont
        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
    }

    private struct Shapes {
        let glyphs: CGPath
        let underlines: CGPath
        let colorGlyphs: [ColorGlyphs]
    }

    /// Junta os contornos das letras visíveis (as que a máquina de escrever já
    /// revelou) e os retângulos do sublinhado, nas coordenadas da caixa de texto.
    private func collectShapes(_ frame: CTFrame, text: NSString, visibleUTF16: Int, style: TextStyle,
                               face: FontFace, fontPx: CGFloat) -> Shapes {
        let glyphPath = CGMutablePath()
        let underlinePath = CGMutablePath()
        var colorGlyphs: [ColorGlyphs] = []
        let skew = CGAffineTransform(a: 1, b: 0, c: face.syntheticItalic ? Self.syntheticSlant : 0, d: 1, tx: 0, ty: 0)
        let blanks = CharacterSet.whitespacesAndNewlines

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        // O Core Text põe o espaço extra depois de toda letra, inclusive a última da
        // linha: desconta essa sobra para centralizar e sublinhar só o que se vê.
        let kern = CGFloat(style.letterSpacing) * fontPx
        let shift: CGFloat = switch style.alignment {
        case .left: 0
        case .center: kern / 2
        case .right: kern
        }
        for (line, lineOrigin) in zip(lines, origins) {
            let origin = CGPoint(x: lineOrigin.x + shift, y: lineOrigin.y)
            var minX = CGFloat.infinity
            var maxX = -CGFloat.infinity
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let runAttrs = CTRunGetAttributes(run) as NSDictionary
                let font = runAttrs[kCTFontAttributeName].map { $0 as! CTFont } ?? face.font
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
                var colored = ColorGlyphs(font: font)
                for i in 0..<count where indices[i] < visibleUTF16 {
                    let p = CGPoint(x: origin.x + positions[i].x, y: origin.y + positions[i].y)
                    if let scalar = Unicode.Scalar(text.character(at: indices[i])), !blanks.contains(scalar) {
                        minX = min(minX, p.x)
                        maxX = max(maxX, p.x + advances[i].width - kern)
                    }
                    if isColor {
                        colored.glyphs.append(glyphs[i])
                        colored.positions.append(p)
                    } else if let outline = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                        glyphPath.addPath(outline, transform: skew.concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
                    }
                }
                if !colored.glyphs.isEmpty { colorGlyphs.append(colored) }
            }
            if style.underline, maxX > minX {
                // Posição e espessura em em, como `underline_offset`/`underline_width` do CapCut.
                let thickness = fontPx * 0.05
                let top = origin.y - fontPx * 0.12
                underlinePath.addRect(CGRect(x: minX, y: top - thickness, width: maxX - minX, height: thickness))
            }
        }
        return Shapes(glyphs: glyphPath, underlines: underlinePath, colorGlyphs: colorGlyphs)
    }

    private func shadowOffset(_ style: TextStyle, fontPx: CGFloat) -> CGSize {
        let distance = max(0, CGFloat(style.shadowDistance)) * fontPx
        let angle = CGFloat(style.shadowAngle) * .pi / 180
        return CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
    }

    // MARK: - Fonte e parágrafo

    private struct FontFace {
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
