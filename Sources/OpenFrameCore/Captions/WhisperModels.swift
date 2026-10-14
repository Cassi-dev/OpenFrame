import CryptoKit
import Foundation

/// Modelos do Whisper oferecidos para as legendas automáticas (formato ggml do whisper.cpp).
public enum WhisperModel: String, CaseIterable, Sendable, Identifiable {
    case base, small
    /// large-v3-turbo quantizado em q5_0.
    case turbo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .base: "Rápido"
        case .small: "Equilibrado"
        case .turbo: "Máxima precisão"
        }
    }

    /// Nome do arquivo no repositório e na pasta local.
    public var fileName: String {
        switch self {
        case .base: "ggml-base.bin"
        case .small: "ggml-small.bin"
        case .turbo: "ggml-large-v3-turbo-q5_0.bin"
        }
    }

    public var byteSize: Int64 {
        switch self {
        case .base: 147_951_465
        case .small: 487_601_967
        case .turbo: 574_041_195
        }
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    public var sha256: String {
        switch self {
        case .base: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
        case .small: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
        case .turbo: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
        }
    }
}

public enum ModelStoreError: LocalizedError, Equatable {
    case http(Int)
    case checksumMismatch
    case sizeMismatch(expected: Int64, got: Int64)

    public var errorDescription: String? {
        switch self {
        case .http(let code): "O servidor do modelo respondeu com o erro \(code)."
        case .checksumMismatch: "O arquivo baixado está corrompido (o sha256 não confere). Tente de novo."
        case .sizeMismatch(let expected, let got):
            "O download veio incompleto (\(got) de \(expected) bytes). Tente de novo."
        }
    }
}

/// Modelos baixados em `~/Library/Application Support/OpenFrame/Models` (a variável de ambiente
/// `OPENFRAME_MODELS_DIR` troca a pasta). O download é o único acesso à rede das legendas.
public final class ModelStore: @unchecked Sendable {
    public static let shared = ModelStore()

    public let directory: URL

    public convenience init() {
        if let custom = ProcessInfo.processInfo.environment["OPENFRAME_MODELS_DIR"], !custom.isEmpty {
            self.init(directory: URL(fileURLWithPath: custom, isDirectory: true))
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.init(directory: support.appendingPathComponent("OpenFrame/Models", isDirectory: true))
        }
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for m: WhisperModel) -> URL {
        directory.appendingPathComponent(m.fileName)
    }

    /// Instalado = o arquivo final existe com o tamanho certo (o sha256 foi conferido ao baixar).
    public func isInstalled(_ m: WhisperModel) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url(for: m).path)
        return (attrs?[.size] as? NSNumber)?.int64Value == m.byteSize
    }

    /// Baixa, confere o sha256 e só então move para o lugar. Cancelável por `Task`: o que já veio
    /// fica guardado e o próximo download continua de onde parou, quando o servidor permite.
    public func download(_ m: WhisperModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await download(from: m.downloadURL, to: url(for: m), size: m.byteSize, sha256: m.sha256, progress: progress)
    }

    public func delete(_ m: WhisperModel) throws {
        let fm = FileManager.default
        for file in [url(for: m), partialURL(url(for: m))] where fm.fileExists(atPath: file.path) {
            try fm.removeItem(at: file)
        }
    }

    // MARK: - Download

    func partialURL(_ destination: URL) -> URL {
        destination.appendingPathExtension("partial")
    }

    /// Baixa em pedaços para um `.partial` (retoma com `Range` se ele já existir), confere tamanho e
    /// sha256 e move para `destination`. Também aceita `file://` (testes).
    func download(from source: URL, to destination: URL, size: Int64, sha256: String,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = partialURL(destination)
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        var have = ((try? fm.attributesOfItem(atPath: partial.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if have > size {
            try Data().write(to: partial)
            have = 0
        }

        if have < size {
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            var request = URLRequest(url: source)
            if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 206: break
                case 200:
                    // O servidor ignorou o Range: recomeça do zero.
                    try handle.truncate(atOffset: 0)
                    have = 0
                default: throw ModelStoreError.http(http.statusCode)
                }
            } else if have > 0 {
                // file:// não tem Range: recomeça.
                try handle.truncate(atOffset: 0)
                have = 0
            }
            try handle.seek(toOffset: UInt64(have))
            progress(Double(have) / Double(size))

            var buffer = Data()
            buffer.reserveCapacity(1 << 20)
            var lastReport = Date.distantPast
            for try await byte in bytes {
                buffer.append(byte)
                guard buffer.count >= 1 << 20 else { continue }
                try Task.checkCancellation()
                try handle.write(contentsOf: buffer)
                have += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.1 {
                    lastReport = Date()
                    progress(min(1, Double(have) / Double(size)))
                }
            }
            try handle.write(contentsOf: buffer)
            have += Int64(buffer.count)
        }

        guard have == size else {
            // Um arquivo maior que o esperado não serve para retomar.
            if have > size { try? fm.removeItem(at: partial) }
            throw ModelStoreError.sizeMismatch(expected: size, got: have)
        }
        try Task.checkCancellation()
        guard try Self.sha256(of: partial) == sha256.lowercased() else {
            try? fm.removeItem(at: partial)
            throw ModelStoreError.checksumMismatch
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: partial, to: destination)
        progress(1)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
