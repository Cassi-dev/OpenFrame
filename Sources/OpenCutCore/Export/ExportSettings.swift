import AVFoundation
import VideoToolbox

// As opções espelham a tela de exportação do CapCut, levantadas via REA no
// `ExportViewModel` (resolutionList, frameRateList, bitrateList, customBitrate,
// encoder/HEVC/ProRes, formatList, getEstimatedInformation).

public enum ResolutionPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case p480, p720, p1080, p1440, p2160, p4320, custom

    public var id: String { rawValue }

    /// Lado menor do vídeo em pixels.
    public var shortSide: Int? {
        switch self {
        case .p480: 480
        case .p720: 720
        case .p1080: 1080
        case .p1440: 1440
        case .p2160: 2160
        case .p4320: 4320
        case .custom: nil
        }
    }

    public var label: String {
        switch self {
        case .p480: "480p"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "2K"
        case .p2160: "4K"
        case .p4320: "8K"
        case .custom: "Personalizada"
        }
    }
}

public enum FrameRate: String, Codable, CaseIterable, Sendable, Identifiable {
    case fps23_976, fps24, fps25, fps29_97, fps30, fps50, fps59_94, fps60, fps120

    public var id: String { rawValue }

    public var frameDuration: CMTime {
        switch self {
        case .fps23_976: CMTime(value: 1001, timescale: 24000)
        case .fps24: CMTime(value: 1, timescale: 24)
        case .fps25: CMTime(value: 1, timescale: 25)
        case .fps29_97: CMTime(value: 1001, timescale: 30000)
        case .fps30: CMTime(value: 1, timescale: 30)
        case .fps50: CMTime(value: 1, timescale: 50)
        case .fps59_94: CMTime(value: 1001, timescale: 60000)
        case .fps60: CMTime(value: 1, timescale: 60)
        case .fps120: CMTime(value: 1, timescale: 120)
        }
    }

    public var value: Double { 1 / frameDuration.seconds }

    public var label: String {
        switch self {
        case .fps23_976: "23,976 fps"
        case .fps24: "24 fps"
        case .fps25: "25 fps"
        case .fps29_97: "29,97 fps"
        case .fps30: "30 fps"
        case .fps50: "50 fps"
        case .fps59_94: "59,94 fps"
        case .fps60: "60 fps"
        case .fps120: "120 fps"
        }
    }
}

public enum VideoCodec: String, Codable, CaseIterable, Sendable, Identifiable {
    case h264, hevc, proRes422

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC (H.265)"
        case .proRes422: "Apple ProRes 422"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .proRes422: .proRes422
        }
    }

    /// Bits por pixel por quadro na qualidade "Recomendada".
    var recommendedBitsPerPixel: Double {
        switch self {
        case .h264: 0.1
        case .hevc: 0.065
        case .proRes422: 2.36 // ~147 Mbps em 1080p30 (ProRes não usa bitrate alvo)
        }
    }

    /// Maior lado suportado pelo codificador de hardware.
    var maxDimension: Int {
        switch self {
        case .h264: 4096
        case .hevc, .proRes422: 8192
        }
    }
}

public enum ContainerFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case mp4, mov, m4a

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mp4: "MP4"
        case .mov: "MOV"
        case .m4a: "M4A (só áudio)"
        }
    }

    public var fileExtension: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .mp4: .mp4
        case .mov: .mov
        case .m4a: .m4a
        }
    }

    public var isAudioOnly: Bool { self == .m4a }
}

public enum BitrateMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case lower, recommended, higher, custom, targetSize

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lower: "Mais baixa"
        case .recommended: "Recomendada"
        case .higher: "Mais alta"
        case .custom: "Bitrate personalizado"
        case .targetSize: "Tamanho de arquivo alvo"
        }
    }
}

