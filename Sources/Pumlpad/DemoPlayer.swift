import AppKit
import os
import PumlCore

/// Plays the scripted session recorded as docs/demo.gif (`scripts/record-demo.sh`).
///
/// Runs only when `PUMLPAD_DEMO` names a control file. The player places the window on a white
/// backdrop, writes the rectangle to record there for `screencapture -R`, waits for
/// `<file>.recording`, then types, breaks and fixes the diagram, completes a keyword, zooms,
/// exports a PNG, opens more documents in tabs and shows them all, and finally writes
/// `<file>.done`. If another app's window comes
/// in front of the rectangle it stops and writes "aborted" instead, so the script throws the
/// recording away rather than keep someone else's window in it.
///
/// With `PUMLPAD_DEMO_DRY_RUN=1` it plays in the background instead, for `DRY_RUN=1
/// scripts/record-demo.sh`: it does not take the front, skips what only works there (the open
/// Export menu, the completion list, tab switching) and checks saving on the way.
@MainActor
final class DemoPlayer {
    private struct Aborted: Error {
        let reason: String
    }

    private static var started = false
    private static let logger = Logger(subsystem: "com.sskorolev.pumlpad", category: "demo")
    private let controller: DocumentWindowController
    private let window: NSWindow
    private let control: URL
    private let dryRun = ProcessInfo.processInfo.environment["PUMLPAD_DEMO_DRY_RUN"] == "1"
    private var abortReason: String?
    /// What is recorded: the window and a white margin around it, for menus and the shadow.
    private var captured = NSRect.zero
    /// White behind the window and its margin, so no other app shows in the recording.
    private var backdrop: NSWindow?

    private var folder: URL {
        control.deletingLastPathComponent().appendingPathComponent("Diagrams")
    }

    static func startIfRequested(controller: DocumentWindowController) {
        guard !started, let path = ProcessInfo.processInfo.environment["PUMLPAD_DEMO"], let window = controller.window else { return }
        started = true
        let player = DemoPlayer(controller: controller, window: window, control: URL(fileURLWithPath: path))
        Task { await player.play() }
    }

    private init(controller: DocumentWindowController, window: NSWindow, control: URL) {
        self.controller = controller
        self.window = window
        self.control = control
    }

    private func play() async {
        let done = URL(fileURLWithPath: control.path + ".done")
        do {
            if dryRun { try await prepareDryRun() } else { try await prepare() }
            let watch = dryRun ? nil : Task { await watchFront() }
            defer { watch?.cancel() }
            try await script()
            if dryRun { try await checkSaving() }
            try? "done".write(to: done, atomically: true, encoding: .utf8)
        } catch {
            let reason = (error as? Aborted)?.reason ?? String(describing: error)
            Self.logger.error("Demo stopped: \(reason, privacy: .public)")
            try? "aborted: \(reason)".write(to: done, atomically: true, encoding: .utf8)
            // Hand the screen back at once. After a finished demo the backdrop and the hidden
            // pointer stay until the app quits, so the last frames show nothing but the window.
            backdrop?.orderOut(nil)
            NSCursor.unhide()
        }
        Services.shared.darkDiagrams = false
    }

