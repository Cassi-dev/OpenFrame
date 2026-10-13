import AVFoundation
import OpenCutCore
import SwiftUI

struct PreviewPanel: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.35)
                PlayerLayerView(player: model.player)
                    .aspectRatio(model.project.aspectValue, contentMode: .fit)
                    .background(Color.black)
                    .overlay {
                        if model.duration == 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 40))
                                Text("Importe mídia e adicione à timeline")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
            }
            controls
        }
        .background(Theme.background)
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 4) {
                Text(Time.format(model.playhead))
                    .foregroundStyle(Theme.accent)
                Text("/ \(Time.format(model.duration))")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.callout.monospacedDigit())
            .lineLimit(1)
            transportButtons
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.panel)
    }

    private var transportButtons: some View {
        HStack(spacing: 18) {
            Button { model.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
                .help("Início")
            Button { model.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                .help("Quadro anterior (←)")
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 30)
            }
            .help("Reproduzir/pausar (espaço)")
            Button { model.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                .help("Próximo quadro (→)")
            Button { model.seek(to: model.duration) } label: { Image(systemName: "forward.end.fill") }
                .help("Fim")
        }
    }
}

/// Exibe o AVPlayer numa AVPlayerLayer, sem os controles do AVKit.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerNSView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
