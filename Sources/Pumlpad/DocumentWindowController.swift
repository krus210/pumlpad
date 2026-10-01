import AppKit
import PumlCore

/// One document window: editor on the left, live preview on the right, status bar below.
/// It keeps the preview in step with the text; export and the toolbar live in their own types.
@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, DiagramExportSource {
    let editor = EditorViewController()
    private let preview = PreviewViewController()
    private let statusBar = StatusBarView()
    private let split = NSSplitViewController()
    let documentToolbar = DocumentToolbar()
    private let scheduler = RenderScheduler(debounce: .milliseconds(300))
    private lazy var exporter = DiagramExporter(source: self)
    /// Last render without errors; kept on screen, dimmed, while the source has an error.
    private var lastGood: RenderResult?
    private var lastError: DiagramError?
    /// Block and folder of the last render: a caret move to another block, or a document moved
    /// to another folder, needs a new render.
    private var renderedBlock: DiagramBlock?
    private var renderedFolder: URL?

    private var pumlDocument: PumlDocument? { document as? PumlDocument }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 640, height: 420)
        window.tabbingMode = .automatic
        super.init(window: window)
        window.delegate = self
        buildLayout(in: window)
        window.toolbar = documentToolbar.toolbar
        window.toolbarStyle = .unified
        window.center()

        editor.onTextChange = { [weak self] text in self?.textDidChange(text) }
        editor.onCaretLineChange = { [weak self] line in self?.caretDidMove(to: line) }
        preview.onZoomChange = { [weak self] zoom in self?.statusBar.zoom = zoom }
        statusBar.onErrorClick = { [weak self] in self?.revealError() }
        // Selector-based observers go away with the controller.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(darkDiagramsDidChange), name: Services.darkDiagramsDidChange, object: nil)
        center.addObserver(self, selector: #selector(localFileAccessDidChange), name: Services.localFileAccessDidChange, object: nil)
        center.addObserver(self, selector: #selector(documentFormatDidChange(_:)), name: PumlDocument.formatDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var document: AnyObject? {
        didSet { reloadFromDocument() }
    }

    func reloadFromDocument() {
        guard let pumlDocument else { return }
        editor.setText(pumlDocument.text)
        statusBar.documentInfo = pumlDocument.format.description
        lastGood = nil
        lastError = nil
        renderedBlock = nil
        editor.errorLine = nil
        statusBar.show(.idle)
        preview.setDarkBackground(Services.shared.darkDiagrams)
        scheduler.scheduleNow { [weak self] in await self?.render() }
        if pumlDocument.replacedBytes > 0 {
            // After the window is on screen, so the sheet has a window to attach to.
            DispatchQueue.main.async { [weak self] in self?.warnAboutReplacedBytes() }
        }
    }

    /// NSDocument calls this after Save As, Move To and Rename too, and when the window closes.
    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        guard let pumlDocument, let renderedFolder,
              renderedFolder != pumlDocument.workingDirectory.standardizedFileURL else { return }
        // Includes and file access depend on the folder.
        scheduler.scheduleNow { [weak self] in await self?.render() }
        Services.shared.releaseUnusedProcesses()
    }

    // MARK: Layout

    private func buildLayout(in window: NSWindow) {
        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 260
        editorItem.canCollapse = true
        let previewItem = NSSplitViewItem(viewController: preview)
        previewItem.minimumThickness = 260
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)

        let root = NSViewController()
        root.view = NSView(frame: NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size))
        root.addChild(split)
        for view in [split.view, statusBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.view.addSubview(view)
        }
        NSLayoutConstraint.activate([
            split.view.topAnchor.constraint(equalTo: root.view.topAnchor),
            split.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: split.view.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
        window.contentViewController = root
        root.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(root.view.bounds.width * 0.42, ofDividerAt: 0)
    }

    // MARK: Rendering

    /// The diagram under the caret.
    var exportBlock: DiagramBlock? {
        DiagramSource.block(in: editor.text, caretLine: editor.caretLine)
    }

    func renderOptions(format: OutputFormat) -> RenderOptions {
        Services.shared.renderOptions(format: format, for: pumlDocument)
    }

    private func textDidChange(_ text: String) {
        pumlDocument?.text = text
        scheduler.schedule { [weak self] in await self?.render() }
    }

    /// With several diagrams in one file, the preview follows the caret.
    private func caretDidMove(to line: Line) {
        guard DiagramSource.block(in: editor.text, caretLine: line)?.startLine != renderedBlock?.startLine else { return }
        scheduler.schedule { [weak self] in await self?.render() }
    }

    private func render() async {
        // A closing window has no document; its folder's process may already be stopped.
        guard pumlDocument != nil else { return }
        guard let renderer = Services.shared.renderer else {
            if case .failure(let missing) = Services.shared.toolchain {
                preview.showMessage(missing.description)
                statusBar.show(.failure(missing.description))
            }
            return
        }
        guard let block = exportBlock else {
            preview.showMessage("Start typing a diagram:\n\n@startuml\nAlice -> Bob : Hello\n@enduml")
            statusBar.show(.idle)
            editor.errorLine = nil
            lastGood = nil
            lastError = nil
            renderedBlock = nil
            return
        }
        if lastGood == nil { statusBar.show(.rendering) }
        let options = renderOptions(format: .svg)
        do {
            let result = try await renderer.render(block, options: options)
            renderedBlock = block
            renderedFolder = options.workingDirectory
            switch result.outcome {
            case .image(let svg):
                lastGood = result
                lastError = nil
                editor.errorLine = nil
                preview.show(svg: svg)
                statusBar.show(encodingHint(for: result).map { .warning($0) } ?? .rendered(result.duration))
                LaunchTiming.firstPreviewShown()
                DemoPlayer.startIfRequested(controller: self)
            case .error(let error):
                lastError = error
                editor.errorLine = error.line
                statusBar.show(.error(error, hint: accessHint(for: error) ?? encodingHint(for: result)))
                if let lastGood, lastGood.block.startLine == block.startLine {
                    preview.setStale(true)
                } else {
                    // Nothing valid to keep for this diagram.
                    lastGood = nil
                    preview.showMessage(StatusBarView.describe(error))
                }
            }
        } catch RenderFailure.stopped {
            // The process was stopped under this render: the window is closing or the app quits.
        } catch {
            statusBar.show(.failure(String(describing: error)))
        }
    }

    /// The sandbox reports a blocked file as "cannot include …".
    private func accessHint(for error: DiagramError) -> String? {
        guard error.message.hasPrefix("cannot include") else { return nil }
        guard let folder = pumlDocument?.folder else { return "save the document to use files next to it" }
        if Services.shared.allowsLocalFiles(in: folder) { return nil }
        if Services.trustRefusal(for: folder) != nil { return "files in “\(folder.lastPathComponent)” cannot be allowed, move the diagram to a project folder" }
        return "local files are off, see Diagram › Allow Local Files"
    }

    /// `-pipe` reads included files as UTF-8, so one in another encoding shows "�" or breaks the diagram.
    private func encodingHint(for result: RenderResult) -> String? {
        guard let file = result.includesNotInUTF8.first else { return nil }
        return "\(file) is not UTF-8, and PlantUML reads included files as UTF-8: open it and use File › Convert to Encoding › UTF-8"
    }

    private func warnAboutReplacedBytes() {
        guard let pumlDocument, pumlDocument.replacedBytes > 0 else { return }
        let count = pumlDocument.replacedBytes
        NSAlert.show(
            "\(count) \(count == 1 ? "byte" : "bytes") of “\(pumlDocument.displayName ?? "")” could not be read as \(TextFormat.name(of: pumlDocument.format.encoding))",
            details: """
            They are shown as “�”. Saving writes “�” in their place, so the document is not saved \
            automatically. If the file uses another encoding, choose it in File › Reopen with Encoding.
            """,
            in: window
        )
    }

    @objc private func darkDiagramsDidChange() {
        preview.setDarkBackground(Services.shared.darkDiagrams)
        documentToolbar.updateDarkDiagramsItem()
        scheduler.scheduleNow { [weak self] in await self?.render() }
    }

    @objc private func localFileAccessDidChange() {
        scheduler.scheduleNow { [weak self] in await self?.render() }
    }

    @objc private func documentFormatDidChange(_ notification: Notification) {
        guard let pumlDocument, notification.object as? PumlDocument === pumlDocument else { return }
        statusBar.documentInfo = pumlDocument.format.description
        if let reason = notification.userInfo?["reason"] as? String {
            NSAlert.show("“\(pumlDocument.displayName ?? "")” is now saved as UTF-8", details: reason, in: window)
        }
    }

    private func revealError() {
        guard let lastError else { return }
        editor.revealLine(lastError.line)
    }

    // MARK: Commands

    @objc func exportPNG(_ sender: Any?) { exporter.export(.png, scale: .standard) }
    @objc func exportRetinaPNG(_ sender: Any?) { exporter.export(.png, scale: .retina) }
    @objc func exportSVG(_ sender: Any?) { exporter.export(.svg, scale: .standard) }
    @objc func copyPNG(_ sender: Any?) { exporter.copy(.png) }
    @objc func copySVG(_ sender: Any?) { exporter.copy(.svg) }

    /// Export without the save panel, as the panel's Save button does.
    func export(_ format: OutputFormat, scale: ExportScale, to url: URL) {
        exporter.write(format, scale: scale, to: url)
    }

    @objc func zoomInDiagram(_ sender: Any?) { preview.zoomIn() }
    @objc func zoomOutDiagram(_ sender: Any?) { preview.zoomOut() }
    @objc func zoomDiagramToActualSize(_ sender: Any?) { preview.zoomToActualSize() }
    @objc func zoomDiagramToFit(_ sender: Any?) { preview.zoomToFit() }

    @objc func toggleEditor(_ sender: Any?) {
        guard let item = split.splitViewItems.first else { return }
        item.animator().isCollapsed.toggle()
    }

    /// Asks before letting diagrams of this folder read files: a downloaded `.puml` could read
    /// the user's files otherwise.
    @objc func toggleLocalFileAccess(_ sender: Any?) {
        guard let folder = pumlDocument?.folder, let window else { return }
        if Services.shared.allowsLocalFiles(in: folder) {
            Services.shared.setAllowsLocalFiles(false, in: folder)
            return
        }
        if let refusal = Services.trustRefusal(for: folder) {
            NSAlert.show(
                "Diagrams in “\(folder.lastPathComponent)” cannot read files",
                details: "\(refusal) Move the diagram and the files it includes into a folder of their own.",
                in: window
            )
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow diagrams in “\(folder.lastPathComponent)” to read files?"
        alert.informativeText = """
        They will be able to include and read files on this Mac, also outside the folder through “../”. \
        They still cannot reach the network. Allow this only for folders you trust; \
        Diagram › Trusted Folders lists them.
        """
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Services.shared.setAllowsLocalFiles(true, in: folder)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleEditor(_:)):
            menuItem.title = split.splitViewItems.first?.isCollapsed == true ? "Show Editor" : "Hide Editor"
        case #selector(toggleLocalFileAccess(_:)):
            guard let folder = pumlDocument?.folder else { return false }
            menuItem.title = "Allow Local Files in “\(folder.lastPathComponent)”…"
            menuItem.state = Services.shared.allowsLocalFiles(in: folder) ? .on : .off
        default:
            break
        }
        return true
    }

    // MARK: DiagramExportSource

    var exportFileName: String {
        pumlDocument?.fileURL?.deletingPathExtension().lastPathComponent ?? "diagram"
    }

    var exportFolder: URL? {
        pumlDocument?.folder
    }

    func report(_ state: StatusBarView.State) {
        statusBar.show(state)
    }

    // MARK: NSWindowDelegate

    /// Text edits go to the document's undo manager, which marks the document as edited.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        pumlDocument?.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        scheduler.cancel()
        preview.tearDown()
        Services.shared.releaseUnusedProcesses(excluding: pumlDocument)
    }
}
