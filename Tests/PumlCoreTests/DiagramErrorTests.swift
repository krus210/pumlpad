import Foundation
import Testing
@testable import PumlCore

@Suite struct DiagramErrorTests {
    /// "' comment" on line 1, "@startuml" on line 2.
    private let block = DiagramBlock(
        source: "@startuml\nAlice -> Bob\n!include <C4/C4_Container>\n!include parts/bad.iuml\nbroken ((\n@enduml",
        startLine: Line(number: 2),
        kind: "uml"
    )

    /// Files by path, for an include tree without a disk.
    private func tree(_ files: [String: String]) -> IncludeTree {
        let folder = URL(fileURLWithPath: "/project")
        let contents = Dictionary(uniqueKeysWithValues: files.map { (folder.appendingPathComponent($0.key).standardizedFileURL.path, Data($0.value.utf8)) })
        return IncludeTree(folder: folder, read: { contents[$0.standardizedFileURL.path] })
    }

    @Test func mapsAnErrorInTheDiagramToItsDocumentLine() {
        let error = DiagramError.parse(report: "string:5:error:Syntax Error? (Assumed diagram type: sequence)\n", block: block)
        #expect(error == DiagramError(line: Line(number: 6), message: "Syntax Error? (Assumed diagram type: sequence)"))
    }

    @Test func pointsAnErrorInAnIncludedFileAtItsInclude() {
        let error = DiagramError.parse(report: "parts/bad.iuml:2:error:Syntax Error?\n", block: block)
        #expect(error == DiagramError(
            line: Line(number: 5), message: "Syntax Error?", includedFile: "parts/bad.iuml", includedFileLine: Line(number: 2)
        ))
    }

    /// PlantUML names the file as written in the innermost `!include`, relative to the file it is in.
    @Test func followsNestedIncludesToTheDiagramsInclude() {
        let block = DiagramBlock(source: "@startuml\n!include x.iuml\n!include sub/a.iuml\n@enduml", startLine: Line(index: 0), kind: "uml")
        let includes = tree(["x.iuml": "X -> Y\n", "sub/a.iuml": "A -> C\n!include b.iuml\n", "sub/b.iuml": "B -> C\nbroken ((\n"])
        let error = DiagramError.parse(report: "b.iuml:2:error:Syntax Error?", block: block, includes: includes)
        #expect(error.line == Line(number: 3))
        #expect(error.includedFile == "b.iuml")
        #expect(error.includedFileLine == Line(number: 2))
    }

    @Test func matchesWholeFileNamesOnly() {
        let block = DiagramBlock(source: "@startuml\n!include bb.iuml\n!include b.iuml\n@enduml", startLine: Line(index: 0), kind: "uml")
        let error = DiagramError.parse(report: "b.iuml:2:error:Syntax Error?", block: block)
        #expect(error.line == Line(number: 3))
    }

    /// A file with its own `@startuml` is reported as `desc…`: the file with diagram text at that line is meant.
    @Test func findsAnIncludedFileWithItsOwnStartTag() {
        let block = DiagramBlock(source: "@startuml\n!include ok.iuml\n!include c.iuml\n@enduml", startLine: Line(index: 0), kind: "uml")
        let includes = tree([
            "ok.iuml": "@startuml\nO -> K\n@enduml\n",
            "c.iuml": "@startuml\nC -> D\nbroken ((\n@enduml\n",
        ])
        let error = DiagramError.parse(report: "desc2:3:error:Syntax Error?", block: block, includes: includes)
        #expect(error.line == Line(number: 3))
        #expect(error.includedFile == "c.iuml")
        #expect(error.includedFileLine == Line(number: 3))
        #expect(DiagramError.parse(report: "desc2:3:error:Syntax Error?", block: block).includedFile == nil)
    }

    @Test func keepsColonsInTheMessage() {
        let error = DiagramError.parse(report: "string:2:error:cannot include a:b.iuml", block: block)
        #expect(error.message == "cannot include a:b.iuml")
        #expect(error.line == Line(number: 3))
    }

    @Test func unknownReportBecomesAMessageOnTheStartLine() {
        #expect(DiagramError.parse(report: "Something odd\n", block: block) == DiagramError(line: Line(number: 2), message: "Something odd"))
        #expect(DiagramError.parse(report: "", block: block) == DiagramError(line: Line(number: 2), message: "Syntax error"))
    }

    @Test func findsIncludedFilesNotInUTF8() {
        var includes = tree(["a.iuml": "!include b.iuml\n"])
        let read = includes.read
        includes.read = { url in url.lastPathComponent == "b.iuml" ? "Алиса".data(using: .windowsCP1251) : read(url) }
        #expect(includes.filesNotInUTF8(in: "@startuml\n!include a.iuml\n@enduml") == ["b.iuml"])
    }
}

@Suite struct PipeReplyTests {
    @Test func recognisesSVGEvenAfterABlankLine() {
        let svg = Data("<?plantuml 1.2026.2?><svg/>".utf8)
        #expect(PipeReply(svg) == .image(svg))
        #expect(PipeReply(Data("\n".utf8) + svg) == .image(svg))
    }

    @Test func recognisesPNG() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        #expect(PipeReply(png) == .image(png))
    }

    @Test func treatsAnythingElseAsAReport() {
        #expect(PipeReply(Data("string:3:error:Syntax Error?\n".utf8)) == .report("string:3:error:Syntax Error?\n"))
    }
}
