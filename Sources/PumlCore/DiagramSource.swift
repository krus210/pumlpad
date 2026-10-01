/// One `@startXXX … @endXXX` diagram taken from a document, ready for PlantUML's `-pipe` mode.
public struct DiagramBlock: Equatable, Sendable {
    /// Text sent to PlantUML: the `@start…` line, the diagram and an `@end…` line that `-pipe` accepts.
    public let source: String
    /// Document line of the `@start…` line; `nil` when the document had none and was wrapped.
    public let startLine: Line?
    /// Diagram kind from the start tag, in lower case: `uml`, `mindmap`, `json`…
    public let kind: String
    /// Document line index of the first line of `source`: -1 for the `@startuml` added around a bare document.
    private let lineOffset: Int

    public init(source: String, startLine: Line?, kind: String) {
        self.init(source: source, startLine: startLine, kind: kind, lineOffset: startLine?.index ?? -1)
    }

    private init(source: String, startLine: Line?, kind: String, lineOffset: Int) {
        self.source = source
        self.startLine = startLine
        self.kind = kind
        self.lineOffset = lineOffset
    }

    /// Maps a line of `source` to a document line.
    public func documentLine(for diagramLine: Line) -> Line {
        Line(index: max(0, lineOffset + diagramLine.index))
    }

    /// The same diagram drawn larger, for PNG export. Most diagrams take `skinparam dpi`, which
    /// still combines with a `scale` of their own; JSON, YAML and math ignore it and take `scale`;
    /// ditaa takes an option on its start line. The added line goes right after `@start…`, so a
    /// setting in the diagram itself still wins.
    public func scaled(_ scale: ExportScale) -> DiagramBlock {
        guard scale != .standard, let firstBreak = source.firstIndex(of: "\n") else { return self }
        let factor = scale.dpi / ExportScale.standard.dpi
        let inserted: String
        switch kind {
        case "ditaa":
            let start = Self.ditaaStart(source[..<firstBreak], factor: factor)
            return DiagramBlock(source: start + source[firstBreak...], startLine: startLine, kind: kind, lineOffset: lineOffset)
        case "json", "yaml", "math":
            inserted = "scale \(factor)"
        default:
            inserted = "skinparam dpi \(scale.dpi)"
        }
        let scaled = source[..<firstBreak] + "\n\(inserted)" + source[firstBreak...]
        return DiagramBlock(source: String(scaled), startLine: startLine, kind: kind, lineOffset: lineOffset - 1)
    }

    /// `@startditaa(scale=2)`: ditaa has neither skinparams nor a `scale` command.
    private static func ditaaStart(_ line: Substring, factor: Int) -> String {
        let tag = "@startditaa"
        guard line.hasPrefix(tag) else { return String(line) }
        let rest = line.dropFirst(tag.count)
        guard rest.hasPrefix("(") else { return "\(tag)(scale=\(factor))\(rest)" }
        return rest.contains("scale") ? String(line) : "\(tag)(scale=\(factor), \(rest.dropFirst())"
    }
}

/// PNG resolution: PlantUML draws at 96 dpi; Retina screens need twice the pixels.
public enum ExportScale: Sendable {
    case standard, retina

    public var dpi: Int {
        switch self {
        case .standard: 96
        case .retina: 192
        }
    }
}

public enum DiagramSource {
    /// Picks the diagram to render from a document.
    ///
    /// `-pipe` reads one diagram per `@end…` line and treats whatever follows as the next diagram,
    /// so exactly one closed block is returned: text outside it is dropped and a missing `@end…`
    /// is added. With several blocks, the last one starting at or before `caretLine` wins.
    ///
    /// Start and end lines are found as PlantUML finds them in files: `@start…` and `@end…` in
    /// lower case, indented or not. `-pipe` is stricter and, for a diagram it cannot close, waits
    /// for more input until the render times out, so the block goes out in its form: the start
    /// line unindented, the end line one that `-pipe` accepts (see `pipeEnd(forStart:)`).
    ///
    /// Lines end at "\n", "\r\n" or "\r", as in PlantUML. The scan works on UTF-8 bytes: it runs on
    /// every keystroke and caret move, and splitting into Characters took ~0.4 s on 20 000 lines.
    public static func block(in document: String, caretLine: Line? = nil) -> DiagramBlock? {
        var document = document
        // Text from NSTextView is bridged UTF-16; one conversion makes the bytes addressable.
        document.makeContiguousUTF8()
        return document.utf8.withContiguousStorageIfAvailable { block(in: $0, caretLine: caretLine) } ?? nil
    }

    private static let startPrefix = Array("@start".utf8)
    private static let endPrefix = Array("@end".utf8)
    /// `-pipe` takes a line starting with this as an instruction to switch the output format.
    private static let formatCommand = Array("@@@format".utf8)

