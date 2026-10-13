import Foundation

public struct SubtitleCue: Hashable, Sendable {
    public var start: Micros
    public var end: Micros
    public var text: String

    public init(start: Micros, end: Micros, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Leitura e escrita de legendas SubRip (.srt).
public enum SRT {
    public static func parse(_ content: String) -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]), end > start
            else { continue }
            let text = lines[(timingIndex + 1)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// Aceita `HH:MM:SS,mmm` e `HH:MM:SS.mmm` (ignora posicionamento após o horário).
    static func parseTimestamp(_ raw: String) -> Micros? {
        let token = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let pieces = token.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard pieces.count == 3,
              let h = Double(pieces[0]), let m = Double(pieces[1]), let s = Double(pieces[2])
        else { return nil }
        return Time.seconds(h * 3600 + m * 60 + s)
    }

    public static func serialize(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { i, cue in
            "\(i + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func timestamp(_ t: Micros) -> String {
        let ms = max(0, t / 1000)
        return String(format: "%02lld:%02lld:%02lld,%03lld", ms / 3_600_000, (ms / 60000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// Converte as legendas em segmentos de texto numa faixa nova.
    public static func importCues(_ cues: [SubtitleCue], into p: inout Project, style: TextStyle = TextStyle()) {
        guard !cues.isEmpty else { return }
        var track = Track(kind: .text)
        track.segments = cues.map {
            Segment.text(TextContent(text: $0.text, style: style), at: $0.start,
                         duration: max(TimelineEditor.minDuration, $0.end - $0.start))
        }
        p.tracks.append(track)
    }

    /// Coleta todos os segmentos de texto do projeto como legendas.
    public static func cues(from p: Project) -> [SubtitleCue] {
        p.tracks.filter { $0.kind == .text && !$0.hidden }
            .flatMap(\.segments)
            .compactMap { s in s.text.map { SubtitleCue(start: s.targetStart, end: s.targetEnd, text: $0.text) } }
            .sorted { $0.start < $1.start }
    }
}
