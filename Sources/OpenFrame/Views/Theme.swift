import AppKit
import OpenFrameCore
import SwiftUI

/// O SwiftUI também declara `Material`; no app, o nome se refere ao nosso.
typealias Material = OpenFrameCore.Material

enum Theme {
    static let background = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let panelRaised = Color(red: 0.18, green: 0.18, blue: 0.21)
    static let accent = Color(red: 0.0, green: 0.76, blue: 0.80)
    static let videoClip = Color(red: 0.16, green: 0.36, blue: 0.52)
    static let photoClip = Color(red: 0.24, green: 0.42, blue: 0.40)
    static let audioClip = Color(red: 0.13, green: 0.45, blue: 0.30)
    static let textClip = Color(red: 0.55, green: 0.33, blue: 0.70)
    static let playhead = Color.white
}

extension RGBA {
    var color: Color { Color(cgColor: cgColor) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}

/// Slider com rótulo, valor formatado e duplo clique para redefinir.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var defaultValue: Double = 0
    var format: (Double) -> String = { String(format: "%.0f", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { value = defaultValue }
        .help("Clique duas vezes para redefinir")
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionTitle = "Redefinir"

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.top, 6)
    }
}

extension Micros {
    var shortSeconds: String { String(format: "%.1fs", seconds) }
}
