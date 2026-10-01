import AppKit
import PumlCore
import UniformTypeIdentifiers

/// What the exporter needs from a document window.
@MainActor
protocol DiagramExportSource: AnyObject {
    var window: NSWindow? { get }
    var exportBlock: DiagramBlock? { get }
    var exportFileName: String { get }
    var exportFolder: URL? { get }
    func renderOptions(format: OutputFormat) -> RenderOptions
    func report(_ state: StatusBarView.State)
}

/// Saves the diagram under the caret to a file or copies it to the clipboard. Exports are
/// rendered afresh by PlantUML; PNG uses its own PlantUML process.
@MainActor
final class DiagramExporter {
    private weak var source: DiagramExportSource?

    init(source: DiagramExportSource) {
        self.source = source
    }

    func export(_ format: OutputFormat, scale: ExportScale) {
        guard let source, let window = source.window, let options = options(format) else { return }
        // Start the PNG process while the user picks a file name.
        Services.shared.renderer?.warmUp(options: options)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .png ? .png : .svg]
        panel.nameFieldStringValue = "\(source.exportFileName)\(scale == .retina ? "@2x" : "").\(format.rawValue)"
        panel.directoryURL = source.exportFolder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.write(format, scale: scale, to: url)
        }
    }

    /// Renders the diagram under the caret and saves it to `url`.
    func write(_ format: OutputFormat, scale: ExportScale, to url: URL) {
        guard let options = options(format) else { return }
        Task { @MainActor [weak self] in
            guard let self, let data = await self.render(options, scale: scale) else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.source?.report(.info("Exported \(url.lastPathComponent)"))
            } catch {
                NSAlert.show("Could not save \(url.lastPathComponent)", details: error.localizedDescription, in: self.source?.window)
            }
        }
    }

    func copy(_ format: OutputFormat) {
        guard let options = options(format) else { return }
        Task {
            guard let data = await render(options, scale: .standard) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch format {
            case .png:
                pasteboard.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
            case .svg:
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
                pasteboard.setString(String(decoding: data, as: UTF8.self), forType: .string)
            }
            source?.report(.info("Copied \(format.rawValue.uppercased()) to the clipboard"))
        }
    }

    private func options(_ format: OutputFormat) -> RenderOptions? {
        guard Services.shared.renderer != nil, let options = source?.renderOptions(format: format) else {
            NSSound.beep()
            return nil
        }
        return options
    }

    private func render(_ options: RenderOptions, scale: ExportScale) async -> Data? {
        guard let renderer = Services.shared.renderer, let block = source?.exportBlock else {
            NSSound.beep()
            return nil
        }
        source?.report(.info("Rendering \(options.format.rawValue.uppercased())…"))
        do {
            let result = try await renderer.render(block.scaled(scale), options: options)
            switch result.outcome {
            case .image(let data):
                return data
            case .error(let error):
                source?.report(.error(error, hint: nil))
                NSAlert.show("The diagram has an error on line \(error.line.number)", details: error.message, in: source?.window)
                return nil
            }
        } catch {
            NSAlert.show("Export failed", details: String(describing: error), in: source?.window)
            return nil
        }
    }
}
