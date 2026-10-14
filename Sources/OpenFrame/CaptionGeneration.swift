import Foundation
import Observation
import OpenFrameCore

/// Estado da janela "Legendas automáticas": as escolhas do usuário e a fase da
/// geração. Fica no `EditorModel` para as escolhas valerem entre uma abertura e
/// outra e para o DebugSnapshot montar cada estado da janela.
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

    var source = Source.timeline
    /// Código do idioma; `nil` = detectar automaticamente.
    var language: String?
    /// `rawValue` do modelo do Whisper escolhido.
    var modelID = "small"
    /// `rawValue` do layout das legendas.
    var layoutID = "phrases"
    var highlightColor = RGBA(1, 0.85, 0.1)
    var replacePrevious = true
    var phase = Phase.configuring
    /// A geração começou baixando o modelo (o passo "Baixar modelo" aparece no progresso).
    var includesDownload = false
    /// Início do download ou da transcrição (mistura incluída), para a estimativa do tempo restante.
    var phaseStartedAt = Date()
    /// Downloads pedidos na lista de precisão, fora da geração: id do modelo → fração.
    var downloads: [String: Double] = [:]

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

    /// Idioma do sistema, se estiver entre os oferecidos; senão, detectar.
    static func systemLanguage(in codes: [String]) -> String? {
        guard let code = Locale.current.language.languageCode?.identifier else { return nil }
        return codes.contains(code) ? code : nil
    }
}
