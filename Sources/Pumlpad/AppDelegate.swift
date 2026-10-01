import AppKit
import PumlCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var signalSources: [DispatchSourceSignal] = []

    /// `kill`, `pkill` and Ctrl-C end an app without `applicationWillTerminate`, and PlantUML
    /// with a busy `dot` would outlive it. These signals quit the app the normal way instead.
    func applicationDidFinishLaunching(_ notification: Notification) {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
                // Should quitting wait for the user (a sheet is open, say), the signal still ends the app.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    MainActor.assumeIsolated { Services.shared.renderer?.shutdown() }
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Services.shared.renderer?.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func toggleDarkDiagrams(_ sender: Any?) {
        Services.shared.darkDiagrams.toggle()
    }

    @objc func increaseEditorFont(_ sender: Any?) {
        Services.shared.editorFontSize += 1
    }

    @objc func decreaseEditorFont(_ sender: Any?) {
        Services.shared.editorFontSize -= 1
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleDarkDiagrams(_:)):
            menuItem.state = Services.shared.darkDiagrams ? .on : .off
        case #selector(increaseEditorFont(_:)):
            return Services.shared.editorFontSize < Services.editorFontSizes.upperBound
        case #selector(decreaseEditorFont(_:)):
            return Services.shared.editorFontSize > Services.editorFontSizes.lowerBound
        default:
            break
        }
        return true
    }
}

/// App-wide state and settings shared by all document windows.
@MainActor
final class Services {
    static let shared = Services()
    static let darkDiagramsDidChange = Notification.Name("PumlpadDarkDiagramsDidChange")
    static let localFileAccessDidChange = Notification.Name("PumlpadLocalFileAccessDidChange")
    static let editorFontDidChange = Notification.Name("PumlpadEditorFontDidChange")
    static let editorFontSizes: ClosedRange<CGFloat> = 9...36

    let toolchain: Result<Toolchain, Toolchain.Missing>
    /// `nil` when Java or PlantUML is missing; windows then show `toolchain`'s error.
    let renderer: RenderService?
    private let defaults = UserDefaults.standard

    private init() {
        toolchain = Toolchain.discover()
        renderer = (try? toolchain.get()).map { RenderService(toolchain: $0) }
    }

    var darkDiagrams: Bool {
        get { defaults.bool(forKey: "darkDiagrams") }
        set {
            defaults.set(newValue, forKey: "darkDiagrams")
            NotificationCenter.default.post(name: Self.darkDiagramsDidChange, object: nil)
        }
    }

    var editorFontSize: CGFloat {
        get {
            let size = CGFloat(defaults.double(forKey: "editorFontSize"))
            return size == 0 ? 13 : size.clamped(to: Self.editorFontSizes)
        }
        set {
            defaults.set(Double(newValue.clamped(to: Self.editorFontSizes)), forKey: "editorFontSize")
            NotificationCenter.default.post(name: Self.editorFontDidChange, object: nil)
        }
    }

    // MARK: Trusted folders

    /// Folders whose diagrams may read files, like workspace trust, in the order they were
    /// trusted. Entries the rules now refuse (saved by an older version) do not count.
    var trustedFolders: [URL] {
        (defaults.stringArray(forKey: "trustedFolders") ?? [])
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { Self.trustRefusal(for: $0) == nil }
    }

    func allowsLocalFiles(in folder: URL) -> Bool {
        trustedFolders.contains(folder.standardizedFileURL)
    }

    func setAllowsLocalFiles(_ allowed: Bool, in folder: URL) {
        let folder = folder.standardizedFileURL
        var folders = trustedFolders.filter { $0 != folder }
        if allowed, Self.trustRefusal(for: folder) == nil { folders.append(folder) }
        storeTrustedFolders(folders)
    }

    func stopTrustingAllFolders() {
        storeTrustedFolders([])
    }

    /// Why `folder` cannot be trusted, or `nil` when it can. A trusted diagram can read any of
    /// the user's files through `../`, so folders that collect files from elsewhere are refused:
    /// any `.puml` that lands there later would be trusted too.
    static func trustRefusal(for folder: URL) -> String? {
        let path = folder.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL.path
        if path.contains(":") {
            return "Its path contains “:”, which PlantUML reads as a separator between folders."
        }
        if path == "/" || path == home || home.hasPrefix(path + "/") {
            return "It holds your whole home folder."
        }
        if path == downloads {
            return "Files from the internet land there, and they would be trusted too."
        }
        return nil
    }

    private func storeTrustedFolders(_ folders: [URL]) {
        defaults.set(folders.map(\.path), forKey: "trustedFolders")
        NotificationCenter.default.post(name: Self.localFileAccessDidChange, object: nil)
    }

    /// The only place render options are put together.
    func renderOptions(format: OutputFormat, for document: PumlDocument?) -> RenderOptions {
        let folder = document?.folder
        return RenderOptions(
            format: format,
            darkMode: darkDiagrams,
            workingDirectory: document?.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser,
            trustsLocalFiles: folder.map(allowsLocalFiles) ?? false
        )
    }

    /// Stops PlantUML processes of folders that no open document uses.
    func releaseUnusedProcesses(excluding closing: NSDocument? = nil) {
        let folders = NSDocumentController.shared.documents
            .filter { $0 !== closing }
            .compactMap { ($0 as? PumlDocument)?.workingDirectory }
        renderer?.stopProcesses(keeping: Set(folders))
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension NSAlert {
    /// A sheet on `window`, or a free-standing alert when there is none.
    static func show(_ message: String, details: String, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
