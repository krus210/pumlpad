import AppKit
import PumlCore

/// Plain-text PlantUML editor: NSTextView with line numbers, highlighting and keyword completion.
@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    var onTextChange: ((String) -> Void)?
    var onCaretLineChange: ((Line) -> Void)?

    /// Document line PlantUML reported an error on.
    var errorLine: Line? {
        didSet { if errorLine != oldValue { updateErrorMarker() } }
    }

    var text: String { textView.string }
    var caretLine: Line { lines.line(at: textView.selectedRange().location) }

    private var textView: EditorTextView!
    /// Owns the TextKit 1 objects when they are built by hand; the text view does not retain it.
    private var textStorage: NSTextStorage!
    private var ruler: LineNumberRulerView!
    private let highlighter = SyntaxHighlighter()
    private var lastCaretLine = Line(index: 0)
    /// Characters changed since the last recolouring and the change in length; `nil` means everything.
    private var editedRange: NSRange?
    private var editedDelta = 0
    private var editCount = 0
    /// Line starts of the text, rebuilt after each edit on first use.
    private var cachedLines: LineIndex?
    private lazy var completionWords: [String] = {
        let words = Keywords.types + Keywords.keywords + Keywords.preprocessor + Keywords.skinParameters + Keywords.colors
        return Array(Set(words)).sorted { $0.lowercased() < $1.lowercased() }
    }()

    private var lines: LineIndex {
        if let cachedLines { return cachedLines }
        let index = LineIndex(textView.string as NSString)
        cachedLines = index
        return index
    }

    static func font(size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 700))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // TextKit 1, built explicitly: the line-number ruler and temporary attributes need NSLayoutManager.
        let size = scrollView.contentSize
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = EditorTextView(frame: NSRect(origin: .zero, size: size), textContainer: container)
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        layoutManager.allowsNonContiguousLayout = true

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.delegate = self
        storage.delegate = self

        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        ruler.lines = { [weak self] in self?.lines }
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        self.textView = textView
        self.textStorage = storage
        self.ruler = ruler
        view = scrollView
        applyFontSize()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyFontSize), name: Services.editorFontDidChange, object: nil
        )
    }

    func setText(_ text: String) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        editedRange = nil
        refreshDecorations()
    }

    func revealLine(_ line: Line) {
        guard let range = lines.range(of: line) else { return }
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    // MARK: Demo recording (DemoPlayer)

    func placeCaret(atEndOfLine line: Line) {
        guard let range = lines.range(of: line) else { return }
        var contentsEnd = 0
        (textView.string as NSString).getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: range)
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: contentsEnd, length: 0))
        textView.scrollRangeToVisible(NSRange(location: contentsEnd, length: 0))
    }

    /// Goes through the same path as typing, so undo, highlighting and rendering react as usual.
    func typeForDemo(_ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    /// Opens the completion list and picks its first item after `seconds`. The list runs its own
    /// event loop until a key arrives, where only timers of the common modes fire: one presses Return.
    func showCompletions(acceptingFirstAfter seconds: Double) {
        guard let window = view.window else { return }
        nonisolated(unsafe) let returnKey = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        )
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { if let returnKey { NSApp.postEvent(returnKey, atStart: false) } }
        }
        RunLoop.main.add(timer, forMode: .common)
        textView.complete(nil)
    }

    @objc private func applyFontSize() {
        let font = Self.font(size: Services.shared.editorFontSize)
        textView.font = font
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        ruler.fontSize = font.pointSize
    }

    // MARK: NSTextStorageDelegate

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            cachedLines = nil
            // Several edits before one recolouring (a replace-all, say) recolour everything.
            editCount += 1
            self.editedRange = editCount == 1 ? editedRange : nil
            editedDelta = delta
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        refreshDecorations()
        onTextChange?(textView.string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let line = caretLine
        guard line != lastCaretLine else { return }
        lastCaretLine = line
        onCaretLineChange?(line)
    }

    /// Return keeps the indentation of the current line.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let string = textView.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        let indentation = string.substring(with: lineRange).prefix { $0 == " " || $0 == "\t" }
        textView.insertText("\n" + indentation, replacementRange: textView.selectedRange())
        return true
    }

    /// ⌥Esc (or F5) completes PlantUML keywords; plain Esc is Cancel in AppKit.
    func textView(
        _ textView: NSTextView,
        completions words: [String],
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
        let string = textView.string as NSString
        var range = charRange
        // Keep the `!` of `!include` or the `@` of `@startuml` in the word being completed.
        if range.location > 0, "!@".contains(string.substring(with: NSRange(location: range.location - 1, length: 1))) {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        let partial = string.substring(with: range).lowercased()
        guard !partial.isEmpty else { return [] }
        let prefixLength = range.length - charRange.length
        return completionWords
            .filter { $0.lowercased().hasPrefix(partial) && $0.count > partial.count }
            .map { String($0.dropFirst(prefixLength)) }
    }

    // MARK: Decorations

    private func refreshDecorations() {
        guard let layoutManager = textView.layoutManager else { return }
        highlighter.highlight(layoutManager, text: textView.string as NSString, edited: editedRange, delta: editedDelta)
        editedRange = nil
        editCount = 0
        updateErrorMarker()
        ruler.needsDisplay = true
    }

    /// The marker follows the line number until the next render says where the error is.
    private func updateErrorMarker() {
        ruler.errorLine = errorLine
        textView.errorRange = errorLine.flatMap { lines.range(of: $0) }
    }
}

/// The editor's text view; it paints a band behind the line with the error.
private final class EditorTextView: NSTextView {
    var errorRange: NSRange? {
        didSet { if errorRange != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let errorRange, let layoutManager, NSMaxRange(errorRange) <= (string as NSString).length else { return }
        var band = NSRect.null
        if errorRange.length == 0 {
            // The empty line after a trailing line break has only the extra fragment.
            band = layoutManager.extraLineFragmentRect
        } else {
            let glyphs = layoutManager.glyphRange(forCharacterRange: errorRange, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
                band = band.union(fragment)
            }
        }
        guard !band.isNull, !band.isEmpty else { return }
        band = NSRect(x: 0, y: band.minY + textContainerOrigin.y, width: bounds.width, height: band.height)
        NSColor.systemRed.withAlphaComponent(0.16).setFill()
        band.intersection(rect).fill()
    }
}
