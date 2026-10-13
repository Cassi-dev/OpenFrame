import AVFoundation
import OpenFrameCore
import SwiftUI

struct PreviewPanel: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PlayerLayerView(player: model.player)
                    .aspectRatio(model.project.aspectValue, contentMode: .fit)
                    .overlay {
                        if model.showGrid { ThirdsGrid().allowsHitTesting(false) }
                    }
                    .overlay {
                        if model.duration == 0 { emptyState }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding([.horizontal, .top], 18)
            TransportBar()
                .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            LogoMark(frameColor: Theme.textTertiary, litColor: Theme.accent.opacity(0.6))
                .frame(width: 54, height: 54)
            Text("Importe mídia e adicione à timeline")
                .foregroundStyle(Theme.textSecondary)
            Button("Importar mídia") { model.presentImportPanel() }
                .buttonStyle(PillButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Grade dos terços, no ciano da marca.
private struct ThirdsGrid: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(Theme.accent.opacity(0.55)), lineWidth: 0.75)
        }
    }
}

/// Cápsula de transporte: tempo, controles e ferramentas de visualização.
private struct TransportBar: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Time.format(model.playhead))
                    .font(Theme.mono(17, .light))
                    .foregroundStyle(Theme.textPrimary)
                Text(Time.format(model.duration))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 128, alignment: .leading)
            .lineLimit(1)

            divider

            HStack(spacing: 6) {
                Button { model.seek(to: 0) } label: { Image(systemName: "backward.end") }
                    .help("Início")
                Button { model.step(frames: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Quadro anterior (←)")
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .offset(x: model.isPlaying ? 0 : 1)
                }
                .buttonStyle(CircleButtonStyle(size: 36))
                .help("Reproduzir/pausar (espaço)")
                Button { model.step(frames: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Próximo quadro (→)")
                Button { model.seek(to: model.duration) } label: { Image(systemName: "forward.end") }
                    .help("Fim")
            }
            .buttonStyle(GlyphButtonStyle())
            .font(Theme.font(13))
            .frame(minWidth: 44)

            divider

            Button { model.showGrid.toggle() } label: {
                Image(systemName: "squareshape.split.3x3").font(Theme.font(14, .light))
            }
            .buttonStyle(GlyphButtonStyle(active: model.showGrid))
            .help(model.showGrid ? "Ocultar grade" : "Mostrar grade dos terços")
            .frame(width: 28)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 48)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 20)
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
            layer?.cornerRadius = 10
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
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
