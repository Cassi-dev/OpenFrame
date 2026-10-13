import AVFoundation

public enum ExportError: LocalizedError {
    case invalid(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .failed(let message): message
        }
    }
}

/// Exporta com AVAssetReader → AVAssetWriter. Diferente do
/// AVAssetExportSession, esse caminho permite escolher bitrate, fps,
/// codec, intervalo de quadros-chave e áudio livremente.
public final class Exporter: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        let reader = reader
        lock.unlock()
        reader?.cancelReading()
    }

    /// Guarda o leitor/gravador para `cancel()`; retorna false se já foi cancelado.
    private func register(reader: AVAssetReader, writer: AVAssetWriter) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.reader = reader
        self.writer = writer
        return !cancelled
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func export(project: Project, settings: ExportSettings, to url: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        if let message = settings.validationError(for: project) { throw ExportError.invalid(message) }

        let audioOnly = settings.container.isAudioOnly
        let size = settings.outputSize(for: project)
        let built = try await CompositionBuilder.build(project: project, renderSize: size,
                                                       frameDuration: settings.frameRate.frameDuration,
                                                       includeAudio: settings.audioEnabled)
        let composition = built.composition
        try? FileManager.default.removeItem(at: url)

        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: built.duration.cmTime)
        let writer = try AVAssetWriter(outputURL: url, fileType: settings.container.fileType)
        writer.shouldOptimizeForNetworkUse = true

        var pairs: [(output: AVAssetReaderOutput, input: AVAssetWriterInput, isVideo: Bool)] = []

        if !audioOnly {
            let videoOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: composition.tracks(withMediaType: .video),
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            videoOutput.videoComposition = built.videoComposition
            videoOutput.alwaysCopiesSampleData = false
            let videoInput = AVAssetWriterInput(mediaType: .video,
                                                outputSettings: settings.videoOutputSettings(size: size, duration: built.duration))
            videoInput.expectsMediaDataInRealTime = false
            videoInput.mediaTimeScale = settings.frameRate.frameDuration.timescale
            guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
                throw ExportError.invalid("Configuração de vídeo não suportada por este Mac.")
            }
            reader.add(videoOutput)
            writer.add(videoInput)
            pairs.append((videoOutput, videoInput, true))
        }

        let audioTracks = composition.tracks(withMediaType: .audio)
        if settings.audioEnabled, !audioTracks.isEmpty {
            let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: settings.audioReaderSettings)
            audioOutput.audioMix = built.audioMix
            audioOutput.audioTimePitchAlgorithm = .spectral
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings.audioOutputSettings)
            audioInput.expectsMediaDataInRealTime = false
            guard reader.canAdd(audioOutput), writer.canAdd(audioInput) else {
                throw ExportError.invalid("Configuração de áudio não suportada.")
            }
            reader.add(audioOutput)
            writer.add(audioInput)
            pairs.append((audioOutput, audioInput, false))
        } else if audioOnly {
            throw ExportError.invalid("O projeto não tem áudio para exportar.")
        }

        if !register(reader: reader, writer: writer) { throw CancellationError() }

        guard reader.startReading() else {
            throw ExportError.failed(reader.error?.localizedDescription ?? "Falha ao iniciar a leitura.")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw ExportError.failed(writer.error?.localizedDescription ?? "Falha ao iniciar a gravação.")
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = max(built.duration.seconds, 0.001)
        let progressLane = audioOnly ? false : true
        let group = DispatchGroup()
        for (index, pair) in pairs.enumerated() {
            group.enter()
            let queue = DispatchQueue(label: "opencut.export.\(index)")
            var finished = false
            pair.input.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard !finished else { return }
                while pair.input.isReadyForMoreMediaData {
                    let stop = self?.isCancelled ?? true
                    guard !stop, reader.status == .reading, let sample = pair.output.copyNextSampleBuffer() else {
                        finished = true
                        pair.input.markAsFinished()
                        group.leave()
                        return
                    }
                    if pair.isVideo == progressLane {
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        progress(min(max(t / totalSeconds, 0), 1))
                    }
                    if !pair.input.append(sample) {
                        finished = true
                        reader.cancelReading()
                        pair.input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { continuation.resume() }
        }

        if isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        if reader.status == .failed || writer.status == .failed {
            let message = writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Erro desconhecido."
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(message)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(writer.error?.localizedDescription ?? "Falha ao finalizar o arquivo.")
        }
        progress(1)
    }
}
