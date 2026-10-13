import OpenFrameCore
import SwiftUI

struct ContentView: View {
    @Environment(EditorModel.self) private var model
    @AppStorage("timelineHeight") private var timelineHeight: Double = 340
    @State private var dragStartHeight: Double?
    /// Altura antes de maximizar a timeline, para voltar a ela.
    @State private var heightBeforeMaximize: Double?

    static let barHeight: CGFloat = 52

    var body: some View {
        @Bindable var model = model
        Group {
            if model.screen == .home {
                HomeView()
            } else {
                editor
            }
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .background(WindowConfigurator(barHeight: Self.barHeight))
        .font(Theme.font(12))
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
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

    private var editor: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                TopBar()
                    .frame(height: Self.barHeight)
                HStack(spacing: 8) {
                    LibraryRail()
                    if model.libraryVisible {
                        LibraryView()
                            .frame(width: 272)
                            .panel()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    PreviewPanel()
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        .panel()
                    InspectorView()
                        .frame(width: 308)
                        .panel()
                }
                resizeHandle(total: geo.size.height)
                TimelineView()
                    .frame(height: clampedTimelineHeight(total: geo.size.height))
                    .panel()
            }
            .padding([.horizontal, .bottom], 8)
        }
        .animation(.easeOut(duration: 0.2), value: model.libraryVisible)
    }

    private func clampedTimelineHeight(total: CGFloat) -> CGFloat {
        min(max(CGFloat(timelineHeight), 190), maxTimelineHeight(total: total))
    }

    private func maxTimelineHeight(total: CGFloat) -> CGFloat {
        max(190, total - Self.barHeight - 360)
    }

    /// Maximiza a timeline ou volta à altura de antes.
    private func toggleMaximized(total: CGFloat) {
        let maximum = Double(maxTimelineHeight(total: total))
        withAnimation(.easeOut(duration: 0.2)) {
            if Double(clampedTimelineHeight(total: total)) >= maximum - 1 {
                timelineHeight = heightBeforeMaximize ?? 340
                heightBeforeMaximize = nil
            } else {
                heightBeforeMaximize = Double(clampedTimelineHeight(total: total))
                timelineHeight = maximum
            }
        }
    }

    /// Faixa fina entre o preview e a timeline; arrastar muda a altura da
    /// timeline e o duplo clique maximiza.
    private func resizeHandle(total: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(width: 36, height: 3)
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartHeight ?? Double(clampedTimelineHeight(total: total))
                    dragStartHeight = start
                    timelineHeight = start - Double(value.translation.height)
                }
                .onEnded { _ in
                    dragStartHeight = nil
                    heightBeforeMaximize = nil
                })
            .onTapGesture(count: 2) { toggleMaximized(total: total) }
            .help("Arraste para redimensionar a timeline; clique duas vezes para maximizar")
    }
}

struct TopBar: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let project = model.project
        let size = model.exportSettings.outputSize(for: project)
        ZStack {
            WindowDragArea()
            HStack(spacing: 10) {
                Button { model.showHome() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(Theme.font(11, .medium))
                            .foregroundStyle(Theme.textSecondary)
                        LogoMark()
                            .frame(width: 22, height: 22)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Voltar aos projetos (⇧⌘P)")
                ProjectNameField()
                if model.isDirty, model.libraryID == nil {
                    Circle()
                        .fill(Theme.textTertiary)
                        .frame(width: 5, height: 5)
                        .help("Alterações não salvas")
                }
                Spacer(minLength: 16)
                HStack(spacing: 6) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo)
                        .help("Desfazer (⌘Z)")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.canRedo)
                        .help("Refazer (⇧⌘Z)")
                }
                .buttonStyle(CircleButtonStyle(size: 30))
                Button {
                    model.showExport = true
                } label: {
                    Label("Exportar", systemImage: "arrow.up.forward")
                }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(model.duration == 0)
                .help("Exportar vídeo (⌘E)")
            }
            .padding(.leading, 84)
            .padding(.trailing, 12)

            // Centro: proporção do canvas e tamanho de saída.
            HStack(spacing: 8) {
                PillPicker(selection: model.projectBinding(\.canvas.aspect),
                           options: AspectRatio.allCases, title: \.label)
                    .fixedSize()
                HStack(spacing: 4) {
                    Text("L").foregroundStyle(Theme.textTertiary)
                    Text(verbatim: "\(Int(size.width))")
                    Text("A").foregroundStyle(Theme.textTertiary).padding(.leading, 4)
                    Text(verbatim: "\(Int(size.height))")
                }
                .font(Theme.mono(11))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .field(radius: 14)
                .help("Tamanho de saída (largura × altura)")
            }
        }
    }
}

/// Nome do projeto na barra superior: clique para renomear (Enter confirma, Esc desiste).
private struct ProjectNameField: View {
    @Environment(EditorModel.self) private var model
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("Nome do projeto", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.font(13))
                .frame(width: 220)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .field(radius: 7)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onAppear { focused = true }
        } else {
            Text(model.project.name)
                .font(Theme.font(13))
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard model.libraryID != nil else { return }
                    draft = model.project.name
                    editing = true
                }
                .help(model.libraryID != nil ? "Clique para renomear" : "")
        }
    }

    private func commit() {
        guard editing else { return }
        model.renameCurrentProject(draft)
        editing = false
    }
}
