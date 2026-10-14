import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaError: LocalizedError {
    case unsupported(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let name): "Formato não suportado: \(name)"
        case .unreadable(let name): "Não foi possível ler: \(name)"
        }
    }
}

public enum MediaProbe {
    /// Se o arquivo é uma mídia que o `probe` aceita (foto, vídeo ou áudio),
    /// pela extensão, sem diferenciar maiúsculas (`.MOV` do iPhone).
    public static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent)
    }

    /// Lê o arquivo e cria o `Material` correspondente.
    public static func probe(_ url: URL) async throws -> Material {
        let name = url.lastPathComponent
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            throw MediaError.unsupported(name)
        }
        if type.conforms(to: .image) {
            return try probeImage(url)
        }
        if type.conforms(to: .audiovisualContent) {
            return try await probeAV(url, isAudioOnlyType: type.conforms(to: .audio))
        }
        throw MediaError.unsupported(name)
    }

    private static func probeImage(_ url: URL) throws -> Material {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw MediaError.unreadable(url.lastPathComponent) }
        // Orientações 5–8 giram a imagem em 90°.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = orientation >= 5
        return Material(kind: .photo, path: url.path, name: url.lastPathComponent, duration: 0,
                        width: rotated ? h : w, height: rotated ? w : h, hasAudio: false)
    }

    private static func probeAV(_ url: URL, isAudioOnlyType: Bool) async throws -> Material {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let name = url.lastPathComponent
        if let video = videoTracks.first, !isAudioOnlyType {
            let (size, transform) = try await video.load(.naturalSize, .preferredTransform)
            let display = size.applying(transform)
            return Material(kind: .video, path: url.path, name: name, duration: duration.micros,
                            width: Int(abs(display.width).rounded()), height: Int(abs(display.height).rounded()),
                            hasAudio: !audioTracks.isEmpty)
        }
        guard !audioTracks.isEmpty else { throw MediaError.unreadable(name) }
        return Material(kind: .audio, path: url.path, name: name, duration: duration.micros,
                        width: 0, height: 0, hasAudio: true)
    }
}