    /// Puts the window in front, hands its rectangle to the script and waits for the recording.
    private func prepare() async throws {
        // The primary screen: screencapture counts its coordinates from that one's top-left corner.
        guard let screen = NSScreen.screens.first else { throw Aborted(reason: "no screen") }
        let size = NSSize(width: 1180, height: 720)
        let visible = screen.visibleFrame
        let frame = NSRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        window.setFrame(frame, display: true)
        captured = frame.insetBy(dx: -40, dy: -40).intersection(visible)
        let backdrop = NSWindow(contentRect: captured, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.backgroundColor = .white
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.isReleasedWhenClosed = false
        backdrop.isExcludedFromWindowsMenu = true
        backdrop.collectionBehavior = [.transient, .ignoresCycle]
        self.backdrop = backdrop
        NSApp.activate()
        backdrop.orderFront(nil)
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<50 where !isInFront() { try await pause(0.1, checked: false) }
        if let reason = foreignWindowReason() ?? (isInFront() ? nil : "Pumlpad is not the front app") {
            try? "not in front: \(reason)".write(to: control, atomically: true, encoding: .utf8)
            throw Aborted(reason: reason)
        }
        // A compact save panel: an expanded one would show the sidebar with the user's folders.
        UserDefaults.standard.set(false, forKey: "NSNavPanelExpandedStateForSaveMode")
        UserDefaults.standard.set(false, forKey: "NSNavPanelExpandedStateForSaveMode2")
        NSCursor.hide()
        // Hiding does not always last, so the pointer also moves out of the picture, to the menu bar.
        CGWarpMouseCursorPosition(CGPoint(x: screen.frame.midX, y: 1))

        // screencapture takes the rectangle from the top-left corner of the main screen.
        let rectangle = "\(Int(captured.minX)),\(Int(screen.frame.height - captured.maxY)),\(Int(captured.width)),\(Int(captured.height))"
        try rectangle.write(to: control, atomically: true, encoding: .utf8)
        let recording = URL(fileURLWithPath: control.path + ".recording")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: recording.path) { try await pause(0.1, checked: false) }
        guard FileManager.default.fileExists(atPath: recording.path) else { throw Aborted(reason: "the recording did not start") }
        try await pause(1.2)
    }

    private func prepareDryRun() async throws {
        window.setFrame(NSRect(x: 80, y: 80, width: 1180, height: 720), display: true)
        captured = window.frame
        try "dry run".write(to: control, atomically: true, encoding: .utf8)
        try await pause(1)
    }

    private func script() async throws {
        let editor = controller.editor
        // Live preview: each new line starts with a line break, so `@enduml` stays on its own line.
        editor.placeCaret(atEndOfLine: Line(index: 4))
        try await type("\nShop -> Payment : Charge card", in: editor)
        try await pause(0.6)
        try await type("\nPayment --> Shop : OK", in: editor)
        try await pause(0.6)
        // An unfinished message: the error appears on its line and the preview dims.
        try await type("\nShop -> ", in: editor)
        try await pause(2)
        try await type("Customer : Order confirmed", in: editor)
        try await pause(0.8)
        // Keyword completion.
        try await type("\npartic", in: editor)
        try await pause(0.3)
        if dryRun { try await type("ipant", in: editor) } else { editor.showCompletions(acceptingFirstAfter: 1.5) }
        try await type(" Bank", in: editor)
        try await pause(0.4)
        try await type("\nShop -> Bank : Reserve funds", in: editor)
        try await pause(1)

        // Zoom.
        for _ in 0..<2 {
            controller.zoomInDiagram(nil)
            try await pause(0.7)
        }
        controller.zoomDiagramToFit(nil)
        try await pause(0.9)

        try await exportPNG()

        // More documents, as tabs of this window.
        let c4 = try await openTab(folder.appendingPathComponent("c4-container.puml"))
        try await pause(2.6)
        c4.zoomInDiagram(nil)
        try await pause(1)
        c4.zoomDiagramToFit(nil)
        try await pause(0.8)
        Services.shared.darkDiagrams = true
        try await pause(2)
        Services.shared.darkDiagrams = false
        try await pause(0.8)

        // Several diagrams in one file: the preview follows the caret.
        let several = try await openTab(folder.appendingPathComponent("multiple-diagrams.puml"))
        try await pause(1.8)
        several.editor.placeCaret(atEndOfLine: Line(index: 16))
        try await pause(2.2)

        // All open documents at a glance, then back to the first one.
        guard !dryRun else { return }
        window.toggleTabOverview(nil)
        try await pause(2.8)
        window.toggleTabOverview(nil)
        try await pause(0.8)
        window.makeKeyAndOrderFront(nil)
        try await pause(1.5)
    }

