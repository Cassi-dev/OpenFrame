import AppKit
import OpenCutCore
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
            HStack {
                Text("Exportar").font(.title2.bold())
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 10)

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
        .frame(width: 560)
        .frame(minHeight: 520)
        .background(Theme.panel)
    }

    private var footer: some View {
        let error = model.exportSettings.validationError(for: model.project)
        return HStack {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Exportar…") { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(error != nil)
        }
        .padding(20)
    }

    private func exportingView(_ progress: Double) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
            HStack {
                Text(String(format: "%.0f%%", progress * 100)).monospacedDigit()
                Spacer()
                if progress > 0.02 {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = elapsed / progress * (1 - progress)
                    Text("Restam ~\(Int(remaining.rounded())) s").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer()
            HStack {
                Spacer()
                Button("Cancelar exportação") { exporter?.cancel() }
            }
        }
        .padding(24)
    }

    private func finishedView(_ url: URL, _ bytes: Int64) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Exportação concluída").font(.title3.bold())
            Text("\(url.lastPathComponent) — \(bytes.formattedFileSize)")
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Abrir") { NSWorkspace.shared.open(url) }
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("A exportação falhou").font(.title3.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack {
                Button("Voltar às configurações") { phase = .configuring }
                Spacer()
                Button("Fechar") { dismiss() }
            }
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
        let project = model.project
        let size = settings.outputSize(for: project)
        let audioOnly = settings.container.isAudioOnly

        Form {
            Section("Arquivo") {
                Picker("Formato", selection: $model.exportSettings.container) {
                    ForEach(ContainerFormat.allCases) { Text($0.label).tag($0) }
                }
            }

            if !audioOnly {
                Section("Vídeo") {
                    Picker("Resolução", selection: $model.exportSettings.resolution) {
                        ForEach(ResolutionPreset.allCases) { Text($0.label).tag($0) }
                    }
                    if settings.resolution == .custom {
                        HStack {
                            TextField("Largura", value: $model.exportSettings.customWidth, format: .number)
                            Text("×")
                            TextField("Altura", value: $model.exportSettings.customHeight, format: .number)
                            Text("px").foregroundStyle(.secondary)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    Picker("Taxa de quadros", selection: $model.exportSettings.frameRate) {
                        ForEach(FrameRate.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Codificador", selection: $model.exportSettings.codec) {
                        ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                    }
                    if settings.codec != .proRes422 {
                        Picker("Qualidade", selection: $model.exportSettings.bitrateMode) {
                            ForEach(BitrateMode.allCases) { Text($0.label).tag($0) }
                        }
                        switch settings.bitrateMode {
                        case .custom:
                            HStack {
                                Slider(value: $model.exportSettings.customMbps, in: 0.5...150)
                                TextField("Mbps", value: $model.exportSettings.customMbps,
                                          format: .number.precision(.fractionLength(1)))
                                    .frame(width: 64)
                                    .textFieldStyle(.roundedBorder)
                                Text("Mbps").foregroundStyle(.secondary)
                            }
                        case .targetSize:
                            HStack {
                                TextField("MB", value: $model.exportSettings.targetMegabytes,
                                          format: .number.precision(.fractionLength(0)))
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                                Stepper("MB", value: $model.exportSettings.targetMegabytes, in: 1...20000, step: 5)
                            }
                        default:
                            EmptyView()
                        }
                        Stepper(value: $model.exportSettings.keyframeInterval, in: 0.5...10, step: 0.5) {
                            LabeledContent("Quadro-chave a cada", value: String(format: "%.1f s", settings.keyframeInterval))
                        }
                    }
                }
            }

            Section("Áudio") {
                Toggle("Incluir áudio", isOn: $model.exportSettings.audioEnabled)
                if settings.audioEnabled {
                    Picker("Bitrate", selection: $model.exportSettings.audioKbps) {
                        ForEach(ExportSettings.audioBitrates, id: \.self) { Text("\($0) kbps").tag($0) }
                    }
                    Picker("Taxa de amostragem", selection: $model.exportSettings.audioSampleRate) {
                        ForEach(ExportSettings.sampleRates, id: \.self) { Text("\($0) Hz").tag($0) }
                    }
                }
            }

            Section("Resumo") {
                if !audioOnly {
                    LabeledContent("Dimensões", value: "\(Int(size.width)) × \(Int(size.height))")
                    if settings.codec != .proRes422 {
                        let bps = settings.videoBitrate(size: size, duration: project.duration)
                        LabeledContent("Bitrate de vídeo", value: String(format: "%.2f Mbps", Double(bps) / 1_000_000))
                    } else {
                        LabeledContent("Bitrate de vídeo", value: "variável (ProRes)")
                    }
                }
                LabeledContent("Duração", value: Time.format(project.duration))
                LabeledContent("Tamanho estimado") {
                    Text("≈ \(settings.estimatedBytes(for: project).formattedFileSize)")
                        .foregroundStyle(Theme.accent)
                        .bold()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
