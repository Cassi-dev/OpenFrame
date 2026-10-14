import OpenFrameCore
import SwiftUI

/// Barra de ferramentas flutuante da esquerda. Clicar no painel aberto o recolhe.
struct LibraryRail: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            ForEach([LibraryPanel.media, .text, .captions]) { item($0) }
            Rectangle().fill(Theme.hairline).frame(width: 20, height: 1).padding(.vertical, 4)
            item(.shortcuts)
        }
        .padding(6)
        .panel(radius: 18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func item(_ panel: LibraryPanel) -> some View {
        let active = model.libraryVisible && model.libraryPanel == panel
        return Button {
            if active {
                model.libraryVisible = false
            } else {
                model.libraryPanel = panel
                model.libraryVisible = true
            }
        } label: {
            Image(systemName: panel.icon)
                .font(Theme.font(15, .light))
                .frame(width: 38, height: 38)
                .background(active ? Theme.raisedHigh : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(GlyphButtonStyle(active: active))
        .help(panel.title)
    }
}

/// Título de painel: SF Pro Light, com ações à direita.
struct PanelHeader<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Theme.font(16, .light))
            if let detail {
                Text(detail).font(Theme.font(11)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            trailing()
        }
        .frame(height: 30)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

struct LibraryView: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Group {
            switch model.libraryPanel {
            case .media: MediaPanel()
            case .text: TextPanel()
            case .captions: CaptionsPanel()
            case .shortcuts: ShortcutsPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Mídia

private struct MediaPanel: View {
    @Environment(EditorModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        let materials = model.project.materials
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Mídia", detail: materials.isEmpty ? nil : "\(materials.count)") {
                Button { model.presentImportPanel() } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleButtonStyle(size: 28))
                    .help("Importar mídia (⌘I)")
            }
            if materials.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 14) {
                        ForEach(materials) { MaterialTile(material: $0) }
                    }
                    .padding(.top, Theme.scrollFade)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .scrollFadeTop()
                .padding(.top, -Theme.scrollFade / 2)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Theme.panelRadius - 4, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.panelRadius - 4, style: .continuous))
                    .padding(4)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importMedia(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(Theme.font(26, .thin))
                .foregroundStyle(Theme.textTertiary)
            Text("Arraste vídeos, fotos\nou músicas para cá")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Button("Importar mídia") { model.presentImportPanel() }
                .buttonStyle(PillButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.white.opacity(0.14)))
    }
}