    /// Dry run only: autosave writes the edited document, and a file with a byte that is not
    /// UTF-8 is left alone by autosave and written by an explicit save.
    private func checkSaving() async throws {
        let checkout = folder.appendingPathComponent("checkout.puml")
        try await autosave(controller.document as? NSDocument)
        guard try String(contentsOf: checkout, encoding: .utf8).contains("Reserve funds") else {
            throw Aborted(reason: "autosave did not write checkout.puml")
        }
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("checkout.png").path) else {
            throw Aborted(reason: "the export wrote no checkout.png")
        }

        let broken = folder.appendingPathComponent("broken.puml")
        // UTF-8 with one broken byte: read as UTF-8, the byte becomes "�".
        let original = Data("@startuml\nАлиса -> Боб : ".utf8) + Data([0x98]) + Data("\n@enduml\n".utf8)
        try original.write(to: broken)
        let tab = try await openTab(broken)
        try await pause(1)
        if let tabWindow = tab.window, let warning = tabWindow.attachedSheet { tabWindow.endSheet(warning) }
        tab.editor.placeCaret(atEndOfLine: Line(index: 1))
        try await type(" again", in: tab.editor)
        try await autosave(tab.document as? NSDocument)
        try await pause(3)
        guard try Data(contentsOf: broken) == original else { throw Aborted(reason: "autosave wrote over unreadable bytes") }
        let document = tab.document as? NSDocument
        let state = "edited \(document?.isDocumentEdited == true), sheet \(tab.window?.attachedSheet != nil), text \(tab.editor.text.debugDescription)"
        document?.save(nil)
        try await pause(1.5)
        guard let saved = try? String(contentsOf: broken, encoding: .utf8), saved.contains("\u{FFFD} again") else {
            let onDisk = (try? Data(contentsOf: broken)).map { String(decoding: $0, as: UTF8.self).debugDescription } ?? "unreadable"
            throw Aborted(reason: "saving did not write broken.puml (\(state); on disk \(onDisk); sheet now \(tab.window?.attachedSheet.map { String(describing: Swift.type(of: $0)) } ?? "none"))")
        }
    }

    /// A document that does not autosave never calls the completion handler, so this just waits.
    private func autosave(_ document: NSDocument?) async throws {
        guard let document else { throw Aborted(reason: "no document") }
        document.autosave(withImplicitCancellability: false) { _ in }
        try await pause(1.5)
    }

    /// Opens the toolbar's Export menu, picks Export PNG… and saves in the panel that follows.
    private func exportPNG() async throws {
        if !dryRun, let menu = controller.documentToolbar.exportMenu {
            let anchor = Self.view(in: window.contentView?.superview) { $0.toolTip == DocumentToolbar.exportToolTip }
            // The open menu runs its own event loop, where only timers of the common modes fire:
            // they press ↓ and Return, and close the menu should the keys not arrive.
            let timers = [
                keyTimer(code: 125, character: NSDownArrowFunctionKey, after: 1.1),
                keyTimer(code: 36, character: 0x0D, after: 1.6),
                closingTimer(menu, after: 4),
            ]
            timers.forEach { RunLoop.main.add($0, forMode: .common) }
            if let anchor {
                // Right-aligned with the button, so the menu stays over the window.
                let point = NSPoint(x: anchor.bounds.maxX - menu.size.width, y: anchor.isFlipped ? anchor.bounds.maxY + 4 : -4)
                menu.popUp(positioning: nil, at: point, in: anchor)
            } else if let content = window.contentView {
                menu.popUp(positioning: nil, at: NSPoint(x: content.bounds.maxX - 150, y: content.bounds.maxY - 4), in: content)
            }
            timers.forEach { $0.invalidate() }
        }
        if try await attachedSheet(within: 3) == nil { controller.exportPNG(nil) }
        guard let panel = try await attachedSheet(within: 3) else { throw Aborted(reason: "no save panel") }
        try await pause(1.6)
        // The panel's buttons cannot be pressed from code (NSSavePanel.ok raises), so the panel
        // closes and the PNG goes where its Save button would have put it.
        let url = (panel as? NSSavePanel)?.url ?? folder.appendingPathComponent("checkout.png")
        window.endSheet(panel, returnCode: .cancel)
        controller.export(.png, scale: .standard, to: url)
        try await pause(2.4)
    }

    /// The sheet on the demo window, once it shows up.
    private func attachedSheet(within seconds: Double) async throws -> NSWindow? {
        for _ in 0..<Int(seconds * 10) where window.attachedSheet == nil { try await pause(0.1) }
        return window.attachedSheet
    }

    /// Opens `url` as a new tab of the demo window, without it first showing as a window of its own.
    private func openTab(_ url: URL) async throws -> DocumentWindowController {
        let document = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSDocument, Error>) in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
                if let document { continuation.resume(returning: document) } else { continuation.resume(throwing: error ?? Aborted(reason: "cannot open \(url.lastPathComponent)")) }
            }
        }
        if document.windowControllers.isEmpty { document.makeWindowControllers() }
        guard let controller = document.windowControllers.first as? DocumentWindowController, let tab = controller.window else {
            throw Aborted(reason: "no window for \(url.lastPathComponent)")
        }
        window.addTabbedWindow(tab, ordered: .above)
        if !dryRun { tab.makeKeyAndOrderFront(nil) }
        return controller
    }

    // MARK: Staying in front

    /// Switching tabs leaves a moment without a visible main window, so a problem counts only
    /// when it is still there 0.3 s later.
    private func watchFront() async {
        var since: ContinuousClock.Instant?
        while !Task.isCancelled, abortReason == nil {
            if let reason = foreignWindowReason() ?? (isInFront() ? nil : "Pumlpad lost the front") {
                if let since, ContinuousClock.now - since > .milliseconds(300) { abortReason = reason }
                since = since ?? .now
            } else {
                since = nil
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The app is active: another app taking the front deactivates it.
    private func isInFront() -> Bool {
        NSApp.isActive
    }

    /// Another app's window over the recorded rectangle: its owner, for the log.
    private func foreignWindowReason() -> String? {
        let reference = CGWindowID((NSApp.mainWindow ?? window).windowNumber)
        guard let screen = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], reference)
                as? [[String: Any]] else { return nil }
        // CGWindow bounds count from the top-left corner of the main screen.
        let rectangle = CGRect(x: captured.minX, y: screen.frame.height - captured.maxY, width: captured.width, height: captured.height)
        for info in windows {
            guard let owner = info[kCGWindowOwnerPID as String] as? Int32, owner != getpid(),
                  let layer = info[kCGWindowLayer as String] as? Int, layer < 20,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.intersects(rectangle) else { continue }
            return "a window of \(info[kCGWindowOwnerName as String] as? String ?? "another app") is in front"
        }
        return nil
    }

    // MARK: Helpers

    /// Types like a person, a character at a time.
    private func type(_ text: String, in editor: EditorViewController) async throws {
        for character in text {
            editor.typeForDemo(String(character))
            try await pause(Double.random(in: 0.035...0.07))
        }
    }

    /// Waits, and stops the demo when the window is no longer safe to record.
    private func pause(_ seconds: Double, checked: Bool = true) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        if checked, let abortReason { throw Aborted(reason: abortReason) }
    }

    /// A timer that presses a key after `delay` seconds.
    private func keyTimer(code: UInt16, character: Int, after delay: Double) -> Timer {
        let characters = String(Character(UnicodeScalar(UInt32(character))!))
        nonisolated(unsafe) let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        )
        return Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { if let event { NSApp.postEvent(event, atStart: false) } }
        }
    }

    private func closingTimer(_ menu: NSMenu, after delay: Double) -> Timer {
        nonisolated(unsafe) let menu = menu
        return Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { menu.cancelTracking() }
        }
    }

    private static func view(in root: NSView?, where matches: (NSView) -> Bool) -> NSView? {
        guard let root else { return nil }
        if matches(root) { return root }
        for subview in root.subviews {
            if let found = view(in: subview, where: matches) { return found }
        }
        return nil
    }
}
