import AppKit
import PumlCore

/// A `.puml` file. The editor writes every change to `text`, so saving and autosave read it directly.
@objc(PumlDocument)
final class PumlDocument: NSDocument {
    /// Posted when `format` changes; `userInfo["reason"]` says why when the user did not ask for it.
    static let formatDidChange = Notification.Name("PumlpadDocumentFormatDidChange")

    nonisolated static let template = """
    @startuml
    Alice -> Bob : Hello
    Bob --> Alice : Hi!
    @enduml

    """

    /// NSDocument calls `read` and `data(ofType:)` outside the main actor's view, but on the main
    /// thread, because this class enables neither concurrent reading nor asynchronous saving.
    nonisolated(unsafe) var text = PumlDocument.template
    /// The file's encoding and line breaks, restored on save.
    nonisolated(unsafe) private(set) var format = TextFormat.standard
    /// Bytes the file's encoding could not read, shown as "�". Saving would write "�" in their
    /// place, so such a document is not autosaved until the user saves it.
    nonisolated(unsafe) private(set) var replacedBytes = 0

    /// The folder of a saved document; relative `!include` paths resolve against it.
    var folder: URL? {
        fileURL?.deletingLastPathComponent()
    }

    /// Where PlantUML runs: the document's folder, or the home folder while untitled.
    var workingDirectory: URL {
        folder ?? FileManager.default.homeDirectoryForCurrentUser
    }

    override class var autosavesInPlace: Bool {
        true
    }

    /// `nil` stops autosaving, so a file with unreadable bytes changes only when the user saves it.
    override var autosavingFileType: String? {
        replacedBytes > 0 ? nil : super.autosavingFileType
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    override func data(ofType typeName: String) throws -> Data {
        // Without autosaving only the user saves, so from now on the "�" are in the file anyway.
        replacedBytes = 0
        if !format.canStore(text) {
            // Failing every autosave would leave the file behind the editor: keep the characters
            // and move the file to UTF-8, and tell the user.
            let previous = TextFormat.name(of: format.encoding)
            format = TextFormat(encoding: .utf8, lineBreak: format.lineBreak)
            let reason = "\(previous) cannot store some of the characters, so the file is now saved as UTF-8."
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.formatDidChange, object: self, userInfo: ["reason": reason])
            }
        }
        return try format.encode(text)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        apply(try TextFormat.decode(data))
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        reloadWindows()
    }

    // MARK: Encodings

    /// File › Reopen with Encoding: reads the file again as the chosen encoding.
    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let url = fileURL, TextFormat.encodings.indices.contains(sender.tag) else { return }
        let encoding = TextFormat.encodings[sender.tag]
        let reopen = { [self] in
            do {
                apply(try TextFormat.decode(Data(contentsOf: url), as: encoding))
                undoManager?.removeAllActions()
                updateChangeCount(.changeCleared)
                reloadWindows()
            } catch {
                presentError(error)
            }
        }
        guard isDocumentEdited, let window = windowForSheet else { return reopen() }
        let alert = NSAlert()
        alert.messageText = "Reopen “\(displayName ?? url.lastPathComponent)” as \(TextFormat.name(of: encoding))?"
        alert.informativeText = "Changes that are not saved yet will be lost."
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { reopen() }
        }
    }

    /// File › Convert to Encoding: the next save writes the file in the chosen encoding.
    @objc func convertToEncoding(_ sender: NSMenuItem) {
        guard TextFormat.encodings.indices.contains(sender.tag) else { return }
        let encoding = TextFormat.encodings[sender.tag]
        let converted = TextFormat(encoding: encoding, lineBreak: format.lineBreak)
        guard converted.canStore(text) else {
            NSAlert.show(
                "\(TextFormat.name(of: encoding)) cannot store this text",
                details: "Some of its characters have no place in \(TextFormat.name(of: encoding)). Remove them or pick another encoding.",
                in: windowForSheet
            )
            return
        }
        format = converted
        replacedBytes = 0
        updateChangeCount(.changeDone)
        NotificationCenter.default.post(name: Self.formatDidChange, object: self)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(reopenWithEncoding(_:)), #selector(convertToEncoding(_:)):
            guard TextFormat.encodings.indices.contains(item.tag) else { return false }
            (item as? NSMenuItem)?.state = TextFormat.encodings[item.tag] == format.encoding ? .on : .off
            return item.action == #selector(convertToEncoding(_:)) || fileURL != nil
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    nonisolated private func apply(_ decoded: TextFormat.Decoded) {
        text = decoded.text
        format = decoded.format
        replacedBytes = decoded.replacedBytes
    }

    private func reloadWindows() {
        windowControllers.compactMap { $0 as? DocumentWindowController }.forEach { $0.reloadFromDocument() }
    }
}
