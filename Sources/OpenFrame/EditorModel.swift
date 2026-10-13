import AppKit
import AVFoundation
import Observation
import OpenFrameCore
import SwiftUI
import UniformTypeIdentifiers

enum InspectorTab: String, CaseIterable, Identifiable {
    case basic, adjust, filters, effects, animation, transition, text, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: "Básico"
        case .adjust: "Ajustar"
        case .filters: "Filtros"
        case .effects: "Efeitos"
        case .animation: "Animação"
        case .transition: "Transição"
        case .text: "Texto"
        case .audio: "Áudio"
        }
    }

    var icon: String {
        switch self {
        case .basic: "arrow.up.and.down.and.arrow.left.and.right"
        case .adjust: "slider.horizontal.3"
        case .filters: "camera.filters"
        case .effects: "sparkles"
        case .animation: "wand.and.stars"
        case .transition: "arrow.left.arrow.right"
        case .text: "textformat"
        case .audio: "waveform"
        }
    }
}

/// Painel da biblioteca, escolhido na barra de ferramentas da esquerda.
enum LibraryPanel: String, CaseIterable, Identifiable {
    case media, text, captions, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Mídia"
        case .text: "Texto"
        case .captions: "Legendas"
        case .shortcuts: "Atalhos"
        }
    }

    var icon: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .text: "textformat"
        case .captions: "captions.bubble"
        case .shortcuts: "keyboard"
        }
    }
}

