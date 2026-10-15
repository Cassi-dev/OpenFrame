import AVFoundation

/// Áudio do projeto como a exportação ouve (a mesma composição e o mesmo `audioMix`: volume,
/// mudo, velocidade, fades, faixas de áudio), em mono Float32 a 16 kHz para o Whisper.
enum AudioMixdown {
    static let sampleRate = 16_000.0

    /// Amostras do trecho `range` da timeline; a amostra 0 é `range.start`. Trechos sem áudio
    /// ficam em silêncio. `nil` quando não há nenhuma faixa de áudio no trecho.
    static func samples(project: Project, range: TimeRange, progress: @escaping (Double) -> Void) async throws -> [Float]? {
        let built = try await CompositionBuilder.build(project: project, renderSize: CGSize(width: 16, height: 16),
                                                       frameDuration: CMTime(value: 1, timescale: 30))
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty, range.duration > 0 else { return nil }

        let reader = try AVAssetReader(asset: built.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = built.audioMix
        output.audioTimePitchAlgorithm = .spectral
        guard reader.canAdd(output) else { throw TranscriptionError.failed("não foi possível ler o áudio") }
        reader.add(output)
        reader.timeRange = range.cmTimeRange
        guard reader.startReading() else {
            throw TranscriptionError.failed(reader.error?.localizedDescription ?? "não foi possível ler o áudio")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }

        let count = Int((Double(range.duration) / 1_000_000 * sampleRate).rounded())
        var samples = [Float](repeating: 0, count: count)
        var lastReport = Date.distantPast
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            // Cada pedaço vai para o lugar do seu tempo: vãos na composição viram silêncio.
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
            let offset = Int(((pts.seconds - range.start.seconds) * sampleRate).rounded())
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let n = length / MemoryLayout<Float>.size
            let from = max(0, -offset)
            let to = min(n, count - offset)
            if from < to {
                var floats = [Float](repeating: 0, count: n)
                guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * MemoryLayout<Float>.size,
                                                 destination: &floats) == kCMBlockBufferNoErr else { continue }
                samples.withUnsafeMutableBufferPointer { dst in
                    floats.withUnsafeBufferPointer { src in
                        (dst.baseAddress! + offset + from).update(from: src.baseAddress! + from, count: to - from)
                    }
                }
            }
            if Date().timeIntervalSince(lastReport) > 0.1 {
                lastReport = Date()
                progress(min(1, Double(offset + n) / Double(max(count, 1))))
            }
        }
        if reader.status == .failed {
            throw TranscriptionError.failed(reader.error?.localizedDescription ?? "não foi possível ler o áudio")
        }
        progress(1)
        return samples
    }
}