private struct MaterialTile: View {
    @Environment(EditorModel.self) private var model
    let material: Material
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(height: 70)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(hovering ? Color.white.opacity(0.25) : Theme.hairline))
                .overlay(alignment: .bottomTrailing) {
                    if material.kind != .photo {
                        Text(Time.format(material.duration))
                            .font(Theme.mono(9.5, .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.usageCount(material) > 0 {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6).padding(7)
                            .help("Em uso na timeline")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Button { model.addToTimeline(material) } label: { Image(systemName: "plus") }
                            .buttonStyle(CircleButtonStyle(size: 22, prominent: true))
                            .help("Adicionar à timeline")
                            .padding(5)
                    }
                }
            Text(material.name)
                .font(Theme.font(11))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.addToTimeline(material) }
        // Arrastar para a timeline: leva o id do material.
        .onDrag {
            model.draggingMaterial = material.id
            return NSItemProvider(object: material.id.uuidString as NSString)
        }
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
        } else if material.kind == .audio {
            ZStack {
                Theme.clipAudio
                if let peaks = model.waveforms[material.id], !peaks.isEmpty {
                    WaveformBars(peaks: peaks, from: 0, to: material.duration.seconds, color: Theme.waveform)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 14)
                } else {
                    Image(systemName: "waveform").font(Theme.font(20, .light)).foregroundStyle(Theme.textTertiary)
                }
            }
        } else {
            ZStack {
                Theme.raised
                Image(systemName: "film").font(Theme.font(18, .light)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Barras da forma de onda para o trecho `from...to` (em segundos de mídia).
struct WaveformBars: View {
    let peaks: [Float]
    let from: Double
    let to: Double
    var color: Color = Theme.waveform
    var bar: CGFloat = 2
    var gap: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty, to > from else { return }
            let count = max(1, Int(size.width / (bar + gap)))
            let perSecond = Waveform.peaksPerSecond
            for i in 0..<count {
                let t0 = from + (to - from) * Double(i) / Double(count)
                let t1 = from + (to - from) * Double(i + 1) / Double(count)
                let a = min(peaks.count - 1, max(0, Int(t0 * perSecond)))
                let b = min(peaks.count, max(a + 1, Int(t1 * perSecond)))
                let value = CGFloat(peaks[a..<b].max() ?? 0)
                let h = max(1.5, value * size.height)
                let rect = CGRect(x: CGFloat(i) * (bar + gap), y: (size.height - h) / 2, width: bar, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(color))
            }
        }
    }
}

// MARK: - Texto

/// Estilos prontos de texto, usados na biblioteca e no inspetor.
enum TextStylePreset: String, CaseIterable, Identifiable {
    case classic, outline, highlight, neon, caption, label, longShadow, spaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Clássico"
        case .outline: "Contorno"
        case .highlight: "Destaque"
        case .neon: "Neon"
        case .caption: "Legenda"
        case .label: "Etiqueta"
        case .longShadow: "Sombra dura"
        case .spaced: "Espaçado"
        }
    }

    /// Aplica o estilo mantendo fonte, tamanho, posição, alinhamento e largura.
    func applied(to old: TextStyle) -> TextStyle {
        var s = TextStyle()
        s.fontName = old.fontName
        s.fontFace = old.fontFace
        s.fontSize = old.fontSize
        s.x = old.x
        s.y = old.y
        s.scale = old.scale
        s.rotation = old.rotation
        s.maxWidth = old.maxWidth
        s.alignment = old.alignment
        switch self {
        case .classic:
            break
        case .outline:
            s.strokeWidth = 8
            s.shadow = false
        case .highlight:
            s.color = .black
            s.backgroundEnabled = true
            s.backgroundColor = .yellow
            s.backgroundRadius = 0.12
            s.shadow = false
        case .neon:
            // Brilho feito com a sombra: sem distância, bem desfocada, na cor do texto.
            s.color = RGBA(0.3, 1, 0.95)
            s.strokeWidth = 2
            s.strokeColor = RGBA(0.05, 0.2, 0.4)
            s.shadowColor = RGBA(0.3, 1, 0.95, 0.9)
            s.shadowDistance = 0
            s.shadowBlur = 0.35
        case .caption:
            s.bold = false
            s.backgroundEnabled = true
            s.backgroundColor = RGBA(0, 0, 0, 0.55)
            s.backgroundRadius = 0.25
            s.backgroundPaddingX = 0.35
            s.backgroundPaddingY = 0.15
            s.shadow = false
        case .label:
            s.textCase = .upper
            s.letterSpacing = 0.08
            s.backgroundEnabled = true
            s.backgroundColor = RGBA(0.9, 0.2, 0.25)
            s.backgroundRadius = 1
            s.backgroundPaddingX = 0.5
            s.shadow = false
        case .longShadow:
            s.shadowColor = RGBA(0, 0, 0, 1)
            s.shadowAngle = -45
            s.shadowDistance = 0.1
            s.shadowBlur = 0
        case .spaced:
            s.textCase = .upper
            s.bold = false
            s.letterSpacing = 0.3
            s.lineSpacing = 0.2
            s.shadow = false
        }
        return s
    }

    /// Amostra do estilo (aproximada) para os cartões.
    @ViewBuilder
    var sample: some View {
        let text = Text("Aa").font(.system(size: 22, weight: .medium))
        switch self {
        case .classic:
            text.foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2, y: 1)
        case .outline:
            text.foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .shadow(color: .black, radius: 0, x: -1, y: -1)
                .shadow(color: .black, radius: 0, x: 1, y: -1)
                .shadow(color: .black, radius: 0, x: -1, y: 1)
        case .highlight:
            text.foregroundStyle(.black).padding(.horizontal, 6).background(Color.yellow, in: RoundedRectangle(cornerRadius: 3))
        case .neon:
            text.foregroundStyle(Color(red: 0.3, green: 1, blue: 0.95))
                .shadow(color: Color(red: 0.3, green: 1, blue: 0.95).opacity(0.8), radius: 6)
        case .caption:
            Text("Aa").font(.system(size: 20, weight: .regular)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
        case .label:
            Text("AA").font(.system(size: 18, weight: .semibold)).tracking(1.5).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color(red: 0.9, green: 0.2, blue: 0.25), in: Capsule())
        case .longShadow:
            text.foregroundStyle(.white).shadow(color: .black, radius: 0, x: 2, y: 2)
        case .spaced:
            Text("AA").font(.system(size: 18, weight: .regular)).tracking(6).foregroundStyle(.white)
        }
    }
}

