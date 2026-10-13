import CoreImage
import Foundation

/// Ajustes, filtros e efeitos aplicados à imagem de um clipe, antes do
/// posicionamento no canvas. `k` = altura do canvas / 1080, para que raios de
/// desfoque etc. tenham o mesmo aspecto em qualquer resolução.
enum ImageEffects {
    // MARK: - Ajustar

    static func adjust(_ input: CIImage, _ a: Adjust, k: CGFloat, time: Double) -> CIImage {
        guard !a.isIdentity else { return input }
        let extent = input.extent
        var img = input

        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            img = img.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: a.brightness * 0.25,
                kCIInputContrastKey: 1 + a.contrast * 0.5,
                kCIInputSaturationKey: max(0, 1 + a.saturation),
            ])
        }
        if a.exposure != 0 {
            img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: a.exposure * 1.5])
        }
        if a.temperature != 0 || a.tint != 0 {
            img = img.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                // Ponto neutro alvo mais baixo (em Kelvin) deixa a imagem mais quente.
                "inputTargetNeutral": CIVector(x: 6500 - a.temperature * 2500, y: -a.tint * 60),
            ])
        }
        if a.highlights != 0 || a.shadows != 0 {
            img = img.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 0.25, y: 0.25 + a.shadows * 0.12),
                "inputPoint2": CIVector(x: 0.5, y: 0.5 + (a.shadows + a.highlights) * 0.03),
                "inputPoint3": CIVector(x: 0.75, y: 0.75 + a.highlights * 0.12),
                "inputPoint4": CIVector(x: 1, y: 1),
            ])
        }
        if a.hue != 0 {
            img = img.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: a.hue * .pi])
        }
        if a.fade > 0 {
            let m = 1 - a.fade * 0.3
            let bias = a.fade * 0.15
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: m, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: m, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: m, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ])
        }
        if a.sharpen > 0 {
            img = img.clampedToExtent().applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: a.sharpen * 1.5,
                kCIInputRadiusKey: 1.5 * k,
            ]).cropped(to: extent)
        }
        if a.vignette > 0 {
            img = img.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputRadiusKey: max(extent.width, extent.height) * 0.55,
                kCIInputIntensityKey: a.vignette,
                "inputFalloff": 0.6,
            ])
        }
        if a.grain > 0 {
            img = grain(over: img, amount: a.grain, time: time)
        }
        return img.cropped(to: extent)
    }

    /// Granulado: ruído cinza semitransparente, deslocado a cada quadro.
    private static func grain(over img: CIImage, amount: Double, time: Double) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return img }
        let frame = (time * 30).rounded()
        let offset = CGAffineTransform(translationX: CGFloat(frame * 137).truncatingRemainder(dividingBy: 997),
                                       y: CGFloat(frame * 71).truncatingRemainder(dividingBy: 991))
        let gray = noise.transformed(by: offset).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: amount * 0.25),
        ]).cropped(to: img.extent)
        return gray.composited(over: img)
    }

    // MARK: - Filtros

    static func filter(_ input: CIImage, _ setting: FilterSetting) -> CIImage {
        guard setting.preset != .none, setting.intensity > 0 else { return input }
        let extent = input.extent
        let filtered: CIImage
        switch setting.preset {
        case .none:
            return input
        case .mono: filtered = input.applyingFilter("CIPhotoEffectMono")
        case .noir: filtered = input.applyingFilter("CIPhotoEffectNoir")
        case .chrome: filtered = input.applyingFilter("CIPhotoEffectChrome")
        case .fade: filtered = input.applyingFilter("CIPhotoEffectFade")
        case .instant: filtered = input.applyingFilter("CIPhotoEffectInstant")
        case .process: filtered = input.applyingFilter("CIPhotoEffectProcess")
        case .tonal: filtered = input.applyingFilter("CIPhotoEffectTonal")
        case .transfer: filtered = input.applyingFilter("CIPhotoEffectTransfer")
        case .sepia: filtered = input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 1.0])
        case .vivid:
            filtered = input
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35, kCIInputContrastKey: 1.08])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.4])
        case .warm:
            var a = Adjust()
            a.temperature = 0.6
            a.saturation = 0.1
            filtered = adjust(input, a, k: 1, time: 0)
        case .cool:
            var a = Adjust()
            a.temperature = -0.6
            a.tint = 0.1
            filtered = adjust(input, a, k: 1, time: 0)
        case .cinematic:
            // Sombras puxadas para o azul-esverdeado, tons de pele para o laranja.
            filtered = input
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.08, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1.0, z: 0.04, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0.08, z: 0.92, w: 0),
                    "inputBiasVector": CIVector(x: -0.02, y: 0.0, z: 0.04, w: 0),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.12, kCIInputSaturationKey: 0.9])
        case .vintage:
            var a = Adjust()
            a.fade = 0.5
            a.vignette = 0.6
            filtered = adjust(input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.45]), a, k: 1, time: 0)
        }
        let cropped = filtered.cropped(to: extent)
        guard setting.intensity < 1 else { return cropped }
        return input.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: cropped,
            kCIInputTimeKey: setting.intensity,
        ]).cropped(to: extent)
    }

    // MARK: - Efeitos

    static func effects(_ input: CIImage, _ effects: [VideoEffect], k: CGFloat, time: Double) -> CIImage {
        var img = input
        let extent = input.extent
        for effect in effects {
            let v = effect.intensity
            switch effect.kind {
            case .blur:
                img = img.clampedToExtent().applyingGaussianBlur(sigma: v * 25 * k).cropped(to: extent)
            case .pixelate:
                img = img.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: max(2, v * 48 * k),
                    kCIInputCenterKey: CIVector(x: extent.minX, y: extent.minY),
                ]).cropped(to: extent)
            case .rgbSplit:
                let jitter = 0.6 + 0.4 * sin(time * 23) * sin(time * 7)
                img = rgbSplit(img, offset: v * 18 * k * jitter).cropped(to: extent)
            case .mirror:
                let half = CGRect(x: extent.minX, y: extent.minY, width: extent.width / 2, height: extent.height)
                let mirrored = img.cropped(to: half).transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * extent.midX, ty: 0))
                img = mirrored.composited(over: img).cropped(to: extent)
            case .flash:
                let phase = (time * (1 + v * 3)).truncatingRemainder(dividingBy: 1)
                let strength = max(0, 1 - phase * 4) * 0.85
                if strength > 0 {
                    img = img.applyingFilter("CIColorMatrix", parameters: [
                        "inputBiasVector": CIVector(x: strength, y: strength, z: strength, w: 0),
                    ])
                }
            case .kaleidoscope:
                img = img.applyingFilter("CIKaleidoscope", parameters: [
                    "inputCount": Int(3 + v * 9),
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                    kCIInputAngleKey: time * 0.3,
                ]).cropped(to: extent)
            case .comic:
                img = img.applyingFilter("CIComicEffect").cropped(to: extent)
            case .edges:
                let edges = img.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1 + v * 9])
                let dark = img.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.25 * v])
                img = edges.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: dark]).cropped(to: extent)
            case .shake, .zoomPulse:
                break // geométricos: ver `geometry`
            }
        }
        return img
    }

    private static func rgbSplit(_ img: CIImage, offset: Double) -> CIImage {
        // Cada canal mantém o alfa original: com alfa 0 a cor pré-multiplicada
        // zeraria. A soma satura o alfa em 1, o que só altera bordas semitransparentes.
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
        let red = channel(1, 0, 0).transformed(by: CGAffineTransform(translationX: offset, y: 0))
        let green = channel(0, 1, 0)
        let blue = channel(0, 0, 1).transformed(by: CGAffineTransform(translationX: -offset, y: 0))
        return red
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
    }

    /// Deslocamento (em unidades normalizadas do canvas) e escala dos efeitos geométricos.
    static func geometry(_ effects: [VideoEffect], time: Double) -> (dx: Double, dy: Double, scale: Double) {
        var dx = 0.0, dy = 0.0, scale = 1.0
        for effect in effects {
            let v = effect.intensity
            switch effect.kind {
            case .shake:
                dx += (sin(time * 41) + sin(time * 67) * 0.5) * v * 0.025
                dy += (cos(time * 53) + sin(time * 29) * 0.5) * v * 0.025
                scale *= 1 + v * 0.06 // evita bordas pretas durante o tremor
            case .zoomPulse:
                scale *= 1 + v * 0.12 * (0.5 + 0.5 * sin(time * 2 * .pi * 2))
            default:
                break
            }
        }
        return (dx, dy, scale)
    }
}
