import Foundation
import Testing
@testable import PumlCore

@Suite struct DiagramSourceTests {
    @Test func takesTheOnlyBlock() throws {
        let block = try #require(DiagramSource.block(in: "@startuml\nA -> B\n@enduml"))
        #expect(block == DiagramBlock(source: "@startuml\nA -> B\n@enduml", startLine: Line(index: 0), kind: "uml"))
    }

    @Test func dropsTextOutsideTheBlock() throws {
        // -pipe would treat the trailing text as the start of the next diagram.
        let block = try #require(DiagramSource.block(in: "' header\n\n@startuml\nA -> B\n@enduml\nnotes after"))
        #expect(block.source == "@startuml\nA -> B\n@enduml")
        #expect(block.startLine == Line(index: 2))
    }

    @Test func closesAnUnfinishedBlock() throws {
        let block = try #require(DiagramSource.block(in: "@startmindmap\n* root\n\n  "))
        #expect(block.source == "@startmindmap\n* root\n@endmindmap")
        #expect(block.kind == "mindmap")
    }

    @Test func unfinishedBlockStopsAtTheNextStart() throws {
        let doc = "@startuml\nA -> B\n@startuml\nC -> D\n@enduml"
        #expect(DiagramSource.block(in: doc)?.source == "@startuml\nA -> B\n@enduml")
        #expect(DiagramSource.block(in: doc, caretLine: Line(index: 3))?.source == "@startuml\nC -> D\n@enduml")
    }

    @Test func picksTheBlockAtTheCaret() {
        let doc = "@startuml\nA -> B\n@enduml\n\n@startuml\nC -> D\n@enduml"
        #expect(DiagramSource.block(in: doc, caretLine: Line(index: 5))?.startLine == Line(index: 4))
        #expect(DiagramSource.block(in: doc, caretLine: Line(index: 3))?.startLine == Line(index: 0))
        #expect(DiagramSource.block(in: doc, caretLine: nil)?.startLine == Line(index: 0))
    }

    @Test func wrapsTextWithoutStartTag() throws {
        let block = try #require(DiagramSource.block(in: "A -> B"))
        #expect(block.source == "@startuml\nA -> B\n@enduml")
        #expect(block.startLine == nil)
    }

    @Test func blankDocumentHasNoDiagram() {
        #expect(DiagramSource.block(in: "  \n\t\r\n") == nil)
    }

    @Test func acceptsNamedStartTagsAndAnyLineBreak() throws {
        let block = try #require(DiagramSource.block(in: "@startuml my-diagram\r\nA -> B\rB -> A\n@enduml\r\n"))
        #expect(block.kind == "uml")
        #expect(block.source == "@startuml my-diagram\nA -> B\nB -> A\n@enduml")
    }

    /// PlantUML takes indented tags in files, but -pipe waits forever for a closing line it
    /// recognises: the block goes out with both tags at the start of their lines.
    @Test func unindentsTagsForThePipe() throws {
        let block = try #require(DiagramSource.block(in: "' c\n  @startuml\n  A -> B\n\t@enduml"))
        #expect(block.source == "@startuml\n  A -> B\n@enduml")
        #expect(block.startLine == Line(index: 1))
    }

    /// PlantUML's tags are lower case; `@StartUML` is not a diagram start, so it is wrapped
    /// and PlantUML reports the line instead of the render hanging.
    @Test func tagsAreCaseSensitive() throws {
        let block = try #require(DiagramSource.block(in: "@StartUML\nA -> B\n@EndUML"))
        #expect(block.startLine == nil)
        #expect(block.source == "@startuml\n@StartUML\nA -> B\n@EndUML\n@enduml")
    }

    /// After a bare `@startmindmap` -pipe waits for `@endmindmap` exactly, and after `@startUML` for `@endUML`.
    @Test func endsTheBlockWithTheLineThePipeWaitsFor() throws {
        #expect(DiagramSource.block(in: "@startmindmap\n* a\n@enduml")?.source == "@startmindmap\n* a\n@endmindmap")
        #expect(DiagramSource.block(in: "@startUML\nA -> B\n@enduml")?.source == "@startUML\nA -> B\n@endUML")
        // With anything after the kind, any @end… line closes it.
        #expect(DiagramSource.block(in: "@startuml(id=x)\nA -> B\n@endfoo")?.source == "@startuml(id=x)\nA -> B\n@endfoo")
    }