/// Estado do editor. Toda alteração no projeto passa por `mutate` (com
/// desfazer) ou pelos métodos de gesto, que atualizam o preview.
@MainActor
@Observable
final class EditorModel {
    private(set) var project = Project()
    var selection: UUID? {
        didSet { if selection != oldValue { ensureValidTab() } }
    }
    var inspectorTab = InspectorTab.basic
    var libraryPanel = LibraryPanel.media
    var libraryVisible = true
    /// Grade dos terços sobre o preview.
    var showGrid = false
    private(set) var playhead: Micros = 0
    private(set) var isPlaying = false
    /// Pontos por segundo na timeline.
    var zoom: Double = 80
    var exportSettings = ExportSettings()
    var showExport = false
    var errorMessage: String?
    private(set) var documentURL: URL?
    private(set) var isDirty = false
    private(set) var thumbnails: [UUID: [CGImage]] = [:]
    /// Picos de áudio por material (`Waveform.peaksPerSecond` por segundo).
    private(set) var waveforms: [UUID: [Float]] = [:]

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var undoStack: [Project] = []
    @ObservationIgnored private var redoStack: [Project] = []
    @ObservationIgnored private var lastCoalesceKey: String?
    @ObservationIgnored private var lastCoalesceTime = Date.distantPast
    @ObservationIgnored private var gestureBase: Project?
    @ObservationIgnored private var structureKey: CompositionBuilder.StructureKey?
    @ObservationIgnored private var planBox: PlanBox?
    @ObservationIgnored private var previewRenderSize: CGSize = .zero
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var pendingSeek: CMTime?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var keyMonitor: Any?
    /// Última versão de cada segmento mostrado no inspetor (ver `binding`).
    @ObservationIgnored private var inspectedSegments: [UUID: Segment] = [:]

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var duration: Micros { project.duration }
    var selectedSegment: Segment? { selection.flatMap { project.segment($0) } }

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playerTimeChanged(time) }
        }
        installKeyMonitor()
        // `OpenFrame -open caminho.openframe` (argumentos com "-" viram UserDefaults;
        // caminhos soltos seriam tratados pelo AppKit como documentos a abrir).
        if let path = UserDefaults.standard.string(forKey: "open") {
            open(url: URL(fileURLWithPath: path))
        } else {
            rebuildPreview()
        }
        DebugSnapshot.runIfRequested(self)
    }

    // MARK: - Alterações e desfazer

    /// Aplica uma alteração com desfazer. Alterações com a mesma `coalesce`
    /// em sequência (ex.: arrastar um slider) viram um único passo.
    func mutate(coalesce: String? = nil, _ change: (inout Project) -> Void) {
        var copy = project
        change(&copy)
        guard copy != project else { return }
        let now = Date()
        let merges = coalesce != nil && coalesce == lastCoalesceKey && now.timeIntervalSince(lastCoalesceTime) < 1
        if !merges { pushUndo(project) }
        lastCoalesceKey = coalesce
        lastCoalesceTime = now
        setProject(copy)
    }

    private func pushUndo(_ snapshot: Project) {
        undoStack.append(snapshot)
        if undoStack.count > 300 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        lastCoalesceKey = nil
        setProject(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        lastCoalesceKey = nil
        setProject(next)
    }

    private func setProject(_ p: Project) {
        project = p
        isDirty = true
        if let id = selection, p.segment(id) == nil { selection = nil }
        if playhead > p.duration { playhead = p.duration }
        projectDidChange()
    }

    // Gestos (arrastar clipes): cada atualização parte do estado do início
    // do gesto; o desfazer é registrado uma vez, ao soltar.

    func beginGesture() {
        if gestureBase == nil { gestureBase = project }
    }

    func updateGesture(_ change: (inout Project) -> Void) {
        guard var copy = gestureBase else { return }
        change(&copy)
        guard copy != project else { return }
        project = copy
        isDirty = true
        projectDidChange()
    }

    func endGesture() {
        if let base = gestureBase, base != project {
            pushUndo(base)
            lastCoalesceKey = nil
        }
        gestureBase = nil
    }

    var gestureSnapshot: Project? { gestureBase }

    // MARK: - Bindings para o inspetor

    /// Ao apagar o clipe selecionado (ou desfazer a criação dele), o SwiftUI
    /// ainda reavalia a aba do inspetor uma vez antes de removê-la, quando o
    /// segmento já não está no projeto. Os bindings usam então a última versão
    /// conhecida dele.
    func binding<T: Equatable>(_ id: UUID, _ keyPath: WritableKeyPath<Segment, T>) -> Binding<T> {
        if let seg = project.segment(id) { inspectedSegments[id] = seg }
        let fallback = inspectedSegments[id]
        return Binding(
            get: { [weak self] in
                // O segmento sempre existe quando o inspetor o mostra pela primeira vez.
                (self?.project.segment(id) ?? fallback)![keyPath: keyPath]
            },
            set: { [weak self] value in
                self?.mutate(coalesce: "\(id)\(keyPath)") { p in
                    TimelineEditor.update(&p, segment: id) { $0[keyPath: keyPath] = value }
                }
            })
    }

    func projectBinding<T: Equatable>(_ keyPath: WritableKeyPath<Project, T>) -> Binding<T> {
        Binding(
            get: { [weak self] in self?.project[keyPath: keyPath] ?? Project()[keyPath: keyPath] },
            set: { [weak self] value in
                self?.mutate(coalesce: "\(keyPath)") { $0[keyPath: keyPath] = value }
            })
    }

    func trackBinding(_ trackId: UUID, _ keyPath: WritableKeyPath<Track, Bool>) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.project.tracks.first { $0.id == trackId }?[keyPath: keyPath] ?? false },
            set: { [weak self] value in
                self?.mutate { p in
                    if let i = p.tracks.firstIndex(where: { $0.id == trackId }) { p.tracks[i][keyPath: keyPath] = value }
                }
            })
    }

    private func ensureValidTab() {
        guard let seg = selectedSegment else { return }
        let tabs = availableTabs(for: seg)
        if !tabs.contains(inspectorTab) { inspectorTab = tabs.first ?? .basic }
    }

    func availableTabs(for seg: Segment) -> [InspectorTab] {
        if seg.text != nil { return [.text, .animation] }
        guard let m = project.material(seg.materialId) else { return [] }
        if m.kind == .audio { return [.audio] }
        var tabs: [InspectorTab] = [.basic, .adjust, .filters, .effects, .animation]
        if isOnMainTrack(seg.id), !isLastOnMainTrack(seg.id) { tabs.append(.transition) }
        return tabs
    }

    func isOnMainTrack(_ id: UUID) -> Bool {
        guard let loc = project.locate(id) else { return false }
        return project.tracks[loc.track].isMain
    }

    func isLastOnMainTrack(_ id: UUID) -> Bool {
        guard let main = project.mainTrackIndex else { return true }
        return project.tracks[main].segments.last?.id == id
    }

    // MARK: - Preview

    private var previewSize: CGSize { project.canvasSize(shortSide: 720) }

    private func projectDidChange() {
        let key = CompositionBuilder.structureKey(project)
        if key == structureKey, let box = planBox, previewRenderSize == previewSize {
            box.update(project: project)
            refreshFrame()
        } else {
            rebuildPreview()
        }
    }

    private func rebuildPreview() {
        rebuildTask?.cancel()
        let snapshot = project
        let size = previewSize
        let key = CompositionBuilder.structureKey(snapshot)
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            do {
                let built = try await CompositionBuilder.build(project: snapshot, renderSize: size,
                                                               frameDuration: CMTime(value: 1, timescale: 30))
                guard !Task.isCancelled, let self else { return }
                built.box.update(project: self.project)
                let item = AVPlayerItem(asset: built.composition)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                item.audioTimePitchAlgorithm = .spectral
                let resume = self.isPlaying
                self.player.replaceCurrentItem(with: item)
                self.planBox = built.box
                self.structureKey = key
                self.previewRenderSize = size
                self.seekPlayer(to: self.playhead.cmTime)
                if resume { self.player.play() }
            } catch {
                self?.errorMessage = "Falha ao montar o preview: \(error.localizedDescription)"
            }
        }
    }

    /// Força o redesenho do quadro atual após mudar só efeitos.
    private func refreshFrame() {
        guard !isPlaying, let item = player.currentItem,
              let composition = item.videoComposition?.mutableCopy() as? AVVideoComposition
        else { return }
        item.videoComposition = composition
        seekPlayer(to: playhead.cmTime)
    }

    private func playerTimeChanged(_ time: CMTime) {
        guard isPlaying else { return }
        playhead = min(time.micros, duration)
        if player.rate == 0 || playhead >= duration {
            isPlaying = false
        }
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
            playhead = min(player.currentTime().micros, duration)
        } else {
            guard duration > 0 else { return }
            if playhead >= duration - 30_000 { seek(to: 0) }
            isPlaying = true
            player.play()
        }
    }

    func seek(to t: Micros) {
        playhead = min(max(0, t), duration)
        seekPlayer(to: playhead.cmTime)
    }

    func step(frames: Int) {
        if isPlaying { togglePlay() }
        seek(to: playhead + Micros(Double(frames) / project.fps * 1_000_000))
    }

    /// Busca "perseguida": enquanto uma busca está em andamento, guarda só a
    /// mais recente, para o scrub não acumular atraso.
    private func seekPlayer(to time: CMTime) {
        pendingSeek = time
        guard !isSeeking else { return }
        performPendingSeek()
    }

    private func performPendingSeek() {
        guard let target = pendingSeek else { return }
        pendingSeek = nil
        isSeeking = true
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.performPendingSeek()
            }
        }
    }

    // MARK: - Mídia

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaProbe.supportedTypes
        panel.allowsMultipleSelection = true
        panel.message = "Escolha vídeos, fotos ou áudios"
        if panel.runModal() == .OK { importMedia(panel.urls) }
    }

    func importMedia(_ urls: [URL]) {
        Task {
            var failures: [String] = []
            for url in urls {
                do {
                    let m = try await MediaProbe.probe(url)
                    if !project.materials.contains(where: { $0.path == m.path }) {
                        mutate { $0.materials.append(m) }
                        loadThumbnails(m)
                    }
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }

    func addToTimeline(_ m: Material) {
        var id: UUID?
        mutate { id = TimelineEditor.addMedia(m, to: &$0, at: playhead) }
        selection = id
    }

    func addAsOverlay(_ m: Material) {
        var id: UUID?
        mutate { id = TimelineEditor.addOverlay(m, to: &$0, at: playhead) }
        selection = id
    }

    func removeMaterial(_ m: Material) {
        mutate { p in
            let ids = p.tracks.flatMap(\.segments).filter { $0.materialId == m.id }.map(\.id)
            for id in ids { TimelineEditor.delete(&p, segment: id) }
            p.materials.removeAll { $0.id == m.id }
        }
        thumbnails[m.id] = nil
        waveforms[m.id] = nil
    }

    func usageCount(_ m: Material) -> Int {
        project.tracks.flatMap(\.segments).filter { $0.materialId == m.id }.count
    }

    private func loadThumbnails(_ m: Material) {
        guard thumbnails[m.id] == nil else { return }
        if m.hasAudio {
            Task { waveforms[m.id] = try? await Waveform.peaks(url: m.url) }
        }
        Task {
            switch m.kind {
            case .video:
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: m.url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 240, height: 240)
                var images: [CGImage] = []
                let count = 10
                for i in 0..<count {
                    let t = CMTime(seconds: m.duration.seconds * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
                    if let (image, _) = try? await generator.image(at: t) { images.append(image) }
                }
                thumbnails[m.id] = images
            case .photo:
                if let src = CGImageSourceCreateWithURL(m.url as CFURL, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                       kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 240,
                   ] as CFDictionary) {
                    thumbnails[m.id] = [image]
                }
            case .audio:
                thumbnails[m.id] = []
            }
        }
    }

    // MARK: - Edição

    /// Segmento a editar: o selecionado, ou o da faixa principal sob o cursor.
    private var targetSegmentId: UUID? {
        if let selection { return selection }
        guard let main = project.mainTrackIndex else { return nil }
        return project.tracks[main].segments.first { $0.targetRange.contains(playhead) }?.id
    }

    func splitAtPlayhead() {
        guard let id = targetSegmentId else { return }
        var right: UUID?
        mutate { right = TimelineEditor.split(&$0, segment: id, at: playhead) }
        if let right { selection = right }
    }

    func deleteSelection() {
        guard let id = selection else { return }
        mutate { TimelineEditor.delete(&$0, segment: id) }
        selection = nil
    }

    func duplicateSelection() {
        guard let id = selection else { return }
        var copy: UUID?
        mutate { copy = TimelineEditor.duplicate(&$0, segment: id) }
        selection = copy
    }

    func addText(style: TextStyle = TextStyle()) {
        var id: UUID?
        mutate { id = TimelineEditor.addText(TextContent(text: "Digite seu texto", style: style), to: &$0, at: playhead) }
        selection = id
        inspectorTab = .text
    }

    func importSubtitles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let cues = SRT.parse(content)
            guard !cues.isEmpty else {
                errorMessage = "Nenhuma legenda encontrada em \(url.lastPathComponent)."
                return
            }
            var style = TextStyle()
            style.fontSize = 0.055
            style.strokeWidth = 3
            mutate { SRT.importCues(cues, into: &$0, style: style) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSubtitles() {
        let cues = SRT.cues(from: project)
        guard !cues.isEmpty else {
            errorMessage = "Não há textos na timeline para exportar como legenda."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(project.name).srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SRT.serialize(cues).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Arrastar na timeline

    func dragMove(_ id: UUID, dx: CGFloat) {
        beginGesture()
        selection = id
        guard let base = gestureBase, let seg = base.segment(id), let loc = base.locate(id) else { return }
        let delta = Micros(Double(dx) / zoom * 1_000_000)
        if base.tracks[loc.track].isMain {
            let center = (seg.targetStart + seg.targetEnd) / 2 + delta
            updateGesture { TimelineEditor.reorderMain(&$0, segment: id, toCenter: center) }
            return
        }
        let points = TimelineEditor.snapPoints(base, excluding: id, extra: [playhead])
        let threshold = Micros(8 / zoom * 1_000_000)
        var start = max(0, seg.targetStart + delta)
        let snappedStart = TimelineEditor.snap(start, to: points, threshold: threshold)
        if snappedStart != start {
            start = snappedStart
        } else {
            let end = start + seg.targetDuration
            start += TimelineEditor.snap(end, to: points, threshold: threshold) - end
        }
        updateGesture { TimelineEditor.move(&$0, segment: id, toStart: start) }
    }

    /// Ao soltar: move para outra faixa (deslocamento vertical em linhas) e
    /// resolve sobreposições.
    func endDragMove(_ id: UUID, rows: Int) {
        if rows != 0, gestureBase != nil {
            let order = displayTrackOrder()
            if let loc = project.locate(id),
               let row = order.firstIndex(of: loc.track) {
                let targetRow = row + rows
                if order.indices.contains(targetRow) {
                    let target = order[targetRow]
                    updateGestureInPlace { TimelineEditor.moveToTrack(&$0, segment: id, track: target) }
                }
            }
        }
        updateGestureInPlace { TimelineEditor.resolveOverlap(&$0, segment: id) }
        endGesture()
    }

    func dragTrim(_ id: UUID, leading: Bool, dx: CGFloat) {
        beginGesture()
        selection = id
        guard let base = gestureBase, let seg = base.segment(id) else { return }
        let delta = Micros(Double(dx) / zoom * 1_000_000)
        let points = TimelineEditor.snapPoints(base, excluding: id, extra: [playhead])
        let threshold = Micros(8 / zoom * 1_000_000)
        if leading {
            let target = TimelineEditor.snap(seg.targetStart + delta, to: points, threshold: threshold)
            updateGesture { TimelineEditor.trimStart(&$0, segment: id, to: target) }
        } else {
            let target = TimelineEditor.snap(seg.targetEnd + delta, to: points, threshold: threshold)
            updateGesture { TimelineEditor.trimEnd(&$0, segment: id, to: target) }
        }
    }

    private func updateGestureInPlace(_ change: (inout Project) -> Void) {
        var copy = project
        change(&copy)
        guard copy != project else { return }
        project = copy
        projectDidChange()
    }

    /// Ordem das faixas de cima para baixo: textos, sobreposições, principal, áudios.
    func displayTrackOrder() -> [Int] {
        let t = project.tracks
        let texts = t.indices.filter { t[$0].kind == .text }.reversed()
        let overlays = t.indices.filter { t[$0].kind == .video && !t[$0].isMain }.reversed()
        let main = t.indices.filter { t[$0].isMain }
        let audios = t.indices.filter { t[$0].kind == .audio }
        return Array(texts) + Array(overlays) + main + audios
    }

    // MARK: - Arquivo

    func newProject() {
        guard confirmDiscardChanges() else { return }
        if isPlaying { togglePlay() }
        project = Project()
        undoStack.removeAll()
        redoStack.removeAll()
        selection = nil
        documentURL = nil
        isDirty = false
        playhead = 0
        projectDidChange()
    }

    func openProject() {
        guard confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectStore.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    /// Abre um projeto `.openframe` (menu, Finder ou linha de comando).
    func open(url: URL) {
        if documentURL?.standardizedFileURL == url.standardizedFileURL, !isDirty { return }
        do {
            let loaded = try ProjectStore.load(from: url)
            if isPlaying { togglePlay() }
            project = loaded
            undoStack.removeAll()
            redoStack.removeAll()
            selection = nil
            documentURL = url
            isDirty = false
            playhead = 0
            thumbnails.removeAll()
            waveforms.removeAll()
            loaded.materials.forEach(loadThumbnails)
            projectDidChange()
            let missing = loaded.materials.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !missing.isEmpty {
                errorMessage = "Arquivos não encontrados:\n" + missing.map(\.path).joined(separator: "\n")
            }
        } catch {
            errorMessage = "Não foi possível abrir o projeto: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveProject(as saveAs: Bool = false) -> Bool {
        var url = documentURL
        if url == nil || saveAs {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: ProjectStore.fileExtension) ?? .json]
            panel.nameFieldStringValue = "\(project.name).\(ProjectStore.fileExtension)"
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            url = chosen
        }
        guard let url else { return false }
        do {
            var p = project
            p.name = url.deletingPathExtension().lastPathComponent
            try ProjectStore.save(p, to: url)
            project = p
            documentURL = url
            isDirty = false
            return true
        } catch {
            errorMessage = "Não foi possível salvar: \(error.localizedDescription)"
            return false
        }
    }

    private func confirmDiscardChanges() -> Bool {
        guard isDirty, project.duration > 0 || !project.materials.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Salvar as alterações em “\(project.name)”?"
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Descartar")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveProject()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    // MARK: - Teclado

    /// Espaço, Delete e setas funcionam em qualquer lugar, exceto ao digitar texto.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // O NSEvent não é Sendable: só o código e os modificadores entram no MainActor.
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self?.handleKey(keyCode, flags) ?? false }
            return handled ? nil : event
        }
    }

    private func handleKey(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        if !flags.intersection([.command, .control, .option]).isEmpty { return false }
        guard NSApp.keyWindow?.sheetParent == nil, NSApp.keyWindow?.attachedSheet == nil else { return false }
        switch keyCode {
        case 49: togglePlay()
        case 51, 117: deleteSelection()
        case 123: step(frames: flags.contains(.shift) ? -10 : -1)
        case 124: step(frames: flags.contains(.shift) ? 10 : 1)
        default: return false
        }
        return true
    }
}
