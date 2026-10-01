import AppKit
import PumlCore

/// Bottom bar: render time or the error (click to jump to its line), the file's encoding and
/// line breaks, and the preview zoom.
@MainActor
final class StatusBarView: NSView {
    enum State {
        case idle
        case rendering
        case rendered(Duration)
        /// `hint` says what the user can do about the error.
        case error(DiagramError, hint: String?)
        case failure(String)
        case info(String)
        /// The diagram rendered, but something about it needs the user's attention.
        case warning(String)
    }

    var onErrorClick: (() -> Void)?

    var zoom: Double = 1 {
        didSet { zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%" }
    }

    /// Encoding and line breaks, e.g. "UTF-8 · LF".
    var documentInfo = "" {
        didSet { infoLabel.stringValue = documentInfo }
    }

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private var showsError = false

    /// One wording for errors, in the status bar and in the preview.
    static func describe(_ error: DiagramError) -> String {
        var text = "Line \(error.line.number)"
        if let fileLine = error.includedFileLine {
            text += " (\(error.includedFile ?? "included file"), line \(fileLine.number))"
        }
        return "\(text): \(error.message)"
    }

    init() {
        super.init(frame: .zero)
        for field in [label, infoLabel, zoomLabel] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zoomLabel.alignment = .right
        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)

        let stack = NSStackView(views: [icon, label, NSView(), infoLabel, zoomLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.setCustomSpacing(14, after: infoLabel)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ state: State) {
        showsError = false
        toolTip = nil
        switch state {
        case .idle:
            set(symbol: nil, text: "", color: .secondaryLabelColor)
        case .rendering:
            set(symbol: "hourglass", text: "Rendering…", color: .secondaryLabelColor)
        case .rendered(let duration):
            let milliseconds = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
            set(symbol: "checkmark.circle.fill", text: "Rendered in \(milliseconds) ms", color: .secondaryLabelColor, tint: .systemGreen)
        case .error(let error, let hint):
            showsError = true
            let text = Self.describe(error) + (hint.map { " — \($0)" } ?? "")
            set(symbol: "exclamationmark.triangle.fill", text: text, color: .systemRed, tint: .systemRed)
            toolTip = "\(text)\nClick to jump to line \(error.line.number)"
        case .failure(let message):
            set(symbol: "xmark.octagon.fill", text: message, color: .systemRed, tint: .systemRed)
        case .info(let message):
            set(symbol: "info.circle", text: message, color: .secondaryLabelColor)
        case .warning(let message):
            set(symbol: "exclamationmark.triangle", text: message, color: .labelColor, tint: .systemOrange)
            toolTip = message
        }
    }

    private func set(symbol: String?, text: String, color: NSColor, tint: NSColor? = nil) {
        icon.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        icon.contentTintColor = tint ?? color
        label.stringValue = text
        label.textColor = color
    }

    @objc private func clicked() {
        if showsError { onErrorClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