private struct TextPanel: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Texto")
            Button { model.addText() } label: {
                Label("Adicionar texto", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .help("Adicionar texto no cursor (⌘T)")
            SectionHeader(title: "Estilos")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(TextStylePreset.allCases) { preset in
                    StyleCard(preset: preset) { model.addText(style: preset.applied(to: TextStyle())) }
                }
            }
            Text("Clique num estilo para adicionar um texto no cursor.")
                .font(Theme.font(11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
    }
}

private struct StyleCard: View {
    let preset: TextStylePreset
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preset.sample
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(
                        LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(hovering ? Color.white.opacity(0.25) : Theme.hairline))
                Text(preset.title)
                    .font(Theme.font(11))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Legendas

private struct CaptionsPanel: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let cues = model.project.tracks.filter { $0.kind == .text }.flatMap(\.segments)
            .sorted { $0.targetStart < $1.targetStart }
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Legendas", detail: cues.isEmpty ? nil : "\(cues.count)")
            Button { model.presentAutoCaptions() } label: {
                Label("Legendas automáticas", systemImage: "waveform.and.mic").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .help("Transcrever o áudio e criar as legendas")
            HStack(spacing: 8) {
                Button { model.importSubtitles() } label: {
                    Label("Importar SRT", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                Button { model.exportSubtitles() } label: {
                    Label("Exportar SRT", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .disabled(cues.isEmpty)
            }
            .buttonStyle(PillButtonStyle(compact: true))
            if model.hasAutoCaptions, model.selectedSegment?.text != nil {
                Button { model.applyStyleToAutoCaptions() } label: {
                    Label("Aplicar este estilo a todas", systemImage: "paintbrush").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(compact: true))
                .help("Copia o estilo do texto selecionado para todas as legendas automáticas")
            }
            if cues.isEmpty {
                Text("Nenhum texto na timeline. Gere legendas a partir do áudio, importe um arquivo SRT ou adicione textos pelo painel Texto.")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(cues) { CueRow(segment: $0) }
                    }
                    .padding(.top, Theme.scrollFade)
                }
                .scrollIndicators(.never)
                .scrollFadeTop()
                .padding(.top, -Theme.scrollFade / 2)
            }
        }
        .padding(14)
    }
}

/// Uma legenda da lista: clique seleciona e leva o cursor até ela; duplo clique
/// (ou o lápis) edita o texto ali mesmo; a lixeira apaga.
private struct CueRow: View {
    @Environment(EditorModel.self) private var model
    let segment: Segment
    @State private var hovering = false
    @State private var draft = ""
    /// A edição desta linha ainda não foi gravada (vale mesmo se outra linha passar a ser editada).
    @State private var pending = false
    @FocusState private var focused: Bool

    private var editing: Bool { model.editingCaption == segment.id }

    var body: some View {
        let selected = model.selection == segment.id
        let row = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Time.format(segment.targetStart))
                .font(Theme.mono(10))
                .foregroundStyle(selected || editing ? Theme.accent : Theme.textTertiary)
            if editing {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand {
                        pending = false
                        model.editingCaption = nil
                    }
                    .onChange(of: focused) { if !focused { commit() } }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(segment.text?.text.replacingOccurrences(of: "\n", with: " ") ?? "")
                    .font(Theme.font(12))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hovering, !editing {
                HStack(spacing: 8) {
                    Button(action: beginEditing) { Image(systemName: "pencil") }
                        .help("Editar o texto")
                    Button { model.deleteSegment(segment.id) } label: { Image(systemName: "trash") }
                        .help("Apagar a legenda")
                }
                .font(Theme.font(11))
                .buttonStyle(GlyphButtonStyle())
                .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected || hovering || editing ? Theme.raised : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(editing ? Theme.accent.opacity(0.6) : .clear))
        .contentShape(Rectangle())

        Group {
            if editing {
                row
            } else {
                // O clique simples age na hora; o duplo vem por cima e abre a edição.
                row.onTapGesture(perform: select)
                    .simultaneousGesture(TapGesture(count: 2).onEnded(beginEditing))
            }
        }
        .onHover { hovering = $0 }
        .onAppear { if editing { startEditing() } }
        .onChange(of: editing) { if editing { startEditing() } else { commit() } }
    }

    private func select() {
        model.selection = segment.id
        model.inspectorTab = .text
        model.seek(to: segment.targetStart)
    }

    private func beginEditing() {
        model.editingCaption = segment.id
    }

    private func startEditing() {
        draft = segment.text?.text ?? ""
        pending = true
        Task { @MainActor in focused = true }
    }

    private func commit() {
        guard pending else { return }
        pending = false
        if editing { model.editingCaption = nil }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != segment.text?.text else { return }
        model.setText(segment.id, text)
    }
}

// MARK: - Atalhos

private struct ShortcutsPanel: View {
    private let items: [(String, String)] = [
        ("Espaço", "Reproduzir / pausar"),
        ("← →", "Quadro a quadro"),
        ("⇧ ← →", "10 quadros"),
        ("↑ ↓", "Corte anterior / seguinte"),
        ("Home  End", "Início / fim do projeto"),
        ("⌘B", "Dividir no cursor"),
        ("⌘D", "Duplicar"),
        ("⌫", "Apagar clipe"),
        ("esc", "Tirar a seleção"),
        ("⌘T", "Adicionar texto"),
        ("⌘I", "Importar mídia"),
        ("⌘Z", "Desfazer"),
        ("⇧⌘Z", "Refazer"),
        ("⌘ =  ⌘ −", "Zoom da timeline"),
        ("⌘ + rolar, pinça", "Zoom no cursor"),
        ("⇧Z", "Ajustar timeline à janela"),
        ("⌘S", "Salvar"),
        ("⌘E", "Exportar"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Atalhos")
            VStack(spacing: 0) {
                ForEach(items, id: \.0) { keys, action in
                    HStack {
                        Text(action).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(keys)
                            .font(Theme.font(11, .medium))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .field(radius: 5)
                    }
                    .frame(height: 30)
                }
            }
        }
        .padding(14)
    }
}
