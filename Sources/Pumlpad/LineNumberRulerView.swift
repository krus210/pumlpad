import AppKit
import PumlCore

/// Line numbers next to the editor; the line with a PlantUML error is shown in red.
@MainActor
final class LineNumberRulerView: NSRulerView {
    var errorLine: Line? {
        didSet { needsDisplay = true }
    }

    /// The editor's font size; numbers are drawn slightly smaller.
    var fontSize: CGFloat = 13 {
        didSet { needsDisplay = true }
    }

    /// Line starts of the editor's text, kept current by the editor.
    var lines: (() -> LineIndex?)?

    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 30
        // Since macOS 14 views may draw outside their bounds, and the ruler sits above the text.
        clipsToBounds = true
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: clipView
            )
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func redraw() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let lines = lines?() else { return }
        let digitWidth = fontSize * 0.55
        let thickness = CGFloat(max(2, String(lines.lineCount).count)) * digitWidth + 16
        if abs(ruleThickness - thickness) > 0.5 { ruleThickness = thickness }

        let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let inset = textView.textContainerInset.height
        var line = lines.line(at: characters.location)
        while let range = lines.range(of: line), range.length > 0, range.location <= NSMaxRange(characters) {
            let fragment = layoutManager.lineFragmentRect(
                forGlyphAt: layoutManager.glyphIndexForCharacter(at: range.location), effectiveRange: nil
            )
            drawNumber(line, top: fragment.minY + inset, height: fragment.height, textView: textView)
            line = Line(index: line.index + 1)
        }
        // The empty line after a trailing line break has no characters, only the extra fragment.
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty {
            drawNumber(line, top: extra.minY + inset, height: extra.height, textView: textView)
        }
    }

    private func drawNumber(_ line: Line, top: CGFloat, height: CGFloat, textView: NSTextView) {
        let isError = line == errorLine
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize * 0.8, weight: isError ? .bold : .regular),
            .foregroundColor: isError ? NSColor.systemRed : NSColor.tertiaryLabelColor,
        ]
        let label = "\(line.number)" as NSString
        let size = label.size(withAttributes: attributes)
        let y = convert(NSPoint(x: 0, y: top), from: textView).y
        label.draw(
            at: NSPoint(x: ruleThickness - size.width - 8, y: y + (height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
