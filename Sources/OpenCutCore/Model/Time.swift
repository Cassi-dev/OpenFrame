import CoreMedia

/// Tempo em microssegundos — a mesma unidade que o CapCut usa nos campos
/// `start`/`duration` do `draft_content.json`.
public typealias Micros = Int64

public enum Time {
    public static let second: Micros = 1_000_000

    public static func seconds(_ s: Double) -> Micros {
        Micros((s * 1_000_000).rounded())
    }

    /// Formata como `mm:ss.cc` (ou `h:mm:ss.cc` acima de uma hora).
    public static func format(_ t: Micros) -> String {
        let total = max(0, Double(t) / 1_000_000)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        let centis = Int((total - total.rounded(.down)) * 100)
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centis)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, centis)
    }
}

public extension Int64 {
    var cmTime: CMTime { CMTime(value: self, timescale: 1_000_000) }
    var seconds: Double { Double(self) / 1_000_000 }
}

public extension CMTime {
    var micros: Micros {
        guard isValid, isNumeric else { return 0 }
        return Micros((seconds * 1_000_000).rounded())
    }
}

public struct TimeRange: Codable, Hashable, Sendable {
    public var start: Micros
    public var duration: Micros

    public init(start: Micros, duration: Micros) {
        self.start = start
        self.duration = duration
    }

    public var end: Micros { start + duration }

    public func contains(_ t: Micros) -> Bool { t >= start && t < end }

    public var cmTimeRange: CMTimeRange {
        CMTimeRange(start: start.cmTime, duration: duration.cmTime)
    }
}