    /// `@@@format png` would switch the SVG process to PNG for every later diagram.
    @Test func keepsDiagramsFromSwitchingThePipeFormat() throws {
        let block = try #require(DiagramSource.block(in: "@startuml\n@@@format png\nA -> B\n@enduml"))
        #expect(block.source == "@startuml\n @@@format png\nA -> B\n@enduml")
    }

    @Test func keepsNonASCIIText() throws {
        let block = try #require(DiagramSource.block(in: "@startuml\nАлиса -> Боб : привет 👋\n@enduml"))
        #expect(block.source == "@startuml\nАлиса -> Боб : привет 👋\n@enduml")
    }

    @Test func mapsPlantUMLLinesToDocumentLines() throws {
        let block = try #require(DiagramSource.block(in: "' c\n\n@startuml\nA -> B\nbad ((\n@enduml"))
        // PlantUML counts from the @start line: "bad ((" is line 3 of the diagram, line 5 of the document.
        #expect(block.documentLine(for: Line(number: 3)) == Line(number: 5))
        let wrapped = try #require(DiagramSource.block(in: "bad (("))
        #expect(wrapped.documentLine(for: Line(number: 2)) == Line(number: 1))
        #expect(wrapped.documentLine(for: Line(number: 1)) == Line(number: 1))
    }

    @Test func retinaScaleAddsDPIAndKeepsLineMapping() throws {
        let block = try #require(DiagramSource.block(in: "' c\n@startuml\nA -> B\nbad ((\n@enduml"))
        let retina = block.scaled(.retina)
        #expect(retina.source == "@startuml\nskinparam dpi 192\nA -> B\nbad ((\n@enduml")
        // "bad ((" is line 4 of the scaled diagram and still line 4 of the document.
        #expect(retina.documentLine(for: Line(number: 4)) == Line(number: 4))
        #expect(retina.startLine == block.startLine)
        #expect(block.scaled(.standard) == block)
    }

    /// JSON and YAML ignore `skinparam dpi`; ditaa has neither skinparams nor `scale`.
    @Test func retinaScaleUsesWhatEachKindUnderstands() throws {
        let json = try #require(DiagramSource.block(in: "@startjson\n{\"a\": 1}\n@endjson"))
        #expect(json.scaled(.retina).source == "@startjson\nscale 2\n{\"a\": 1}\n@endjson")
        let ditaa = try #require(DiagramSource.block(in: "@startditaa\n+--+\n@endditaa"))
        #expect(ditaa.scaled(.retina).source == "@startditaa(scale=2)\n+--+\n@endditaa")
        #expect(ditaa.scaled(.retina).documentLine(for: Line(number: 2)) == Line(number: 2))
        let options = try #require(DiagramSource.block(in: "@startditaa(--no-shadows)\n+--+\n@endditaa"))
        #expect(options.scaled(.retina).source == "@startditaa(scale=2, --no-shadows)\n+--+\n@endditaa")
    }

    /// The scan runs on every keystroke and caret move of the main thread.
    @Test func handlesLargeDocumentsQuickly() throws {
        let body = (0..<20_000).map { "Service\($0) -> Service\($0 + 1) : call \($0)" }.joined(separator: "\n")
        let document = "@startuml\n\(body)\n@enduml\n" as NSString as String
        let clock = ContinuousClock()
        let start = clock.now
        let block = try #require(DiagramSource.block(in: document, caretLine: Line(index: 10_000)))
        let elapsed = clock.now - start
        #expect(block.startLine == Line(index: 0))
        // Splitting into Characters took ~400 ms here; the byte scan takes a few, even unoptimised.
        #expect(elapsed < .milliseconds(100), "took \(elapsed)")
    }
}
