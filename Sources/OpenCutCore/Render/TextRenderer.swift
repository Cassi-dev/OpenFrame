import CoreImage
import CoreText
import Foundation

/// Rasteriza texto com Core Text (seguro fora da main thread) e guarda o
/// resultado em cache por conteúdo, estilo, resolução e progresso da animação.
final class TextRenderer: @unchecked Sendable {
    static let shared = TextRenderer()

    private let cache = NSCache<NSString, CIImage>()

    init() {
        cache.countLimit = 256
    }

    func image(for content: TextContent, canvas: CGSize, reveal: Double) -> CIImage? {
        let characters = content.text.count
        guard characters > 0, canvas.height > 0 else { return nil }
        let visible = reveal >= 1 ? characters : Int((Double(characters) * reveal).rounded(.up))
        let key = "\(content.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))|\(visible)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = render(content, canvas: canvas, visibleCharacters: visible) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private func render(_ content: TextContent, canvas: CGSize, visibleCharacters: Int) -> CIImage? {
        let style = content.style
        let fontPx = max(4, CGFloat(style.fontSize) * canvas.height)
        let font = makeFont(style, size: fontPx)
        let paragraph = makeParagraphStyle(style.alignment)

        let visibleAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -style.strokeWidth,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): style.strokeColor.cgColor,
        ]
        // O trecho ainda "não digitado" é desenhado transparente, para o
        // layout não pular durante a animação de máquina de escrever.
        var hiddenAttrs = visibleAttrs
        hiddenAttrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = CGColor(gray: 0, alpha: 0)
        hiddenAttrs[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = 0

        let text = content.text
        let attributed = NSMutableAttributedString(string: text, attributes: visibleAttrs)
        if visibleCharacters < text.count {
            let start = text.index(text.startIndex, offsetBy: visibleCharacters)
            attributed.setAttributes(hiddenAttrs, range: NSRange(start..<text.endIndex, in: text))
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let maxWidth = max(fontPx, CGFloat(style.maxWidth) * canvas.width)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(suggested.width) + 1, height: ceil(suggested.height) + 1)
        let pad = ceil(fontPx * 0.35)
        let width = Int(textSize.width + pad * 2)
        let height = Int(textSize.height + pad * 2)

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        if style.backgroundEnabled {
            let box = CGRect(x: pad * 0.4, y: pad * 0.4, width: CGFloat(width) - pad * 0.8, height: CGFloat(height) - pad * 0.8)
            ctx.setFillColor(style.backgroundColor.cgColor)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: fontPx * 0.18, cornerHeight: fontPx * 0.18, transform: nil))
            ctx.fillPath()
        }
        if style.shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -fontPx * 0.04), blur: fontPx * 0.15,
                          color: CGColor(gray: 0, alpha: 0.65))
        }
        let path = CGPath(rect: CGRect(origin: CGPoint(x: pad, y: pad), size: textSize), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)

        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }

    private func makeFont(_ style: TextStyle, size: CGFloat) -> CTFont {
        let base = CTFontCreateWithName(style.fontName as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
    }

    private func makeParagraphStyle(_ alignment: TextAlignmentKind) -> CTParagraphStyle {
        var value: CTTextAlignment = switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        return withUnsafeBytes(of: &value) { raw in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                                  value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
    }
}
