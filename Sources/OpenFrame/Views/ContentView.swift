import OpenFrameCore
import SwiftUI

struct ContentView: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopBar()
            Divider()
            VSplitView {
                HSplitView {
                    MediaBinView()
                        .frame(minWidth: 220, idealWidth: 270, maxWidth: 400)
                    PreviewPanel()
                        .frame(minWidth: 420, maxWidth: .infinity)
                    InspectorView()
                        .frame(minWidth: 290, idealWidth: 330, maxWidth: 460)
                }
                .frame(minHeight: 340, idealHeight: 520)
                TimelineView()
                    .frame(minHeight: 200, idealHeight: 300)
            }
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showExport) {
            ExportSheet()
                .environment(model)
        }
        .alert("OpenFrame", isPresented: Binding(get: { model.errorMessage != nil },
                                               set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct TopBar: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                    .foregroundStyle(Theme.accent)
                Text("OpenFrame").font(.headline)
                Text("— \(model.project.name)\(model.isDirty ? " •" : "")")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Divider().frame(height: 18)
            Button { model.presentImportPanel() } label: { Label("Importar", systemImage: "square.and.arrow.down") }
            Button { model.addText() } label: { Label("Texto", systemImage: "textformat") }
            Menu {
                Button("Importar legendas (SRT)…") { model.importSubtitles() }
                Button("Exportar legendas (SRT)…") { model.exportSubtitles() }
            } label: {
                Label("Legendas", systemImage: "captions.bubble")
            }
            .fixedSize()
            Divider().frame(height: 18)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .help("Desfazer (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .help("Refazer (⇧⌘Z)")
            Spacer()
            Menu {
                ForEach(AspectRatio.allCases) { ratio in
                    Button(ratio.label) { model.mutate { $0.canvas.aspect = ratio } }
                }
            } label: {
                Label("Proporção: \(model.project.canvas.aspect.label)", systemImage: "aspectratio")
            }
            .fixedSize()
            Button {
                model.showExport = true
            } label: {
                Label("Exportar", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(model.duration == 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.panel)
    }
}
