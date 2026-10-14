import OpenFrameCore
import SwiftUI

/// Janela "Legendas automáticas": fonte, idioma, precisão (modelo do Whisper),
/// estilo e o andamento da geração.
struct AutoCaptionsSheet: View {
    @Environment(EditorModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let generation = model.captionGeneration
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Legendas automáticas").font(Theme.font(22, .light))
                Text(model.project.name).foregroundStyle(Theme.textTertiary).lineLimit(1)
                Spacer()
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 14)

            switch generation.phase {
            case .configuring:
                CaptionOptionsForm()
                footer
            case .downloading, .mixing, .transcribing:
                GenerationProgressView()
            case .finished(let count):
                finishedView(count)
            case .failed(let message):
                failedView(message)
            }
        }
        .frame(width: 720)
        .frame(minHeight: 620)
        .background(Theme.surface)
        .font(Theme.font(12))
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var footer: some View {
        let generation = model.captionGeneration
        let problem = model.captionSourceProblem
        let pending = CaptionModels.info(generation.modelID).flatMap { $0.installed ? nil : $0 }
        return HStack(spacing: 12) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.35))
                    .lineLimit(2)
            } else {
                Label {
                    Text(pending.map { "Baixa o modelo \($0.name) (\($0.bytes.megabytes)) uma vez. A transcrição roda neste Mac." }
                         ?? "A transcrição roda neste Mac, sem enviar nada para a internet.")
                } icon: {
                    Image(systemName: pending == nil ? "lock" : "arrow.down.circle")
                }
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
            }
            Spacer()
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(PillButtonStyle(kind: .quiet))
            Button("Gerar legendas") { model.generateCaptions() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(problem != nil)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func finishedView(_ count: Int) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(Theme.font(46, .thin))
                .foregroundStyle(Theme.accent)
            Text("Legendas prontas").font(Theme.font(18, .light))
            Text(count == 1 ? "1 legenda na timeline" : "\(count) legendas na timeline")
                .foregroundStyle(Theme.textSecondary)
            Text("Edite o texto no painel Legendas. ⌘Z desfaz a geração inteira.")
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            HStack {
                Spacer()
                Button("Fechar") { close() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
        }
        .padding(24)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "xmark.octagon")
                .font(Theme.font(42, .thin))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
            Text("Não deu para gerar as legendas").font(Theme.font(18, .light))
            Text(message)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer()
            HStack {
                Button("Voltar às opções") { model.captionGeneration.setPhase(.configuring) }
                Spacer()
                Button("Fechar") { close() }
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(24)
    }

    private func close() {
        model.captionGeneration.setPhase(.configuring)
        dismiss()
    }
}

// MARK: - Opções

