import OpenFrameCore
import SwiftUI

/// Tela inicial: criar um projeto (vazio ou num formato pronto) e abrir,
/// renomear, duplicar ou apagar os projetos da biblioteca.
struct HomeView: View {
    @Environment(EditorModel.self) private var model
    @State private var search = ""
    @State private var renaming: ProjectEntry?
    @State private var renameText = ""
    @State private var deleting: ProjectEntry?

    /// Formatos prontos, como os modelos de tela do CapCut.
    private static let formats: [(AspectRatio, String)] = [
        (.r16x9, "YouTube · tela cheia"),
        (.r9x16, "Reels · TikTok · Shorts"),
        (.r1x1, "Quadrado"),
        (.r4x5, "Feed do Instagram"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: ContentView.barHeight)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    createSection
                    projectsSection
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .panel()
            .padding([.horizontal, .bottom], 8)
        }
        .onAppear {
            model.refreshLibrary()
            // O AppKit põe o foco no primeiro campo de texto; a busca só ganha foco com um clique.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .alert("Renomear projeto", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $renameText)
            Button("Renomear") {
                if let entry = renaming { model.renameProject(entry.id, to: renameText) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Apagar “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Mover para o Lixo", role: .destructive) {
                if let entry = deleting { model.deleteProject(entry.id) }
            }
        } message: {
            Text("O projeto vai para o Lixo. Os vídeos, fotos e áudios usados nele não são apagados.")
        }
    }

    // MARK: - Barra superior

    private var topBar: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 10) {
                LogoMark()
                    .frame(width: 22, height: 22)
                Text("OpenFrame")
                    .font(Theme.font(14, .medium))
                Spacer()
                Button {
                    model.openProject()
                } label: {
                    Label("Abrir arquivo…", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle(kind: .secondary))
                .help("Trazer um arquivo .openframe para a biblioteca (⌘O)")
            }
            .padding(.leading, 84)
            .padding(.trailing, 12)
        }
    }

    // MARK: - Criar

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Criar")
                .font(Theme.font(22, .light))
            HStack(spacing: 12) {
                NewProjectCard { model.createProject() }
                ForEach(Self.formats, id: \.0) { aspect, subtitle in
                    FormatCard(aspect: aspect, subtitle: subtitle) { model.createProject(aspect: aspect) }
                }
            }
        }
    }

    // MARK: - Projetos

    private var filtered: [ProjectEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Projetos")
                    .font(Theme.font(22, .light))
                Text("\(model.entries.count)")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if !model.entries.isEmpty { searchField }
            }
            if model.entries.isEmpty {
                emptyState("Nenhum projeto ainda",
                           detail: "Crie um projeto acima ou abra um arquivo .openframe.")
            } else if filtered.isEmpty {
                emptyState("Nenhum projeto com “\(search)”", detail: nil)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 18, alignment: .top)],
                          alignment: .leading, spacing: 22) {
                    ForEach(filtered) { entry in
                        ProjectCard(entry: entry,
                                    open: { model.openLibraryProject(entry.id) },
                                    rename: {
                                        renameText = entry.name
                                        renaming = entry
                                    },
                                    duplicate: { model.duplicateProject(entry.id) },
                                    reveal: { model.revealProject(entry.id) },
                                    delete: { deleting = entry })
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            TextField("Buscar", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(GlyphButtonStyle())
            }
        }
        .font(Theme.font(12))
        .padding(.horizontal, 10)
        .frame(width: 220, height: 28)
        .field(radius: 14)
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(Theme.font(28, .thin))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textSecondary)
            if let detail {
                Text(detail)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Cartões de criação

private struct NewProjectCard: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "plus")
                    .font(Theme.font(18, .medium))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
                Spacer()
                Text("Novo projeto")
                    .font(Theme.font(14, .medium))
                Text("Formato do primeiro clipe")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
            .padding(16)
            .frame(width: 216, height: 140, alignment: .leading)
            .background(hovering ? Theme.raisedHigh : Theme.raised,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 2, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.6) : Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Projeto novo; o formato segue o primeiro clipe (⌘N)")
    }
}

private struct FormatCard: View {
    let aspect: AspectRatio
    let subtitle: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                AspectGlyph(aspect: aspect.value ?? 16.0 / 9, highlighted: hovering)
                    .frame(width: 48, height: 48, alignment: .leading)
                Spacer()
                Text(aspect.label)
                    .font(Theme.font(14, .medium))
                Text(subtitle)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(16)
            .frame(width: 160, height: 140, alignment: .leading)
            .background(hovering ? Theme.raisedHigh : Theme.raised,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 2, style: .continuous)
                .strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Projeto novo em \(aspect.label)")
    }
}

/// Retângulo na proporção do formato, encaixado no quadro disponível.
private struct AspectGlyph: View {
    let aspect: Double
    var highlighted = false

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            let size = aspect >= box.width / box.height
                ? CGSize(width: box.width, height: box.width / aspect)
                : CGSize(width: box.height * aspect, height: box.height)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent : Theme.textSecondary, lineWidth: 1.5)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Cartão de projeto

private struct ProjectCard: View {
    let entry: ProjectEntry
    let open: () -> Void
    let rename: () -> Void
    let duplicate: () -> Void
    let reveal: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    @State private var image: NSImage?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(Theme.font(13))
                    .lineLimit(1)
                Text("Editado \(Self.relative.localizedString(for: entry.modified, relativeTo: Date())) · \(entry.aspect.label)")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .task(id: entry.thumbnailModified) {
            image = entry.thumbnailModified == nil ? nil : NSImage(contentsOf: entry.thumbnailURL)
        }
        .help("Abrir “\(entry.name)”")
    }

    private var thumbnail: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                AspectGlyph(aspect: entry.aspectValue)
                    .frame(width: 44, height: 44)
                    .opacity(0.6)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if entry.duration > 0 {
                Text(Time.format(entry.duration).components(separatedBy: ".")[0])
                    .font(Theme.mono(10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.6), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(hovering ? Theme.accent.opacity(0.7) : Theme.hairline, lineWidth: hovering ? 1.5 : 1))
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Abrir", action: open)
        Button("Renomear…", action: rename)
        Button("Duplicar", action: duplicate)
        Button("Mostrar no Finder", action: reveal)
        Divider()
        Button("Apagar…", role: .destructive, action: delete)
    }
}
