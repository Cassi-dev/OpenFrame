import AppKit
import AVFoundation
import CoreImage
import OpenFrameCore

/// Ferramenta de desenvolvimento: com `OPENFRAME_SNAPSHOT_DIR` definido, o app
/// percorre algumas telas, salva capturas das próprias janelas e fecha.
/// Um app pode capturar as próprias views sem permissão de gravação de tela.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(_ model: EditorModel) {
        guard let path = ProcessInfo.processInfo.environment["OPENFRAME_SNAPSHOT_DIR"] else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            await wait(4)
            model.seek(to: 1_500_000)
            await wait(1)
            capture("1-projeto", to: dir)
            await capturePlayerFrame(model, to: dir.appendingPathComponent("0-preview-frame.png"))

            let p = model.project
            if let main = p.mainTrackIndex, let first = p.tracks[main].segments.first {
                model.selection = first.id
                model.inspectorTab = .basic
                await wait(1)
                capture("2-clipe-basico", to: dir)
                model.inspectorTab = .filters
                await wait(2)
                capture("3-clipe-filtros", to: dir)
                model.inspectorTab = .transition
                await wait(1)
                capture("4-clipe-transicao", to: dir)
            }
            if let text = p.tracks.first(where: { $0.kind == .text })?.segments.first {
                model.selection = text.id
                model.inspectorTab = .text
                await wait(1)
                capture("5-texto", to: dir)
            }
            if let audio = p.tracks.first(where: { $0.kind == .audio })?.segments.first {
                model.selection = audio.id
                await wait(1)
                capture("7-audio", to: dir)
            }
            // Barra de ações do clipe na primeira e na última faixa exibidas.
            let rows = model.displayTrackOrder().map { p.tracks[$0] }
            if let first = rows.first?.segments.first {
                model.selection = first.id
                await wait(1)
                capture("10-barra-primeira-faixa", to: dir)
            }
            if rows.count > 1, let last = rows.last?.segments.last {
                model.selection = last.id
                model.seek(to: last.targetEnd - 200_000)
                await wait(1)
                capture("11-barra-ultima-faixa", to: dir)
            }
            // Zoom: o playhead (ou o ponto da pinça/roda) fica no mesmo lugar da tela.
            model.selection = nil
            model.seek(to: model.duration * 3 / 4)
            await wait(0.5)
            logZoom("antes", model)
            model.setZoom(model.zoom * 3)
            await wait(1)
            logZoom("aproximar ×3 (âncora: playhead)", model)
            capture("12-zoom-aproximado", to: dir)
            let anchor = model.zoomAnchor(contentX: model.timelineScrollX + 200)
            log("zoom: âncora da roda em x=200 → \(String(format: "%.3f", anchor.time)) s")
            model.setZoom(model.zoom / 2, keeping: anchor.time, at: anchor.x)
            await wait(1)
            logZoom("afastar ÷2 (âncora: x=200)", model)
            log("zoom: \(String(format: "%.3f", anchor.time)) s agora em x="
                + String(format: "%.1f", anchor.time * model.zoom - model.timelineScrollX))
            model.zoomToFit()
            await wait(1)
            logZoom("ajustar à janela", model)
            capture("13-zoom-ajustado", to: dir)
            model.selection = nil
            model.showGrid = true
            model.libraryPanel = .text
            await wait(1)
            capture("8-painel-texto-grade", to: dir)
            model.showGrid = false
            model.libraryPanel = .captions
            await wait(1)
            capture("9-painel-legendas", to: dir)
            model.libraryPanel = .media
            model.showExport = true
            await wait(1.5)
            capture("6-exportar", to: dir)
            NSApp.terminate(nil)
        }
    }

    /// Lê o quadro que o AVPlayer está exibindo (a camada de vídeo não entra no cacheDisplay).
    private static func capturePlayerFrame(_ model: EditorModel, to url: URL) async {
        guard let item = model.player.currentItem else {
            log("preview: sem item no player")
            return
        }
        log("preview: status=\(item.status.rawValue) erro=\(String(describing: item.error))")
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        model.seek(to: 2_000_000)
        try? await Task.sleep(for: .seconds(1.5))
        let time = item.currentTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            log("preview: nenhum quadro disponível em \(time.seconds)s")
            return
        }
        let image = CIImage(cvPixelBuffer: buffer)
        try? CIContext().writePNGRepresentation(of: image, to: url, format: .RGBA8,
                                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        log("preview: quadro \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) salvo")
        item.remove(output)
    }

    private static func logZoom(_ step: String, _ model: EditorModel) {
        let playheadX = model.playhead.seconds * model.zoom - model.timelineScrollX
        let projectWidth = model.duration.seconds * model.zoom
        log(String(format: "zoom: %@ → %.3f pt/s (mín. %.3f), rolagem %.1f, playhead na tela em x=%.1f, "
                   + "projeto %.0f pt de %.0f visíveis", step, model.zoom, model.minZoom,
                   model.timelineScrollX, playheadX, projectWidth, model.timelineViewportWidth))
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[snapshot] \(message)\n".utf8))
    }

    private static func capture(_ name: String, to dir: URL) {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.height > 150 }
        for (index, window) in windows.enumerated() {
            // A moldura da janela (superview) inclui os botões de fechar/minimizar/zoom.
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let suffix = windows.count > 1 ? "-\(index)" : ""
            try? rep.representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(name)\(suffix).png"))
        }
    }
}
