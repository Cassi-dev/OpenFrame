import CoreImage
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Texto")
struct TextTests {
    let canvas = CGSize(width: 1280, height: 720)

    func style(_ change: (inout TextStyle) -> Void = { _ in }) -> TextStyle {
        var s = TextStyle()
        s.shadow = false
        s.fontSize = 0.1
        change(&s)
        return s
    }

    func image(_ text: String, _ style: TextStyle, reveal: Double = 1) -> CIImage {
        TextRenderer().image(for: TextContent(text: text, style: style), canvas: canvas, reveal: reveal)!
    }

    /// Pixels RGBA (linha 0 = topo) da imagem do texto inteira.
    func pixels(_ img: CIImage) -> (width: Int, height: Int, data: [UInt8]) {
        let w = Int(img.extent.width), h = Int(img.extent.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        CIContext().render(img, toBitmap: &bytes, rowBytes: w * 4, bounds: img.extent, format: .RGBA8,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return (w, h, bytes)
    }

    @Test("Espaçamento entre letras alarga a caixa")
    func letterSpacingWidens() {
        let normal = image("ESPAÇO", style())
        let wide = image("ESPAÇO", style { $0.letterSpacing = 0.5 })
        let tight = image("ESPAÇO", style { $0.letterSpacing = -0.1 })
        // Seis letras com 0,5 em a mais cada: pelo menos ~2,5 em (180 px a 72 px/em) mais largo.
        #expect(wide.extent.width > normal.extent.width + 150)
        #expect(tight.extent.width < normal.extent.width)
        #expect(abs(wide.extent.height - normal.extent.height) < 2)
    }

    @Test("Espaçamento entre linhas muda a altura")
    func lineSpacingChangesHeight() {
        let normal = image("um\ndois\ntrês", style())
        let loose = image("um\ndois\ntrês", style { $0.lineSpacing = 1 })
        let tight = image("um\ndois\ntrês", style { $0.lineSpacing = -0.3 })
        // Duas entrelinhas de 1 em (72 px) a mais.
        #expect(loose.extent.height > normal.extent.height + 130)
        #expect(tight.extent.height < normal.extent.height)
        #expect(abs(loose.extent.width - normal.extent.width) < 2)
    }

    @Test("Projeto antigo sem os campos novos abre com os valores padrão")
    func decodesOldStyle() throws {
        // Estilo como era gravado antes desta versão (sem espaçamentos, sombra configurável etc.).
        let old = """
        {"fontName":"Futura","fontSize":0.09,"bold":false,"italic":true,
         "color":{"r":1,"g":0,"b":0,"a":1},"strokeColor":{"r":0,"g":0,"b":0,"a":1},"strokeWidth":3,
         "backgroundEnabled":true,"backgroundColor":{"r":0,"g":0,"b":0,"a":0.5},"shadow":false,
         "alignment":"left","x":0.1,"y":-0.5,"scale":1.2,"rotation":5,"maxWidth":0.8}
        """
        let s = try JSONDecoder().decode(TextStyle.self, from: Data(old.utf8))
        #expect(s.fontName == "Futura" && s.italic && !s.bold && s.strokeWidth == 3)
        #expect(s.alignment == .left && s.maxWidth == 0.8 && !s.shadow)
        let d = TextStyle()
        #expect(s.letterSpacing == d.letterSpacing && s.lineSpacing == d.lineSpacing)
        #expect(s.fontFace == "" && s.textCase == .none && !s.underline && s.opacity == 1)
        #expect(s.shadowColor == d.shadowColor && s.shadowAngle == d.shadowAngle)
        #expect(s.backgroundRadius == d.backgroundRadius && s.backgroundPaddingX == d.backgroundPaddingX)

        // Um projeto inteiro antigo também abre, e regravar mantém os campos novos.
        var p = Project()
        TimelineEditor.addText(TextContent(text: "Oi", style: s), to: &p, at: 0)
        let data = try JSONEncoder().encode(p)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json = Self.removingKeys(["letterSpacing", "lineSpacing", "fontFace", "underline", "textCase", "opacity",
                                  "shadowColor", "shadowDistance", "shadowAngle", "shadowBlur",
                                  "backgroundRadius", "backgroundPaddingX", "backgroundPaddingY"], from: json) as! [String: Any]
        let reopened = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(reopened.tracks.flatMap(\.segments).compactMap(\.text).first?.style == s)
    }

    /// Tira as chaves só de dentro dos objetos `style` (o segmento tem a própria `opacity`).
    static func removingKeys(_ keys: Set<String>, from value: Any, inStyle: Bool = false) -> Any {
        if let dict = value as? [String: Any] {
            return dict.filter { !(inStyle && keys.contains($0.key)) }
                .reduce(into: [String: Any]()) { $0[$1.key] = removingKeys(keys, from: $1.value, inStyle: $1.key == "style") }
        }
        if let array = value as? [Any] { return array.map { removingKeys(keys, from: $0) } }
        return value
    }

    @Test("Estilo novo sobrevive a gravar e abrir")
    func roundTrip() throws {
        let s = style {
            $0.letterSpacing = 0.2; $0.lineSpacing = -0.1; $0.underline = true; $0.textCase = .upper
            $0.shadow = true; $0.shadowAngle = 30; $0.shadowBlur = 0.3; $0.fontFace = "Light"; $0.opacity = 0.4
        }
        #expect(try JSONDecoder().decode(TextStyle.self, from: JSONEncoder().encode(s)) == s)
    }

    @Test("O cache distingue estilos que só mudam nos campos novos")
    func cacheKeyUsesNewFields() {
        let renderer = TextRenderer.shared
        let a = renderer.image(for: TextContent(text: "Cache", style: style()), canvas: canvas, reveal: 1)!
        let b = renderer.image(for: TextContent(text: "Cache", style: style { $0.letterSpacing = 0.4 }), canvas: canvas, reveal: 1)!
        #expect(b.extent.width > a.extent.width)
    }

    @Test("Contorno grosso fica do lado de fora da letra")
    func strokeIsOutside() {
        // Um "I" com contorno de 20% do tamanho: o meio da haste continua da cor do texto.
        let img = image("I", style { $0.strokeWidth = 20; $0.strokeColor = RGBA(1, 0, 0); $0.color = .white; $0.bold = true })
        let (w, h, px) = pixels(img)
        let i = ((h / 2) * w + w / 2) * 4
        #expect(px[i] > 240 && px[i + 1] > 240 && px[i + 2] > 240)
        // E o contorno vermelho aparece ao lado.
        let red = (0..<w).contains { x in
            let j = ((h / 2) * w + x) * 4
            return px[j] > 200 && px[j + 1] < 40 && px[j + 3] > 200
        }
        #expect(red)
    }

    @Test("Sombra segue o ângulo")
    func shadowFollowsAngle() {
        let s = style {
            $0.color = .white; $0.shadow = true; $0.shadowColor = RGBA(1, 0, 0)
            $0.shadowDistance = 0.4; $0.shadowBlur = 0; $0.shadowAngle = 0
        }
        let (w, h, px) = pixels(image("I", s))
        func reds(_ xs: Range<Int>) -> Int {
            xs.filter { x in let j = ((h / 2) * w + x) * 4; return px[j] > 200 && px[j + 1] < 40 && px[j + 3] > 200 }.count
        }
        #expect(reds(w / 2..<w) > 5)
        #expect(reds(0..<w / 2 - 10) == 0)
    }

    @Test("Opacidade vale para o texto inteiro")
    func opacity() {
        let (_, _, px) = pixels(image("OPACO", style { $0.opacity = 0.5; $0.backgroundEnabled = true; $0.backgroundColor = .black }))
        let maxAlpha = stride(from: 3, to: px.count, by: 4).map { px[$0] }.max() ?? 0
        #expect(maxAlpha > 100 && maxAlpha < 140)
    }

    @Test("Sublinhado desenha embaixo da linha")
    func underline() {
        func inkBelowBaseline(_ s: TextStyle) -> Int {
            // "ama" não tem descendentes: abaixo da linha de base só pode haver o sublinhado.
            let (w, h, px) = pixels(image("ama", s))
            var count = 0
            for y in (h * 62 / 100)..<h {
                for x in 0..<w where px[(y * w + x) * 4 + 3] > 128 { count += 1 }
            }
            return count
        }
        #expect(inkBelowBaseline(style { $0.underline = true }) > inkBelowBaseline(style()) + 100)
    }

    @Test("Caixa das letras e máquina de escrever")
    func textCase() {
        #expect(TextRenderer.cased("olá Mundo", .upper) == "OLÁ MUNDO")
        #expect(TextRenderer.cased("Olá MUNDO", .lower) == "olá mundo")
        #expect(TextRenderer.cased("olá mundo", .title) == "Olá Mundo")
        // A revelação parcial não muda o tamanho da caixa (o layout não pula).
        let s = style { $0.textCase = .upper }
        #expect(image("digitando", s, reveal: 0.3).extent == image("digitando", s).extent)
    }

    @Test("Catálogo lista estilos da família em ordem de peso")
    func fontCatalog() {
        #expect(FontCatalog.families().contains("Helvetica Neue"))
        let faces = FontCatalog.faces(of: "Helvetica Neue")
        let light = faces.firstIndex(of: "Light"), bold = faces.firstIndex(of: "Bold")
        #expect(light != nil && bold != nil && light! < bold!)
        // Um estilo escolhido muda o desenho em relação ao padrão.
        let regular = image("Peso", style { $0.bold = false })
        let heavy = image("Peso", style { $0.bold = false; $0.fontFace = "Bold" })
        #expect(heavy.extent.width > regular.extent.width)
    }
}