    private static func block(in bytes: UnsafeBufferPointer<UInt8>, caretLine: Line?) -> DiagramBlock? {
        let lines = lineRanges(in: bytes)
        var blocks: [(start: Int, end: Int?, kind: String)] = []
        var index = 0
        while index < lines.count {
            guard let kind = tag(startPrefix, bytes, lines[index]) else {
                index += 1
                continue
            }
            var end: Int?
            var next = index + 1
            while next < lines.count {
                if tag(endPrefix, bytes, lines[next]) != nil {
                    end = next
                    next += 1
                    break
                }
                if tag(startPrefix, bytes, lines[next]) != nil { break }
                next += 1
            }
            blocks.append((index, end, kind))
            index = next
        }

        guard let first = blocks.first else {
            guard bytes.contains(where: { !isBlank($0) }) else { return nil }
            let body = joined(lines, 0..<lines.count, bytes)
            return DiagramBlock(source: "@startuml\n\(body)\n@enduml", startLine: nil, kind: "uml")
        }

        let chosen = caretLine.flatMap { caret in blocks.last { $0.start <= caret.index } } ?? first
        var lastBodyLine = chosen.end.map { $0 - 1 }
            ?? blocks.first(where: { $0.start > chosen.start }).map { $0.start - 1 }
            ?? lines.count - 1
        if chosen.end == nil {
            while lastBodyLine > chosen.start, bytes[lines[lastBodyLine]].allSatisfy(isBlank) { lastBodyLine -= 1 }
        }

        let start = unindented(bytes, lines[chosen.start])
        let pipeEnd = pipeEnd(forStart: start)
        // The end line as written when -pipe takes it; otherwise, or when missing, the one it waits for.
        let end = chosen.end.map { unindented(bytes, lines[$0]) }.flatMap { $0.hasPrefix(pipeEnd) ? $0 : nil } ?? pipeEnd
        var source = start
        if lastBodyLine > chosen.start {
            source += "\n" + joined(lines, (chosen.start + 1)..<(lastBodyLine + 1), bytes)
        }
        source += "\n" + end
        return DiagramBlock(source: source, startLine: Line(index: chosen.start), kind: chosen.kind)
    }

    /// The end line `-pipe` waits for after `start`: `@end` and the kind when the start line is
    /// the bare tag (`@startuml` → `@enduml`, `@startUML` → `@endUML`), any `@end…` otherwise.
    private static func pipeEnd(forStart start: String) -> String {
        let kind = start.dropFirst("@start".count)
        return kind.allSatisfy { $0.isASCII && $0.isLetter } ? "@end\(kind)" : "@end"
    }

    /// Byte ranges of the lines, without their line breaks; a trailing break leaves an empty last line.
    private static func lineRanges(in bytes: UnsafeBufferPointer<UInt8>) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 0x0A:
                lines.append(start..<index)
                start = index + 1
            case 0x0D:
                lines.append(start..<index)
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 1 }
                start = index + 1
            default:
                break
            }
            index += 1
        }
        lines.append(start..<bytes.count)
        return lines
    }

    /// The diagram kind, in lower case and possibly empty, when the line opens with `prefix`
    /// (`@start` or `@end`) after optional indentation. Like PlantUML, the tag itself is case-sensitive.
    private static func tag(_ prefix: [UInt8], _ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> String? {
        var index = indentationEnd(bytes, line)
        guard line.upperBound - index >= prefix.count else { return nil }
        for offset in prefix.indices where bytes[index + offset] != prefix[offset] { return nil }
        index += prefix.count
        var kind: [UInt8] = []
        while index < line.upperBound, isLetter(bytes[index]) {
            kind.append(lowercased(bytes[index]))
            index += 1
        }
        return String(decoding: kind, as: UTF8.self)
    }

    private static func unindented(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> String {
        String(decoding: bytes[indentationEnd(bytes, line)..<line.upperBound], as: UTF8.self)
    }

    private static func indentationEnd(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> Int {
        var index = line.lowerBound
        while index < line.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        return index
    }

    /// Joins lines with "\n". A line that `-pipe` would take as `@@@format` is indented, so the
    /// diagram cannot switch the process to another output format; PlantUML then reports it.
    private static func joined(_ lines: [Range<Int>], _ range: Range<Int>, _ bytes: UnsafeBufferPointer<UInt8>) -> String {
        var result: [UInt8] = []
        result.reserveCapacity(lines[range].reduce(0) { $0 + $1.count + 1 })
        for index in range {
            if index > range.lowerBound { result.append(0x0A) }
            let line = bytes[lines[index]]
            if line.starts(with: formatCommand) { result.append(0x20) }
            result.append(contentsOf: line)
        }
        return String(decoding: result, as: UTF8.self)
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
    }
}