private struct CaptionOptionsForm: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        @Bindable var generation = model.captionGeneration
        let clipAvailable = model.selectedClipWithAudio != nil
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                FieldRow(label: "Fonte") {
                    HStack(spacing: 10) {
                        PillPicker(selection: $generation.source, options: [.timeline, .clip],
                                   title: { $0 == .timeline ? "Timeline inteira" : "Clipe selecionado" })
                            .frame(width: 280)
                            .disabled(!clipAvailable)
                        if !clipAvailable {
                            Text("Selecione um clipe com áudio para usar só ele.")
                                .font(Theme.font(11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                FieldRow(label: "Idioma") {
                    MenuField(selection: $generation.language, options: [nil] + CaptionModels.languages.map(\.code),
                              title: { code in
                                  code.flatMap { c in CaptionModels.languages.first { $0.code == c }?.name }
                                      ?? "Detectar automaticamente"
                              })
                        .frame(width: 280)
                }

                SectionHeader(title: "Precisão")
                VStack(spacing: 2) {
                    ForEach(CaptionModels.all, id: \.id) { info in
                        ModelRow(info: info, selected: generation.modelID == info.id) {
                            generation.modelID = info.id
                        }
                    }
                }

                SectionHeader(title: "Estilo")
                HStack(spacing: 12) {
                    ForEach(CaptionLooks.all, id: \.id) { look in
                        CaptionStyleCard(look: look, selected: generation.layoutID == look.id) {
                            generation.layoutID = look.id
                        }
                    }
                }
                if generation.layoutID == "highlight" {
                    ColorRow(title: "Cor do destaque",
                             color: Binding(get: { generation.highlightColor.color },
                                            set: { generation.highlightColor = RGBA($0) }))
                        .padding(.top, 4)
                }

                SwitchRow(title: "Substituir legendas automáticas anteriores", isOn: $generation.replacePrevious)
                    .padding(.top, 10)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .padding(.horizontal, 24)
        .onAppear {
            if !clipAvailable { generation.source = .timeline }
        }
    }
}

/// Uma linha da lista de precisão: escolher, baixar com progresso, cancelar e apagar.
private struct ModelRow: View {
    @Environment(EditorModel.self) private var model
    let info: CaptionModels.Info
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        let download = model.captionGeneration.downloads[info.id]
        HStack(spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(Theme.font(14))
                .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(info.name).font(Theme.font(13, selected ? .medium : .regular))
                    if info.recommended {
                        Text("Recomendado")
                            .font(Theme.font(10, .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }
                Text(info.detail)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 12)
            Text(info.bytes.megabytes)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .trailing)
            status(download)
                .frame(width: 190, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(selected ? Theme.raisedHigh : (hovering ? Theme.raised : .clear),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(selected ? Theme.accent.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func status(_ download: Double?) -> some View {
        if let download {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressBar(fraction: download).frame(width: 110)
                    Text("\(Int64(Double(info.bytes) * download).megabytes) de \(info.bytes.megabytes)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
                Button { model.cancelModelDownload(info.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle(size: 22))
                    .help("Cancelar o download")
            }
        } else if info.installed {
            HStack(spacing: 8) {
                Label("Instalado", systemImage: "checkmark")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textSecondary)
                Menu {
                    Button("Apagar modelo (\(info.bytes.megabytes))", role: .destructive) {
                        model.deleteModel(info.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Mais opções")
            }
        } else {
            Button { model.downloadModel(info.id) } label: {
                Label("Baixar", systemImage: "arrow.down")
            }
            .buttonStyle(PillButtonStyle(compact: true))
        }
    }
}

/// Trilho fino de progresso, no ciano da marca.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(Theme.accent).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// Cartão de um visual de legenda, com a prévia animada sobre um quadro do vídeo.
private struct CaptionStyleCard: View {
    @Environment(EditorModel.self) private var model
    let look: CaptionLooks.Look
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    CardBackdrop()
                    CaptionSample(lookID: look.id, highlight: model.captionGeneration.highlightColor.color)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : (hovering ? Color.white.opacity(0.22) : Theme.hairline),
                                  lineWidth: selected ? 1.5 : 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(look.name)
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                    Text(look.detail)
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2, reservesSpace: true)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .frame(maxWidth: .infinity)
    }
}

/// Fundo da prévia: o primeiro quadro do vídeo do projeto, escurecido; sem vídeo, um degradê.
private struct CardBackdrop: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let p = model.project
        let first = p.mainTrackIndex.flatMap { p.tracks[$0].segments.first?.materialId }
        if let first, let image = model.thumbnails[first]?.first {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(Color.black.opacity(0.25))
        } else {
            LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Amostra de cada visual feita no SwiftUI: aparece enquanto a prévia do núcleo não fica pronta.
private struct CaptionSample: View {
    let lookID: String
    let highlight: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            switch lookID {
            case "highlight":
                (Text("um vídeo ") + Text("muito").foregroundColor(highlight) + Text(" bom"))
                    .font(.system(size: h * 0.11, weight: .bold))
                    .modifier(CaptionInk())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, h * 0.12)
            case "punch":
                Text("MUITO BOM")
                    .font(.system(size: h * 0.2, weight: .heavy))
                    .modifier(CaptionInk())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                Text("Hoje eu vou mostrar\num vídeo muito bom")
                    .font(.system(size: h * 0.085, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .modifier(CaptionInk())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, h * 0.1)
            }
        }
    }
}

private struct CaptionInk: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 0.5)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - Progresso

private struct GenerationProgressView: View {
    @Environment(EditorModel.self) private var model

    private enum Step: Int { case download, mix, transcribe }

    var body: some View {
        let generation = model.captionGeneration
        let (step, fraction) = Self.state(generation.phase)
        let steps: [Step] = generation.includesDownload ? [.download, .mix, .transcribe] : [.mix, .transcribe]
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(steps, id: \.rawValue) { s in
                    if s != steps.first {
                        Rectangle().fill(s.rawValue <= step.rawValue ? Theme.accent.opacity(0.6) : Theme.hairline)
                            .frame(width: 28, height: 1)
                    }
                    stepLabel(s, current: step)
                }
            }
            .padding(.top, 8)
            Spacer()
            Text(String(format: "%.0f%%", fraction * 100))
                .font(Theme.mono(44, .thin))
            ProgressBar(fraction: fraction)
                .frame(height: 4)
                .shadow(color: Theme.accent.opacity(0.5), radius: 6)
            HStack {
                Text(detail(generation)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let remaining = remaining(generation, fraction: fraction) {
                    Text(remaining).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            HStack {
                Text("Pode continuar editando depois: um ⌘Z desfaz a geração inteira.")
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Cancelar") { model.cancelCaptionGeneration() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(24)
    }

    private func stepLabel(_ s: Step, current: Step) -> some View {
        let done = s.rawValue < current.rawValue
        let active = s == current
        return HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "circle.inset.filled" : "circle"))
                .foregroundStyle(done || active ? Theme.accent : Theme.textTertiary)
            Text(Self.title(s))
                .font(Theme.font(12, active ? .medium : .regular))
                .foregroundStyle(active ? Theme.textPrimary : (done ? Theme.textSecondary : Theme.textTertiary))
        }
    }

    private static func title(_ s: Step) -> String {
        switch s {
        case .download: "Baixar modelo"
        case .mix: "Misturar áudio"
        case .transcribe: "Transcrever"
        }
    }

    private static func state(_ phase: CaptionGeneration.Phase) -> (Step, Double) {
        switch phase {
        case .downloading(let received, let total): (.download, total > 0 ? Double(received) / Double(total) : 0)
        case .mixing(let f): (.mix, f)
        case .transcribing(let f): (.transcribe, f)
        default: (.transcribe, 1)
        }
    }

    private func detail(_ generation: CaptionGeneration) -> String {
        let name = CaptionModels.info(generation.modelID)?.name ?? ""
        switch generation.phase {
        case .downloading(let received, let total):
            return "Baixando o modelo \(name): \(received.megabytes) de \(total.megabytes)"
        case .mixing:
            return generation.source == .clip ? "Preparando o áudio do clipe" : "Misturando o áudio da timeline"
        default:
            return "Transcrevendo com o modelo \(name)"
        }
    }

    private func remaining(_ generation: CaptionGeneration, fraction: Double) -> String? {
        guard fraction > 0.03, fraction < 1 else { return nil }
        let elapsed = Date().timeIntervalSince(generation.phaseStartedAt)
        guard elapsed > 1 else { return nil }
        let seconds = Int((elapsed / fraction * (1 - fraction)).rounded())
        return seconds < 60 ? "Restam ~\(seconds) s" : "Restam ~\(Int((Double(seconds) / 60).rounded())) min"
    }
}

// MARK: - Dados dos modelos e visuais

extension Int64 {
    /// Tamanho em MB inteiros, como nos downloads ("488 MB").
    var megabytes: String { "\(Int((Double(self) / 1_000_000).rounded())) MB" }
}

/// Modelos do Whisper oferecidos na lista de precisão.
enum CaptionModels {
    struct Info {
        let id: String
        let name: String
        let detail: String
        let bytes: Int64
        let installed: Bool
        let recommended: Bool
    }

    static let recommendedID = "small"

    private static let details: [String: String] = [
        "base": "O mais leve. Bom para fala clara e pouco ruído.",
        "small": "Bom equilíbrio entre velocidade e precisão.",
        "turbo": "Mais lento e mais preciso. Melhor para áudio difícil.",
    ]

    // Provisório até a etapa 1 do núcleo trazer o catálogo dos modelos.
    private static let provisional: [(id: String, name: String, bytes: Int64)] = [
        ("base", "Rápido", 147_951_465),
        ("small", "Equilibrado", 487_601_967),
        ("turbo", "Máxima precisão", 574_041_195),
    ]

    static var all: [Info] {
        provisional.map {
            Info(id: $0.id, name: $0.name, detail: details[$0.id] ?? "", bytes: $0.bytes, installed: false,
                 recommended: $0.id == recommendedID)
        }
    }

    static func info(_ id: String) -> Info? { all.first { $0.id == id } }

    // Provisório até a etapa 1 do núcleo trazer a lista de idiomas do transcritor.
    static let languages: [(code: String, name: String)] = [
        ("pt", "Português"), ("en", "Inglês"), ("es", "Espanhol"),
    ]
}

/// Os três visuais de legenda, na ordem dos cartões.
enum CaptionLooks {
    struct Look {
        let id: String
        let name: String
        let detail: String
    }

    static let all: [Look] = [
        Look(id: "phrases", name: "Frases", detail: "Até duas linhas embaixo, como no cinema."),
        Look(id: "highlight", name: "Destaque", detail: "Uma linha; a palavra falada acende."),
        Look(id: "punch", name: "Impacto", detail: "Poucas palavras grandes no centro."),
    ]
}
