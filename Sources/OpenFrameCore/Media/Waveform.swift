import AVFoundation

/// Picos de amplitude de um arquivo, para desenhar a forma de onda na timeline.
public enum Waveform {
    /// Picos por segundo de mídia; suficiente até o zoom máximo da timeline.
    public static let peaksPerSecond = 50.0

    /// Lê o áudio inteiro (mixado em mono) e devolve um pico por intervalo,
    /// normalizado entre 0 e 1 pelo maior pico do arquivo.
    public static func peaks(url: URL, perSecond: Double = peaksPerSecond) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let sampleRate = 8000.0
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaError.unreadable(url.lastPathComponent) }

        let bucket = max(1, Int(sampleRate / perSecond))
        var peaks: [Float] = []
        var current: Float = 0
        var filled = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            for sample in samples {
                current = max(current, abs(sample))
                filled += 1
                if filled == bucket {
                    peaks.append(current)
                    current = 0
                    filled = 0
                }
            }
        }
        if reader.status == .failed { throw reader.error ?? MediaError.unreadable(url.lastPathComponent) }
        if filled > 0 { peaks.append(current) }
        let top = peaks.max() ?? 0
        return top > 0 ? peaks.map { $0 / top } : peaks
    }
}
