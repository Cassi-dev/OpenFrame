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
        .frame(width: 760)
        .frame(minHeight: 700)
        .background(Theme.surface)
        .font(Theme.font(12))
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var footer: some View {
        let generation = model.captionGeneration
        let problem = model.captionSourceProblem
        let pending = generation.installed.contains(generation.model) ? nil : generation.model
        return HStack(spacing: 12) {
            if let warning = problem ?? generation.modelError {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.35))
                    .lineLimit(2)
            } else {
                Label {
                    Text(pending.map { "Baixa o modelo \($0.displayName) (\($0.byteSize.megabytes)) uma vez. A transcrição roda neste Mac." }
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
    static let columns = 4

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
                    MenuField(selection: $generation.language, options: [nil] + Transcriber.languages.map(\.code),
                              title: { code in
                                  code.flatMap { c in Transcriber.languages.first { $0.code == c }?.name }
                                      ?? "Detectar automaticamente"
                              })
                        .frame(width: 280)
                }

                SectionHeader(title: "Precisão")
                VStack(spacing: 2) {
                    ForEach(WhisperModel.allCases) { whisper in
                        ModelRow(whisper: whisper, selected: generation.model == whisper) {
                            generation.model = whisper
                        }
                    }
                }

                SectionHeader(title: "Estilo")
                ForEach(CaptionPresetGroup.allCases) { group in
                    Text(group.displayName)
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, group == .classic ? 0 : 6)
                    // Uma fileira por grupo (o maior tem 4): os títulos ficam alinhados com as fileiras.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                             count: Self.columns), alignment: .leading, spacing: 12) {
                        ForEach(CaptionPreset.allCases.filter { $0.group == group }) { preset in
                            CaptionStyleCard(preset: preset, selected: generation.preset == preset) {
                                generation.preset = preset
                            }
                        }
                    }
                }
                if generation.preset.usesAccent {
                    ColorRow(title: "Cor do destaque",
                             color: Binding(get: { generation.highlightColor.color },
                                            set: { generation.highlightColor = RGBA($0) }))
                        .padding(.top, 4)
                }

                // Sem legendas automáticas no projeto, não há o que substituir.
                if model.hasAutoCaptions {
                    SwitchRow(title: generation.source == .clip ? "Substituir as legendas automáticas deste clipe"
                                                                : "Substituir as legendas automáticas anteriores",
                              isOn: $generation.replacePrevious)
                        .padding(.top, 10)
                }
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
    let whisper: WhisperModel
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    private static let details: [WhisperModel: String] = [
        .base: "O mais leve. Bom para fala clara e pouco ruído.",
        .small: "Bom equilíbrio entre velocidade e precisão.",
        .turbo: "Mais lento e mais preciso. Melhor para áudio difícil.",
    ]

    var body: some View {
        let generation = model.captionGeneration
        let download = generation.downloads[whisper]
        HStack(spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(Theme.font(14))
                .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(whisper.displayName).font(Theme.font(13, selected ? .medium : .regular))
                    if whisper == CaptionGeneration.recommended {
                        Text("Recomendado")
                            .font(Theme.font(10, .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }
                Text(Self.details[whisper] ?? "")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 12)
            Text(whisper.byteSize.megabytes)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .trailing)
            status(download, installed: generation.installed.contains(whisper))
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
    private func status(_ download: Double?, installed: Bool) -> some View {
        let generation = model.captionGeneration
        if let download {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressBar(fraction: download).frame(width: 110)
                    Text("\(Int64(Double(whisper.byteSize) * download).megabytes) de \(whisper.byteSize.megabytes)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
                Button { generation.cancelDownload(whisper) } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle(size: 22))
                    .help("Cancelar o download")
            }
        } else if installed {
            HStack(spacing: 8) {
                Label("Instalado", systemImage: "checkmark")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textSecondary)
                Menu {
                    Button("Apagar modelo (\(whisper.byteSize.megabytes))", role: .destructive) {
                        generation.delete(whisper)
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
            Button { generation.download(whisper) } label: {
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

/// Cartão de uma predefinição de legenda, com a prévia animada sobre um quadro do vídeo.
/// A prévia é feita pelo mesmo render da exportação, com o estilo padrão da predefinição.
private struct CaptionStyleCard: View {
    @Environment(EditorModel.self) private var model
    let preset: CaptionPreset
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = model.captionGeneration.highlightColor
        let key = CaptionPreviewFrames.Key(preset: preset, color: preset.usesAccent ? color : nil)
        let store = model.animationStrips
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    CardBackdrop()
                    FrameStripView(frames: store.strip(key), rest: CaptionPreviewFrames.restIndex,
                                   playing: hovering || selected, cycle: CaptionPreviewFrames.cycle) {
                        CaptionSample(layout: preset.layout, highlight: color.color)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : (hovering ? Color.white.opacity(0.22) : Theme.hairline),
                                  lineWidth: selected ? 1.5 : 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName)
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                        .lineLimit(1)
                    Text(preset.detail)
                        .font(Theme.font(10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .frame(maxWidth: .infinity)
        .help(preset.detail)
        .task(id: key) {
            store.request(key, urgent: true) { CaptionPreviewFrames.frames(key) }
        }
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
    let layout: CaptionLayout
    let highlight: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            switch layout {
            case .highlight:
                (Text("um vídeo ") + Text("muito").foregroundColor(highlight) + Text(" bom"))
                    .font(.system(size: h * 0.11, weight: .bold))
                    .modifier(CaptionInk())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, h * 0.12)
            case .punch, .stacked:
                Text("MUITO BOM")
                    .font(.system(size: h * 0.2, weight: .heavy))
                    .modifier(CaptionInk())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .phrases:
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
        let name = generation.model.displayName
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

/// Quadros da prévia de cada predefinição: uma frase falsa com tempo por palavra, montada pelo
/// `CaptionBuilder` e desenhada pelo `FrameRenderer` num canvas transparente 16:9.
enum CaptionPreviewFrames {
    struct Key: Hashable {
        let preset: CaptionPreset
        /// Cor do destaque (só nas predefinições que a usam).
        let color: RGBA?
    }

    static let pixelSize = CGSize(width: 384, height: 216)
    static let cycle = 3.6
    static let count = 72
    /// Quadro parado: no meio da frase, com uma palavra destacada.
    static let restIndex = 24

    private static let sample = "Hoje eu vou mostrar como gerar legendas no seu Mac."

    private nonisolated(unsafe) static let renderer = FrameRenderer()
    private nonisolated(unsafe) static let context = CIContext(options: [.cacheIntermediates: false])

    /// Uma palavra a cada ~0,26 s, a partir de 0,2 s.
    static func words() -> [TranscribedWord] {
        var t: Micros = 200_000
        return sample.split(separator: " ").map { (word: Substring) -> TranscribedWord in
            let length = Micros(170_000 + 18_000 * word.count)
            defer { t += length + 50_000 }
            return TranscribedWord(text: String(word), start: t, end: t + length)
        }
    }

    static func frames(_ key: Key) -> [CGImage] {
        var project = Project()
        project.canvas.background = .color(RGBA(0, 0, 0, 0))
        let cues = CaptionBuilder.cues(from: words(), preset: key.preset)
        CaptionBuilder.apply(cues, preset: key.preset, accent: key.color, to: &project, replacing: false)
        let plan = RenderPlan(project: project, renderSize: pixelSize)
        let rect = CGRect(origin: .zero, size: pixelSize)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return (0..<count).compactMap { i in
            let time = Micros(cycle * 1_000_000 * Double(i) / Double(count))
            let image = renderer.render(plan: plan, time: time) { _ in nil }
            return context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: space)
        }
    }
}
