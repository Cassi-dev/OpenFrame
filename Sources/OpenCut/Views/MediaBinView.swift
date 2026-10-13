import OpenCutCore
import SwiftUI

struct MediaBinView: View {
    @Environment(EditorModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mídia").font(.headline)
                Spacer()
                Button { model.presentImportPanel() } label: {
                    Label("Importar", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if model.project.materials.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                        ForEach(model.project.materials) { m in
                            MaterialTile(material: m)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: 2).padding(4)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importMedia(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Arraste vídeos, fotos ou músicas para cá")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Importar mídia…") { model.presentImportPanel() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.tertiary))
    }
}

private struct MaterialTile: View {
    @Environment(EditorModel.self) private var model
    let material: Material
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                thumbnail
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if material.kind != .photo {
                    Text(Time.format(material.duration))
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
                if hovering {
                    Button { model.addToTimeline(material) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Adicionar à timeline")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)
                }
                if model.usageCount(material) > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(4)
                }
            }
            .frame(height: 64)
            Text(material.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.addToTimeline(material) }
        .contextMenu {
            Button(material.kind == .audio ? "Adicionar à faixa de áudio" : "Adicionar à faixa principal") {
                model.addToTimeline(material)
            }
            if material.isVisual {
                Button("Adicionar como sobreposição") { model.addAsOverlay(material) }
            }
            Divider()
            Button("Remover do projeto", role: .destructive) { model.removeMaterial(material) }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = model.thumbnails[material.id]?.first {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                (material.kind == .audio ? Theme.audioClip : Theme.panelRaised)
                Image(systemName: material.kind == .audio ? "music.note" : "film")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
