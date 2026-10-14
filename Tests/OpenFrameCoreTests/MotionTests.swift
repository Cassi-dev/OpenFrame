import CoreImage
import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Animações de motion")
struct MotionTests {
    static let newKinds: [AnimationKind] = [.focus, .cascade, .elastic, .wave, .wordByWord, .maskReveal, .tracking, .decode]
    let size = CGSize(width: 480, height: 270)

    func textProject(_ change: (inout Segment) -> Void = { _ in }) -> (Project, UUID) {
        var p = Project()
        p.canvas.aspect = .r16x9
        var style = TextStyle()
        style.y = 0
        style.fontSize = 0.15
        let id = TimelineEditor.addText(TextContent(text: "Motion 42", style: style), to: &p, at: 0, duration: 3_000_000)
        TimelineEditor.update(&p, segment: id, change)
        return (p, id)
    }

    func render(_ p: Project, at t: Micros) -> Bitmap {
        Bitmap(FrameRenderer().render(plan: RenderPlan(project: p, renderSize: size), time: t) { _ in nil }, size: size)
    }

    /// Soma do brilho (canal vermelho) de todos os pixels.
    func ink(_ b: Bitmap) -> Int {
        stride(from: 0, to: b.data.count, by: 4).reduce(0) { $0 + Int(b.data[$1]) }
    }

    func difference(_ a: Bitmap, _ b: Bitmap) -> Int {
        zip(a.data, b.data).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }

    // MARK: - Modelo

    @Test("Tipos novos: nomes, só texto e Codable")
    func newKindsModel() throws {
        #expect(AnimationKind.focus.displayName == "Foco" && !AnimationKind.focus.textOnly)
        for kind in Self.newKinds where kind != .focus { #expect(kind.textOnly) }
        #expect(AnimationKind.decode.displayName == "Decodificar")
        #expect(LoopKind.allCases.map(\.displayName) == ["Flutuar", "Pulsar", "Respirar brilho", "Reflexo de luz"])

        var (p, id) = textProject {
            $0.animationIn = SegmentAnimation(kind: .maskReveal, duration: 700_000)
            $0.animationOut = SegmentAnimation(kind: .decode)
            $0.animationLoop = LoopAnimation(kind: .shine, period: 1_500_000, intensity: 0.8)
        }
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        #expect(back == p)
        #expect(back.segment(id)!.animationLoop == LoopAnimation(kind: .shine, period: 1_500_000, intensity: 0.8))

        // Sem loop, a chave não é gravada.
        TimelineEditor.update(&p, segment: id) { $0.animationLoop = nil }
        let plain = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(!plain.contains("animationLoop"))
    }

    @Test("Projeto antigo sem animationLoop abre")
    func oldProjectOpens() throws {
        let (p, id) = textProject { $0.animationIn = SegmentAnimation(kind: .fade) }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        #expect(!String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self).contains("animationLoop"))
        json["formatVersion"] = 1
        let reopened = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(reopened.segment(id)!.animationLoop == nil)
        #expect(reopened.segment(id)!.animationIn == SegmentAnimation(kind: .fade))
    }

    @Test("Dividir mantém o loop nas duas metades")
    func splitKeepsLoop() {
        var (p, id) = textProject {
            $0.animationIn = SegmentAnimation(kind: .cascade)
            $0.animationOut = SegmentAnimation(kind: .wave)
            $0.animationLoop = LoopAnimation(kind: .float)
        }
        let right = TimelineEditor.split(&p, segment: id, at: 1_500_000)!
        let l = p.segment(id)!, r = p.segment(right)!
        #expect(l.animationLoop?.kind == .float && r.animationLoop?.kind == .float)
        #expect(l.animationIn != nil && l.animationOut == nil && r.animationIn == nil && r.animationOut != nil)
    }

    // MARK: - Render

    @Test("Cada tipo novo começa invisível e termina igual ao repouso", arguments: newKinds)
    func entryEndsAtRest(kind: AnimationKind) {
        let (rest, _) = textProject()
        let (p, _) = textProject { $0.animationIn = SegmentAnimation(kind: kind, duration: 500_000) }
        let restInk = ink(render(rest, at: 1_000_000))
        #expect(ink(render(p, at: 0)) < restInk / 20)
        #expect(difference(render(p, at: 500_000), render(rest, at: 500_000)) < size.area / 50)
        #expect(difference(render(p, at: 1_000_000), render(rest, at: 1_000_000)) == 0)
    }

    @Test("Loops mexem na imagem ao longo do tempo", arguments: LoopKind.allCases)
    func loopsChange(kind: LoopKind) {
        let (p, _) = textProject { $0.animationLoop = LoopAnimation(kind: kind, intensity: 1) }
        // Um quarto de ciclo depois do início, o seno está no máximo.
        #expect(difference(render(p, at: 0), render(p, at: 500_000)) > 0)
    }

    @Test("Prévia devolve quadros diferentes, com fundo transparente")
    func previewFrames() throws {
        let content = TextContent(text: "Prévia", style: TextStyle())
        let frames = AnimationPreview.frames(subject: .text(content), part: .entry(.zoomIn), size: CGSize(width: 160, height: 90), count: 12)
        #expect(frames.count == 12)
        #expect(frames.allSatisfy { $0.width == 160 && $0.height == 90 })
        #expect(Set(frames.map(bytes)).count > 6)
        // Canto sem nada: transparente.
        #expect(bytes(frames.last!)[3] == 0)
        // Na entrada, o último quadro já está em repouso e o texto ocupa boa parte da largura.
        let alphaColumns = columnsWithInk(frames.last!)
        #expect(alphaColumns > 160 / 2)

        let exit = AnimationPreview.frames(subject: .text(content), part: .exit(.fade), size: CGSize(width: 160, height: 90), count: 8)
        #expect(exit.count == 8 && bytes(exit[0]) != bytes(exit[7]))
        // 5 quadros por ciclo: fases que não se repetem dentro do ciclo (com 4, o seno só vale 0, 1, 0 e -1).
        let loop = AnimationPreview.frames(subject: .text(content), part: .loop(.float), size: CGSize(width: 160, height: 90), count: 10)
        #expect(loop.count == 10 && Set(loop.map(bytes)).count >= 5)

        // Imagem: encaixada e animada.
        let cg = CIContext().createCGImage(CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)),
                                           from: CGRect(x: 0, y: 0, width: 64, height: 64))!
        let image = AnimationPreview.frames(subject: .image(cg), part: .entry(.slideLeft), size: CGSize(width: 160, height: 90), count: 10)
        #expect(image.count == 10 && Set(image.map(bytes)).count > 5)
        let last = bytes(image.last!)
        let center = (45 * 160 + 80) * 4
        #expect(last[center + 1] > 240 && last[center + 3] == 255)
        #expect(last[3] == 0) // canto: fora da foto quadrada
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func columnsWithInk(_ image: CGImage) -> Int {
        let data = bytes(image)
        return (0..<image.width).filter { x in
            (0..<image.height).contains { y in data[(y * image.width + x) * 4 + 3] > 128 }
        }.count
    }
}

private extension CGSize {
    var area: Int { Int(width * height) }
}
