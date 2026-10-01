import AppKit
import PumlCore

/// The menu bar, built in code because the app has no nib.
@MainActor
enum MainMenu {
    private static let recentDocuments = RecentDocumentsMenu()
    private static let trustedFolders = TrustedFoldersMenu()

    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(fileMenu()))
        menu.addItem(submenu(editMenu()))
        menu.addItem(submenu(viewMenu()))
        menu.addItem(submenu(diagramMenu()))
        let window = windowMenu()
        menu.addItem(submenu(window))
        // AppKit adds the window list and tab commands to this menu.
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        menu.addItem(submenu(help))
        NSApp.helpMenu = help
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Pumlpad")
        menu.addItem(item("About Pumlpad", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide Pumlpad", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Pumlpad", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = recentDocuments
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save…", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        // Shown in place of Duplicate while Option is held, as in Apple's apps.
        let saveAs = item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift, .option])
        saveAs.isAlternate = true
        menu.addItem(saveAs)
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(submenu(encodingMenu("Reopen with Encoding", #selector(PumlDocument.reopenWithEncoding(_:)))))
        menu.addItem(submenu(encodingMenu("Convert to Encoding", #selector(PumlDocument.convertToEncoding(_:)))))
        menu.addItem(.separator())
        add(Commands.export, to: menu)
        return menu
    }

    /// One item per encoding; the tag is its index in `TextFormat.encodings`.
    private static func encodingMenu(_ title: String, _ action: Selector) -> NSMenu {
        let menu = NSMenu(title: title)
        for (index, encoding) in TextFormat.encodings.enumerated() {
            menu.addItem(item(TextFormat.name(of: encoding), action, tag: index))
        }
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        let find = NSMenu(title: "Find")
        let finderAction = #selector(NSTextView.performTextFinderAction(_:))
        find.addItem(item("Find…", finderAction, "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        find.addItem(item("Find and Replace…", finderAction, "f", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue))
        find.addItem(item("Find Next", finderAction, "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        find.addItem(item("Find Previous", finderAction, "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        find.addItem(item("Use Selection for Find", finderAction, "e", tag: NSTextFinder.Action.setSearchString.rawValue))
        find.addItem(item("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenu(find))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(Commands.toggleEditor.menuItem())
        menu.addItem(.separator())
        for command in Commands.zoom.reversed() { menu.addItem(command.menuItem()) }
        menu.addItem(.separator())
        menu.addItem(Commands.biggerFont.menuItem())
        menu.addItem(Commands.smallerFont.menuItem())
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func diagramMenu() -> NSMenu {
        let menu = NSMenu(title: "Diagram")
        menu.addItem(Commands.darkDiagrams.menuItem())
        menu.addItem(.separator())
        menu.addItem(Commands.localFiles.menuItem())
        let trusted = NSMenu(title: "Trusted Folders")
        trusted.delegate = trustedFolders
        menu.addItem(submenu(trusted))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    /// Adds `commands`; `nil` becomes a separator.
    static func add(_ commands: [Command?], to menu: NSMenu) {
        for command in commands {
            menu.addItem(command?.menuItem() ?? .separator())
        }
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }
}

/// Fills File › Open Recent from `NSDocumentController`, which only does it for nib-based menus.
@MainActor
private final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: ""))
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            // A moved or deleted file must say so instead of doing nothing.
            guard let error, (error as? CocoaError)?.code != .userCancelled else { return }
            DispatchQueue.main.async { NSApp.presentError(error) }
        }
    }
}

/// Diagram › Trusted Folders: the folders whose diagrams may read files, each with a way to
/// stop trusting it, and one to stop trusting them all.
@MainActor
private final class TrustedFoldersMenu: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let folders = Services.shared.trustedFolders
        guard !folders.isEmpty else {
            // An item without an action is shown disabled.
            menu.addItem(NSMenuItem(title: "No Trusted Folders", action: nil, keyEquivalent: ""))
            return
        }
        for folder in folders {
            let item = NSMenuItem(title: (folder.path as NSString).abbreviatingWithTildeInPath, action: nil, keyEquivalent: "")
            let actions = NSMenu()
            actions.addItem(action("Show in Finder", #selector(showInFinder(_:)), folder))
            actions.addItem(action("Stop Trusting", #selector(stopTrusting(_:)), folder))
            item.submenu = actions
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(action("Stop Trusting All Folders…", #selector(stopTrustingAll(_:)), nil))
    }

    private func action(_ title: String, _ selector: Selector, _ folder: URL?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = folder
        return item
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    @objc private func stopTrusting(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        Services.shared.setAllowsLocalFiles(false, in: folder)
    }

    @objc private func stopTrustingAll(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Stop trusting all folders?"
        alert.informativeText = "Diagrams will no longer read local files until you allow it again, folder by folder."
        alert.addButton(withTitle: "Stop Trusting")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Services.shared.stopTrustingAllFolders()
    }
}
