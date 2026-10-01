import Foundation

/// The local files a diagram includes, read to explain what PlantUML reports about them.
///
/// For an error inside an included file PlantUML gives the line in that file and names the file
/// as written in the innermost `!include` (`b.iuml` for `!include b.iuml` inside `parts/a.iuml`),
/// or `desc…` when the file has an `@startuml` of its own. Following the includes from the
/// diagram tells which of its own `!include` lines leads there.
struct IncludeTree: Sendable {
    /// An `!include` directive: its line in the text it is in, and the path as written.
    struct Include: Equatable {
        let line: Line
        let path: String
    }

    /// Where the diagram's relative paths start: the document's folder.
    let folder: URL
    /// Reads a file, or returns `nil`. Tests replace it.
    var read: @Sendable (URL) -> Data? = IncludeTree.readSmallFile

    private static let maxDepth = 8
    private static let maxFiles = 64

    /// The `!include` of `source` that brings in the file PlantUML reported as `reportedFile`,
    /// and that file's path as written. PlantUML stops at the first error, so the first match
    /// in include order is taken.
    func origin(of reportedFile: String, line: Line, in source: String) -> (include: Include, file: String)? {
        let includes = Self.includes(in: source)
        if let direct = includes.first(where: { $0.path == reportedFile }) { return (direct, reportedFile) }
        let ownDiagram = Self.isOwnDiagramName(reportedFile)
        for include in includes {
            let file = firstFile(from: include) { text, path in
                // A `desc…` file is the one with an `@start` line and diagram text at the reported line.
                ownDiagram ? Self.hasOwnDiagram(text, withContentAt: line) : path == reportedFile
            }
            if let file { return (include, file) }
        }
        // Files that cannot be read: an include of the same file name, compared whole.
        let name = (reportedFile as NSString).lastPathComponent
        return includes.first { ($0.path as NSString).lastPathComponent == name }.map { ($0, reportedFile) }
    }

    /// Included files, as written, whose bytes are not UTF-8. `-pipe` reads included files as
    /// UTF-8 whatever `-charset` says, so their non-ASCII text comes out as "�".
    func filesNotInUTF8(in source: String) -> [String] {
        var found: [String] = []
        for include in Self.includes(in: source) {
            _ = firstFile(from: include) { _, path in false } visiting: { data, path in
                if String(data: data, encoding: .utf8) == nil, !found.contains(path) { found.append(path) }
            }
        }
        return found
    }

    /// Local includes of `text`, in order: `!include`, `!include_once`, `!include_many` and
    /// `!includesub`, without a `!block` suffix. Not the standard library (`<C4/C4>`) or URLs,
    /// which hold no user files.
    static func includes(in text: String) -> [Include] {
        var result: [Include] = []
        for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let directive = line.drop { $0 == " " || $0 == "\t" }
            guard directive.lowercased().hasPrefix("!include") else { continue }
            let afterName = directive.dropFirst("!include".count).drop { $0.isLetter || $0 == "_" }
            let variant = directive.dropFirst("!include".count).prefix { $0.isLetter || $0 == "_" }.lowercased()
            guard ["", "_once", "_many", "sub"].contains(variant), afterName.first?.isWhitespace == true else { continue }
            var path = afterName.trimmingCharacters(in: .whitespaces)
            if path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") { path = String(path.dropFirst().dropLast()) }
            if let block = path.firstIndex(of: "!") { path = String(path[..<block]) }
            guard !path.isEmpty, !path.hasPrefix("<"), !path.contains("://") else { continue }
            result.append(Include(line: Line(index: index), path: path))
        }
        return result
    }

    /// PlantUML's name for a file with its own `@startuml`: `desc` and a number.
    static func isOwnDiagramName(_ name: String) -> Bool {
        name.hasPrefix("desc") && name.count > 4 && name.dropFirst(4).allSatisfy(\.isASCII) && name.dropFirst(4).allSatisfy(\.isNumber)
    }

    /// Whether `text` has an `@start` line and diagram text (not blank, a tag or a comment) at `line`.
    private static func hasOwnDiagram(_ text: String, withContentAt line: Line) -> Bool {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.drop { $0 == " " || $0 == "\t" } }
        guard lines.contains(where: { $0.hasPrefix("@start") }), lines.indices.contains(line.index) else { return false }
        let content = lines[line.index]
        return !content.isEmpty && !content.hasPrefix("@start") && !content.hasPrefix("@end") && !content.hasPrefix("'")
    }

    /// Walks `include`'s file and the files it includes, depth first in include order, until
    /// `matches` accepts one; returns that file's path as written. `visiting` sees every file read.
    private func firstFile(
        from include: Include,
        where matches: (_ text: String, _ path: String) -> Bool,
        visiting: (_ data: Data, _ path: String) -> Void = { _, _ in }
    ) -> String? {
        var visited = Set<URL>()
        func visit(_ url: URL, writtenAs path: String, depth: Int) -> String? {
            let url = url.standardizedFileURL
            guard depth <= Self.maxDepth, visited.count < Self.maxFiles, visited.insert(url).inserted,
                  let data = read(url) else { return nil }
            visiting(data, path)
            let text = String(decoding: data, as: UTF8.self)
            if matches(text, path) { return path }
            let directory = url.deletingLastPathComponent()
            for nested in Self.includes(in: text) {
                if let found = visit(Self.resolve(nested.path, in: directory), writtenAs: nested.path, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }
        return visit(Self.resolve(include.path, in: folder), writtenAs: include.path, depth: 0)
    }

    /// PlantUML resolves an include against the folder of the file it is written in.
    private static func resolve(_ path: String, in directory: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
    }

    /// Included files are text; anything over a megabyte is not worth reading for this.
    private static func readSmallFile(_ url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              size.isRegularFile == true, (size.fileSize ?? .max) <= 1_000_000 else { return nil }
        return try? Data(contentsOf: url)
    }
}
