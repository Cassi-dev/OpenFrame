import CoreImage
import Foundation

// Mede o ImageEffects/Transitions do Swift em manchas de cor e grava as cores
// resultantes (sRGB 8 bits) em qt/tests/fixtures/efeitos.json. A versão Qt
// compara o próprio render com esses números. Uso: qt/tests/tools/gerar-efeitos.sh

// Com um segundo argumento "denso", usa uma grade 9×9×9 (para ajustar modelos; não vai para o repositório).
let dense = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "denso"
let colors: [[Double]] = {
    if dense {
        let levels = (0...8).map { Double($0) / 8 }
        return levels.flatMap { r in levels.flatMap { g in levels.map { b in [r, g, b] } } }
    }
    var c: [[Double]] = []
    for r in [0.0, 0.5, 1.0] { for g in [0.0, 0.5, 1.0] { for b in [0.0, 0.5, 1.0] { c.append([r, g, b]) } } }
    for v in stride(from: 0.125, through: 0.875, by: 0.125) where v != 0.5 { c.append([v, v, v]) }
    c += [[0.9, 0.2, 0.2], [0.2, 0.6, 0.3], [0.85, 0.65, 0.5], [0.4, 0.3, 0.25], [0.3, 0.45, 0.8], [0.95, 0.85, 0.2]]
    return c
}()
let side = 16
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext()

func patches(_ cs: [[Double]]) -> CIImage {
    var image = CIImage.empty()
    for (i, c) in cs.enumerated() {
        let color = CIColor(red: c[0], green: c[1], blue: c[2], alpha: 1, colorSpace: srgb)!
        image = CIImage(color: color).cropped(to: CGRect(x: i * side, y: 0, width: side, height: side)).composited(over: image)
    }
    return image
}

func read(_ image: CIImage, count: Int) -> [[Int]] {
    let w = count * side
    var bytes = [UInt8](repeating: 0, count: w * side * 4)
    context.render(image, toBitmap: &bytes, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: side),
                   format: .RGBA8, colorSpace: srgb)
    return (0..<count).map { i in
        let p = ((side / 2) * w + i * side + side / 2) * 4
        return [Int(bytes[p]), Int(bytes[p + 1]), Int(bytes[p + 2])]
    }
}

var cases: [[String: Any]] = []
func record(_ name: String, _ op: (CIImage) -> CIImage) {
    // Cada mancha é processada sozinha, para não misturar vizinhas.
    let out = colors.map { c -> [Int] in
        let img = patches([c])
        return read(op(img).cropped(to: img.extent), count: 1)[0]
    }
    cases.append(["name": name, "output": out])
}

let adjustKeys: [(String, WritableKeyPath<Adjust, Double>, [Double])] = [
    ("brightness", \.brightness, [-1, -0.5, 0.5, 1]),
    ("contrast", \.contrast, [-1, -0.5, 0.5, 1]),
    ("saturation", \.saturation, [-1, -0.5, 0.5, 1]),
    ("exposure", \.exposure, [-1, -0.5, 0.5, 1]),
    ("temperature", \.temperature, [-1, -0.5, 0.5, 1]),
    ("tint", \.tint, [-1, -0.5, 0.5, 1]),
    ("highlights", \.highlights, [-1, -0.5, 0.5, 1]),
    ("shadows", \.shadows, [-1, -0.5, 0.5, 1]),
    ("hue", \.hue, [-1, -0.5, -0.25, 0.25, 0.5, 1]),
    ("fade", \.fade, [0.5, 1]),
]
for (key, path, values) in adjustKeys {
    for v in values {
        var a = Adjust()
        a[keyPath: path] = v
        record("adjust.\(key)=\(v)") { ImageEffects.adjust($0, a, k: 1, time: 0) }
    }
}
for preset in FilterPreset.allCases where preset != .none {
    for intensity in [1.0, 0.5] {
        record("filter.\(preset.rawValue)=\(intensity)") { ImageEffects.filter($0, FilterSetting(preset: preset, intensity: intensity)) }
    }
}
for t in [0.0, 0.1, 0.2] {
    record("effect.flash@\(t)") { ImageEffects.effects($0, [VideoEffect(kind: .flash, intensity: 0.5)], k: 1, time: t) }
}
// Composição em luz linear: cor a 50% sobre preto e dissolver contra o vermelho.
for alpha in [0.25, 0.5, 0.75] {
    record("opacity=\(alpha)") { img in
        img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
            .composited(over: CIImage(color: .black).cropped(to: img.extent))
    }
}
let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1, colorSpace: srgb)!)
for p in [0.25, 0.5, 0.75] {
    record("dissolve@\(p)") { img in
        Transitions.apply(.dissolve, from: img, to: red.cropped(to: img.extent), progress: p, canvas: img.extent, k: 1)
    }
    record("fadeBlack@\(p)") { img in
        Transitions.apply(.fadeBlack, from: img, to: red.cropped(to: img.extent), progress: p, canvas: img.extent, k: 1)
    }
    record("fadeWhite@\(p)") { img in
        Transitions.apply(.fadeWhite, from: img, to: red.cropped(to: img.extent), progress: p, canvas: img.extent, k: 1)
    }
}
record("blurBackgroundBrightness") { $0.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.08]) }

let json: [String: Any] = ["colors": colors.map { $0.map { Int(($0 * 255).rounded()) } }, "cases": cases]
let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("ok: \(cases.count) casos, \(colors.count) cores")
