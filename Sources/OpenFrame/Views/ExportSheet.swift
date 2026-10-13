import AppKit
import OpenFrameCore
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(EditorModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case configuring
        case exporting(Double)
        case finished(URL, Int64)
        case failed(String)
    }

    @State private var phase = Phase.configuring
    @State private var exporter: Exporter?
    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Exportar").font(Theme.font(22, .light))
                Text(model.project.name).foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 14)

            switch phase {
            case .configuring:
                SettingsForm()
                footer
            case .exporting(let progress):
                exportingView(progress)
            case .finished(let url, let bytes):
                finishedView(url, bytes)
            case .failed(let message):
                failedView(message)
            }
        }
        .frame(width: 680)
        .frame(minHeight: 540)
        .background(Theme.surface)
        .font(Theme.font(12))
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var footer: some View {
        let error = model.exportSettings.validationError(for: model.project)
        return HStack {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.35))
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(PillButtonStyle(kind: .quiet))
            Button("Exportar…") { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(error != nil)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func exportingView(_ progress: Double) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(String(format: "%.0f%%", progress * 100))
                .font(Theme.mono(44, .thin))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 4)
            HStack {
                Text("Renderizando").foregroundStyle(Theme.textSecondary)
                Spacer()
                if progress > 0.02 {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = elapsed / progress * (1 - progress)
                    Text("Restam ~\(Int(remaining.rounded())) s").foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancelar exportação") { exporter?.cancel() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(24)
    }

    private func finishedView(_ url: URL, _ bytes: Int64) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(Theme.font(46, .thin))
                .foregroundStyle(Theme.accent)
            Text("Exportação concluída").font(Theme.font(18, .light))
            Text("\(url.lastPathComponent) · \(bytes.formattedFileSize)")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack {
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Abrir") { NSWorkspace.shared.open(url) }
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(24)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "xmark.octagon")
                .font(Theme.font(42, .thin))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
            Text("A exportação falhou").font(Theme.font(18, .light))
            Text(message)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack {
                Button("Voltar às configurações") { phase = .configuring }
                Spacer()
                Button("Fechar") { dismiss() }
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(24)
    }

    private func start() {
        let settings = model.exportSettings
        let panel = NSSavePanel()
        let ext = settings.container.fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .movie]
        panel.nameFieldStringValue = "\(model.project.name).\(ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if model.isPlaying { model.togglePlay() }
        let exporter = Exporter()
        self.exporter = exporter
        startedAt = Date()
        phase = .exporting(0)
        let project = model.project
        Task {
            do {
                try await exporter.export(project: project, settings: settings, to: url) { value in
                    Task { @MainActor in
                        if case .exporting = phase { phase = .exporting(value) }
                    }
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                phase = .finished(url, size)
            } catch is CancellationError {
                phase = .configuring
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

private struct SettingsForm: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let settings = model.exportSettings
        let audioOnly = settings.container.isAudioOnly

        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Arquivo")
                    FieldRow(label: "Formato") {
                        MenuField(selection: $model.exportSettings.container, options: ContainerFormat.allCases, title: \.label)
                    }

                    if !audioOnly {
                        SectionHeader(title: "Vídeo")
                        FieldRow(label: "Resolução") {
                            MenuField(selection: $model.exportSettings.resolution, options: ResolutionPreset.allCases, title: \.label)
                        }
                        if settings.resolution == .custom {
                            FieldRow(label: "Tamanho") {
                                HStack(spacing: 6) {
                                    NumberField(value: $model.exportSettings.customWidth)
                                    Text("×").foregroundStyle(Theme.textTertiary)
                                    NumberField(value: $model.exportSettings.customHeight)
                                    Text("px").foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        FieldRow(label: "Quadros/s") {
                            MenuField(selection: $model.exportSettings.frameRate, options: FrameRate.allCases, title: \.label)
                        }
                        FieldRow(label: "Codificador") {
                            MenuField(selection: $model.exportSettings.codec, options: VideoCodec.allCases, title: \.label)
                        }
                        if settings.codec != .proRes422 {
                            FieldRow(label: "Qualidade") {
                                MenuField(selection: $model.exportSettings.bitrateMode, options: BitrateMode.allCases, title: \.label)
                            }
                            switch settings.bitrateMode {
                            case .custom:
                                FieldRow(label: "Bitrate") {
                                    HStack(spacing: 8) {
                                        ThinSlider(value: $model.exportSettings.customMbps, range: 0.5...150)
                                        DecimalField(value: $model.exportSettings.customMbps, digits: 1)
                                            .frame(width: 58)
                                        Text("Mbps").foregroundStyle(Theme.textTertiary)
                                    }
                                }
                            case .targetSize:
                                FieldRow(label: "Tamanho alvo") {
                                    HStack(spacing: 8) {
                                        DecimalField(value: $model.exportSettings.targetMegabytes, digits: 0)
                                            .frame(width: 80)
                                        Text("MB").foregroundStyle(Theme.textTertiary)
                                        Stepper("", value: $model.exportSettings.targetMegabytes, in: 1...20000, step: 5)
                                            .labelsHidden()
                                    }
                                }
                            default:
                                EmptyView()
                            }
                            FieldRow(label: "Quadro-chave") {
                                HStack(spacing: 8) {
                                    Text(String(format: "a cada %.1f s", settings.keyframeInterval))
                                    Stepper("", value: $model.exportSettings.keyframeInterval, in: 0.5...10, step: 0.5)
                                        .labelsHidden()
                                }
                            }
                        }
                    }

                    SectionHeader(title: "Áudio")
                    SwitchRow(title: "Incluir áudio", isOn: $model.exportSettings.audioEnabled)
                    if settings.audioEnabled {
                        FieldRow(label: "Bitrate") {
                            MenuField(selection: $model.exportSettings.audioKbps, options: ExportSettings.audioBitrates,
                                      title: { "\($0) kbps" })
                        }
                        FieldRow(label: "Amostragem") {
                            MenuField(selection: $model.exportSettings.audioSampleRate, options: ExportSettings.sampleRates,
                                      title: { "\($0) Hz" })
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)

            SummaryCard()
                .frame(width: 210)
        }
        .padding(.horizontal, 24)
    }
}

/// Resumo à direita: o tamanho estimado em destaque.
private struct SummaryCard: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let settings = model.exportSettings
        let project = model.project
        let size = settings.outputSize(for: project)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tamanho estimado").foregroundStyle(Theme.textSecondary)
                Text(settings.estimatedBytes(for: project).formattedFileSize)
                    .font(Theme.font(28, .thin))
                    .foregroundStyle(Theme.accent)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if !settings.container.isAudioOnly {
                row("Dimensões", "\(Int(size.width)) × \(Int(size.height))")
                row("Quadros/s", settings.frameRate.label)
                if settings.codec != .proRes422 {
                    let bps = settings.videoBitrate(size: size, duration: project.duration)
                    row("Vídeo", String(format: "%.2f Mbps", Double(bps) / 1_000_000))
                } else {
                    row("Vídeo", "variável (ProRes)")
                }
            }
            row("Áudio", settings.audioEnabled ? "\(settings.audioKbps) kbps" : "sem áudio")
            row("Duração", Time.format(project.duration))
        }
        .padding(16)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline))
        .padding(.top, 10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value).font(Theme.mono(12))
        }
    }
}

private struct NumberField: View {
    @Binding var value: Int

    var body: some View {
        TextField("", value: $value, format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .font(Theme.mono(12))
            .padding(.horizontal, 8)
            .frame(width: 70, height: 28)
            .field()
    }
}

private struct DecimalField: View {
    @Binding var value: Double
    let digits: Int

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(digits)).grouping(.never))
            .textFieldStyle(.plain)
            .font(Theme.mono(12))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .field()
    }
}
