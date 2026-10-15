import Foundation
import Observation
import OpenFrameCore

/// Estado da janela "Legendas automáticas": as escolhas do usuário, os modelos
/// instalados e a fase da geração. Fica no `EditorModel` para as escolhas valerem
/// entre uma abertura e outra e para o DebugSnapshot montar cada estado da janela.
@MainActor
@Observable
final class CaptionGeneration {
    enum Source: Hashable { case timeline, clip }

    enum Phase: Equatable {
        case configuring
        case downloading(received: Int64, total: Int64)
        /// Mistura e transcrição levam o progresso total das duas (`overall`): a barra não volta a zero
        /// entre uma e outra; a fase só muda o rótulo.
        case mixing(Double)
        case transcribing(Double)
        case finished(count: Int)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .downloading, .mixing, .transcribing: true
            default: false
            }
        }
    }

    /// O recomendado na lista de precisão.
    static let recommended = WhisperModel.small

    var source = Source.timeline
    /// Código do idioma; `nil` = detectar automaticamente.
    var language: String?
    /// O idioma já foi preenchido com o do sistema (só na primeira abertura).
    var languageChosen = false
    var model = recommended
    var preset = CaptionPreset.phrases
    /// Cor de destaque: vai para onde a predefinição a usa (`usesAccent`).
    var highlightColor = WordHighlight().color
    var replacePrevious = true
    var phase = Phase.configuring
    /// A geração começou baixando o modelo (o passo "Baixar modelo" aparece no progresso).
    var includesDownload = false
    /// Início do download ou da transcrição (mistura incluída), para a estimativa do tempo restante.
    var phaseStartedAt = Date()
    /// Downloads pedidos na lista de precisão, fora da geração: modelo → fração.
    var downloads: [WhisperModel: Double] = [:]
    /// Falha do último download ou da remoção pela lista de precisão.
    var modelError: String?
    private(set) var installed: Set<WhisperModel> = []

    @ObservationIgnored let store = ModelStore.shared
    @ObservationIgnored private var downloadTasks: [WhisperModel: Task<Void, Never>] = [:]
    @ObservationIgnored var job: Task<Void, Never>?

    init() {
        refreshInstalled()
    }

    func setPhase(_ new: Phase) {
        if !Self.sameStage(new, phase) { phaseStartedAt = Date() }
        phase = new
    }

    private static func sameStage(_ a: Phase, _ b: Phase) -> Bool {
        switch (a, b) {
        case (.downloading, .downloading): true
        case (.mixing, .mixing), (.mixing, .transcribing), (.transcribing, .mixing), (.transcribing, .transcribing): true
        default: false
        }
    }

    // MARK: - Modelos

    func refreshInstalled() {
        installed = Set(WhisperModel.allCases.filter { store.isInstalled($0) })
    }

    /// Baixa pela lista de precisão; o progresso vai para `downloads`.
    func download(_ m: WhisperModel) {
        guard downloadTasks[m] == nil, !installed.contains(m) else { return }
        modelError = nil
        downloads[m] = 0
        let store = store
        downloadTasks[m] = Task { [weak self] in
            do {
                try await store.download(m) { fraction in
                    Task { @MainActor in
                        if self?.downloads[m] != nil { self?.downloads[m] = fraction }
                    }
                }
            } catch {
                // Cancelar pode chegar como `URLError.cancelled`, não só `CancellationError`.
                if !Task.isCancelled { self?.modelError = error.localizedDescription }
            }
            self?.downloads[m] = nil
            self?.downloadTasks[m] = nil
            self?.refreshInstalled()
        }
    }

    /// Para o download; o que já veio fica guardado e o próximo continua dali.
    func cancelDownload(_ m: WhisperModel) {
        downloadTasks[m]?.cancel()
        downloadTasks[m] = nil
        downloads[m] = nil
    }

    func delete(_ m: WhisperModel) {
        cancelDownload(m)
        do {
            try store.delete(m)
        } catch {
            modelError = error.localizedDescription
        }
        refreshInstalled()
    }

    /// Idioma do sistema, se estiver entre os oferecidos; senão, detectar.
    static func systemLanguage(in codes: [String]) -> String? {
        guard let code = Locale.current.language.languageCode?.identifier else { return nil }
        return codes.contains(code) ? code : nil
    }
}

