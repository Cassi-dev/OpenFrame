import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Forma de onda")
struct WaveformTests {
    @Test("Um pico por intervalo, normalizado")
    func peaksFollowDuration() async throws {
        let url = try await TestMedia.makeVideo(seconds: 2, audio: true)
        let peaks = try await Waveform.peaks(url: url, perSecond: 20)
        // 2 s a 20 picos/s; o AAC pode acrescentar alguns quadros de silêncio.
        #expect((40...44).contains(peaks.count))
        #expect(peaks.max() == 1)
        // Seno de amplitude constante: o meio do arquivo fica perto do topo.
        #expect(peaks[10..<30].allSatisfy { $0 > 0.8 })
    }

    @Test("Vídeo sem áudio não tem picos")
    func silentVideo() async throws {
        let url = try await TestMedia.makeVideo(seconds: 1, audio: false)
        #expect(try await Waveform.peaks(url: url).isEmpty)
    }
}
