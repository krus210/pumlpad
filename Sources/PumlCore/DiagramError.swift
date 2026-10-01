import Foundation

/// A PlantUML syntax error, mapped to a document line.
public struct DiagramError: Equatable, Sendable {
    /// Document line of the error. For an error inside an included file, the line of the
    /// diagram's `!include` that brings the file in.
    public let line: Line
    public let message: String
    /// The included file the error is in, as written in its `!include`; `nil` when unknown.
    public let includedFile: String?
    /// The line PlantUML reported in the included file.
    public let includedFileLine: Line?

    public init(line: Line, message: String, includedFile: String? = nil, includedFileLine: Line? = nil) {
        self.line = line
        self.message = message
        self.includedFile = includedFile
        self.includedFileLine = includedFileLine
    }

    /// Whether the error is inside an included file rather than in the diagram itself.
    public var isInIncludedFile: Bool {
        includedFileLine != nil
    }

    /// Parses a `-stdrpt:2` report, `<source>:<line>:error:<message>`. The source is `string`
    /// for the diagram itself and names the file otherwise (see `IncludeTree`); the line is
    /// 1-based and counted in that source. `includes` finds included files; without it an error
    /// in one points at the diagram's first local `!include`.
    static func parse(report: String, block: DiagramBlock, includes: IncludeTree? = nil) -> DiagramError {
        let reportLine = report.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard let match = reportLine.firstMatch(of: /^(.*?):(\d+):error:(.*)$/),
              let number = Int(match.2) else {
            let text = reportLine.trimmingCharacters(in: .whitespaces)
            return DiagramError(line: block.documentLine(for: Line(index: 0)), message: text.isEmpty ? "Syntax error" : text)
        }
        let source = String(match.1)
        let message = String(match.3).trimmingCharacters(in: .whitespaces)
        if source == "string" {
            return DiagramError(line: block.documentLine(for: Line(number: number)), message: message)
        }
        let reportedLine = Line(number: number)
        let origin = (includes ?? IncludeTree(folder: URL(fileURLWithPath: "/"), read: { _ in nil }))
            .origin(of: source, line: reportedLine, in: block.source)
        let includeLine = origin?.include.line ?? IncludeTree.includes(in: block.source).first?.line ?? Line(index: 0)
        return DiagramError(
            line: block.documentLine(for: includeLine),
            message: message,
            includedFile: origin?.file ?? (IncludeTree.isOwnDiagramName(source) ? nil : source),
            includedFileLine: reportedLine
        )
    }
}
