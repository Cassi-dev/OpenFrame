import CoreImage

/// Miniaturas de pré-visualização para os painéis de filtros.
public enum EffectPreview {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    public static func filtered(_ image: CGImage, preset: FilterPreset) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = ImageEffects.filter(input, FilterSetting(preset: preset))
        return context.createCGImage(output, from: input.extent)
    }
}
