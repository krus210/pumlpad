import AppKit

/// A command shown in the menu bar and, for some, in the toolbar. Defined once, so the two
/// cannot drift apart.
@MainActor
struct Command {
    let title: String
    let action: Selector
    var key = ""
    var modifiers: NSEvent.ModifierFlags = .command
    /// SF Symbol for the toolbar.
    var symbol: String?

    /// The item has no target: the action goes to the key window's responder chain.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

@MainActor
enum Commands {
    static let exportPNG = Command(
        title: "Export PNG…", action: #selector(DocumentWindowController.exportPNG(_:)), key: "e", modifiers: [.command, .shift]
    )
    static let exportRetinaPNG = Command(
        title: "Export PNG @2x…", action: #selector(DocumentWindowController.exportRetinaPNG(_:))
    )
    static let exportSVG = Command(
        title: "Export SVG…", action: #selector(DocumentWindowController.exportSVG(_:)), key: "e", modifiers: [.command, .shift, .option]
    )
    static let copyPNG = Command(
        title: "Copy Diagram as PNG", action: #selector(DocumentWindowController.copyPNG(_:)), key: "c", modifiers: [.command, .shift]
    )
    static let copySVG = Command(
        title: "Copy Diagram as SVG", action: #selector(DocumentWindowController.copySVG(_:)), key: "c", modifiers: [.command, .shift, .option]
    )
    /// As listed in File and under the toolbar's Export button; `nil` is a separator.
    static let export: [Command?] = [exportPNG, exportRetinaPNG, exportSVG, nil, copyPNG, copySVG]

    static let zoomOut = Command(
        title: "Zoom Out", action: #selector(DocumentWindowController.zoomOutDiagram(_:)), key: "-", symbol: "minus.magnifyingglass"
    )
    static let actualSize = Command(
        title: "Actual Size", action: #selector(DocumentWindowController.zoomDiagramToActualSize(_:)), key: "0", symbol: "1.magnifyingglass"
    )
    static let zoomToFit = Command(
        title: "Zoom to Fit", action: #selector(DocumentWindowController.zoomDiagramToFit(_:)), key: "9",
        symbol: "arrow.up.left.and.down.right.magnifyingglass"
    )
    static let zoomIn = Command(
        title: "Zoom In", action: #selector(DocumentWindowController.zoomInDiagram(_:)), key: "=", symbol: "plus.magnifyingglass"
    )
    /// Left to right, as in the toolbar.
    static let zoom = [zoomOut, actualSize, zoomToFit, zoomIn]

    static let toggleEditor = Command(
        title: "Hide Editor", action: #selector(DocumentWindowController.toggleEditor(_:)), key: "e", modifiers: [.command, .control],
        symbol: "sidebar.left"
    )
    static let biggerFont = Command(
        title: "Bigger Editor Font", action: #selector(AppDelegate.increaseEditorFont(_:)), key: "=", modifiers: [.command, .option]
    )
    static let smallerFont = Command(
        title: "Smaller Editor Font", action: #selector(AppDelegate.decreaseEditorFont(_:)), key: "-", modifiers: [.command, .option]
    )
    static let darkDiagrams = Command(
        title: "Dark Diagrams", action: #selector(AppDelegate.toggleDarkDiagrams(_:)), symbol: "moon"
    )
    static let localFiles = Command(
        title: "Allow Local Files in This Folder…", action: #selector(DocumentWindowController.toggleLocalFileAccess(_:))
    )
}