public struct ExportSettings: Codable, Hashable, Sendable {
    public var resolution = ResolutionPreset.p1080
    public var customWidth = 1920
    public var customHeight = 1080
    public var frameRate = FrameRate.fps30
    public var codec = VideoCodec.h264
    public var container = ContainerFormat.mp4
    public var bitrateMode = BitrateMode.recommended
    /// Usado em `.custom`, em Mbps.
    public var customMbps: Double = 10
    /// Usado em `.targetSize`, em MB.
    public var targetMegabytes: Double = 50
    /// Intervalo entre quadros-chave, em segundos.
    public var keyframeInterval: Double = 2
    public var audioEnabled = true
    public var audioKbps = 192
    public var audioSampleRate = 48000

    public init() {}

    public static let audioBitrates = [96, 128, 192, 256, 320]
    public static let sampleRates = [44100, 48000]

    // MARK: - Cálculos

    /// Dimensões finais do vídeo (sempre pares, como exigem os codificadores).
    public func outputSize(for project: Project) -> CGSize {
        func even(_ v: Int) -> Int { max(2, v / 2 * 2) }
        guard let short = resolution.shortSide else {
            return CGSize(width: even(customWidth), height: even(customHeight))
        }
        return project.canvasSize(shortSide: short)
    }

    /// Bitrate médio de vídeo em bits/s.
    public func videoBitrate(size: CGSize, duration: Micros) -> Int {
        let pixelsPerSecond = Double(size.width * size.height) * frameRate.value
        let recommended = pixelsPerSecond * codec.recommendedBitsPerPixel
        let bps: Double
        switch bitrateMode {
        case .lower: bps = recommended * 0.55
        case .recommended: bps = recommended
        case .higher: bps = recommended * 1.8
        case .custom: bps = customMbps * 1_000_000
        case .targetSize:
            let seconds = max(duration.seconds, 0.1)
            let audio = audioEnabled ? Double(audioKbps * 1000) : 0
            bps = targetMegabytes * 8_000_000 / seconds - audio
        }
        return Int(min(max(bps, 100_000), 800_000_000))
    }

    /// Tamanho estimado do arquivo em bytes (vídeo + áudio + ~1% de contêiner).
    public func estimatedBytes(for project: Project) -> Int64 {
        let duration = project.duration
        let audio = audioEnabled ? Double(audioKbps * 1000) : 0
        let video = container.isAudioOnly ? 0 : Double(videoBitrate(size: outputSize(for: project), duration: duration))
        return Int64((video + audio) * duration.seconds / 8 * 1.01)
    }

    /// Mensagem de erro se a combinação não puder ser exportada.
    public func validationError(for project: Project) -> String? {
        if project.duration <= 0 { return "A timeline está vazia." }
        if container.isAudioOnly { return audioEnabled ? nil : "Ative o áudio para exportar M4A." }
        let size = outputSize(for: project)
        if size.width < 16 || size.height < 16 { return "Resolução muito pequena." }
        if Int(max(size.width, size.height)) > codec.maxDimension {
            return "\(codec.label) suporta até \(codec.maxDimension) px no lado maior. Use HEVC ou ProRes, ou reduza a resolução."
        }
        if codec == .proRes422, container != .mov { return "ProRes só pode ser exportado em MOV." }
        return nil
    }

    func videoOutputSettings(size: CGSize, duration: Micros) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        guard codec != .proRes422 else { return settings }
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: videoBitrate(size: size, duration: duration),
            AVVideoExpectedSourceFrameRateKey: Int(frameRate.value.rounded()),
            AVVideoMaxKeyFrameIntervalKey: max(1, Int((frameRate.value * keyframeInterval).rounded())),
        ]
        switch codec {
        case .h264:
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        case .hevc:
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        case .proRes422:
            break
        }
        settings[AVVideoCompressionPropertiesKey] = compression
        return settings
    }

    var audioOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: audioKbps * 1000,
        ]
    }

    var audioReaderSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }
}

public extension Int64 {
    /// "12,3 MB" etc.
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
