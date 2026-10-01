import AppKit

/// The document window's toolbar. Items carry no target: their actions go to the key window's
/// responder chain, like the menu items of the same `Commands`.
@MainActor
final class DocumentToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "PumlpadToolbar")
    static let exportToolTip = "Export or copy the diagram"

    private enum Item {
        static let editor = NSToolbarItem.Identifier("editor")
        static let zoom = NSToolbarItem.Identifier("zoom")
        static let darkDiagrams = NSToolbarItem.Identifier("darkDiagrams")
        static let export = NSToolbarItem.Identifier("export")
    }

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
    }

    /// The menu under the Export button.
    var exportMenu: NSMenu? {
        (toolbar.items.first { $0.itemIdentifier == Item.export } as? NSMenuToolbarItem)?.menu
    }

    func updateDarkDiagramsItem() {
        toolbar.items.first { $0.itemIdentifier == Item.darkDiagrams }?.image = darkDiagramsImage
    }

    private var darkDiagramsImage: NSImage? {
        symbol(Services.shared.darkDiagrams ? "moon.fill" : "moon", Commands.darkDiagrams.title)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.editor, .flexibleSpace, Item.zoom, Item.darkDiagrams, Item.export]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Item.editor:
            return button(identifier, label: "Editor", image: symbol(Commands.toggleEditor.symbol, "Show or hide the editor"),
                          action: Commands.toggleEditor.action)
        case Item.zoom:
            let group = NSToolbarItemGroup(
                itemIdentifier: identifier,
                images: Commands.zoom.compactMap { symbol($0.symbol, $0.title) },
                selectionMode: .momentary,
                labels: Commands.zoom.map(\.title),
                target: self,
                action: #selector(zoom(_:))
            )
            group.label = "Zoom"
            return group
        case Item.darkDiagrams:
            return button(identifier, label: "Dark", image: darkDiagramsImage, action: Commands.darkDiagrams.action)
        case Item.export:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.image = symbol("square.and.arrow.up", "Export")
            item.label = "Export"
            item.toolTip = Self.exportToolTip
            let menu = NSMenu()
            MainMenu.add(Commands.export, to: menu)
            item.menu = menu
            return item
        default:
            return nil
        }
    }

    @objc private func zoom(_ sender: NSToolbarItemGroup) {
        guard Commands.zoom.indices.contains(sender.selectedIndex) else { return }
        NSApp.sendAction(Commands.zoom[sender.selectedIndex].action, to: nil, from: sender)
    }

    private func button(_ identifier: NSToolbarItem.Identifier, label: String, image: NSImage?, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = image?.accessibilityDescription
        item.image = image
        item.action = action
        item.isBordered = true
        return item
    }

    private func symbol(_ name: String?, _ description: String) -> NSImage? {
        name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: description) }
    }
}
