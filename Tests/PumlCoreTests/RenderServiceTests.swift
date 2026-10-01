import Foundation
import Testing
@testable import PumlCore

/// Runs the real PlantUML found on this Mac; skipped when it is not installed.
@Suite(.enabled(if: (try? Toolchain.discover().get()) != nil), .serialized)
final class RenderServiceTests {
    /// A diagram -pipe cannot close would wait out the timeout; 10 s fails such a test quickly.
    private let service = RenderService(toolchain: try! Toolchain.discover().get(), timeout: 10)
    private let folder: URL
    private let options: RenderOptions

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pumlpad-render-\(UUID().uuidString)")
        let files = [
            "part.iuml": "Alice -> Bob : from include\n",
            "bad.iuml": "Alice -> Bob\nthis is broken ((\n",
            "data.json": #"{"token": "SECRET-TOKEN"}"#,
            "x.iuml": "X -> Y\n",
            "sub/a.iuml": "A -> C\n!include b.iuml\n",
            "sub/b.iuml": "B -> C\nbroken in b ((\n",
            "own.iuml": "@startuml\nC -> D\nbroken in own ((\n@enduml\n",
        ]
        for (name, text) in files {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try #require("Alice -> Bob : Привет\n".data(using: .windowsCP1251)).write(to: folder.appendingPathComponent("ru.iuml"))
        options = RenderOptions(workingDirectory: folder)
    }

    deinit {
        service.shutdown()
        try? FileManager.default.removeItem(at: folder)
    }

    private var trusted: RenderOptions {
        var options = options
        options.trustsLocalFiles = true
        return options
    }

    private func svg(_ result: RenderResult) -> String {
        String(decoding: result.image ?? Data(), as: UTF8.self)
    }

    private func diagram(_ document: String) throws -> DiagramBlock {
        try #require(DiagramSource.block(in: document))
    }

    @Test func rendersSVGInOneWarmProcess() async throws {
        let block = try diagram("@startuml\nAlice -> Bob : привет\n@enduml")
        let first = try await service.render(block, options: options)
        let processes = service.processIdentifiers
        let second = try await service.render(block, options: options)

        #expect(first.error == nil)
        // PlantUML 1.2026.2 writes non-ASCII text as character references, 1.2026.8 as is.
        #expect(svg(second).contains("привет") || svg(second).contains("&#1087;&#1088;&#1080;&#1074;&#1077;&#1090;"))
        #expect(processes.count == 1)
        #expect(service.processIdentifiers == processes)
        #expect(second.duration < .milliseconds(500))
    }

    @Test func reportsSyntaxErrorOnTheDocumentLineAndKeepsWorking() async throws {
        let failed = try await service.render(diagram("' comment\n@startuml\nAlice -> Bob\nthis is wrong ((\n@enduml"), options: options)
        #expect(failed.error?.line == Line(number: 4))
        #expect(failed.error?.message.contains("Syntax Error") == true)
        #expect(try await service.render(diagram("@startuml\nAlice -> Bob\n@enduml"), options: options).error == nil)
    }

    /// Tags -pipe does not take as written: before, each of these waited out the timeout.
    @Test func answersDiagramsWhoseTagsThePipeWouldWaitOn() async throws {
        for document in ["  @startuml\nA -> B\n  @enduml", "@startmindmap\n* a\n@enduml", "@startUML\nA -> B\n@enduml", "@StartUML\nA -> B\n@EndUML"] {
            let result = try await service.render(diagram(document), options: options)
            #expect(result.duration < .seconds(5), "\(document)")
        }
    }

    @Test func diagramsCannotSwitchTheProcessToPNG() async throws {
        _ = try await service.render(diagram("@startuml\n@@@format png\nA -> B\n@enduml"), options: options)
        let next = try await service.render(diagram("@startuml\nA -> B\n@enduml"), options: options)
        #expect(next.image?.first == UInt8(ascii: "<"))
    }

    @Test func rendersPNG() async throws {
        var pngOptions = options
        pngOptions.format = .png
        let result = try await service.render(diagram("@startuml\nAlice -> Bob\n@enduml"), options: pngOptions)
        #expect(result.image?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    }

    /// `skinparam dpi` does nothing to JSON; the Retina export used to come out at 1×.
    @Test func retinaPNGOfJSONHasTwiceThePixels() async throws {
        var pngOptions = options
        pngOptions.format = .png
        let json = try diagram("@startjson\n{\"a\": 1, \"b\": [1, 2]}\n@endjson")
        let standard = try #require(try await service.render(json, options: pngOptions).image)
        let retina = try #require(try await service.render(json.scaled(.retina), options: pngOptions).image)
        let ratio = Double(pngWidth(retina)) / Double(pngWidth(standard))
        #expect((1.9...2.1).contains(ratio), "\(pngWidth(standard)) → \(pngWidth(retina))")
    }

    @Test func blocksLocalFilesUnlessTheFolderIsTrusted() async throws {
        let include = try diagram("@startuml\nAlice -> Bob\n!include part.iuml\n@enduml")
        let blocked = try await service.render(include, options: options)
        #expect(blocked.error == DiagramError(line: Line(number: 3), message: "cannot include part.iuml"))

        let allowed = try await service.render(include, options: trusted)
        #expect(allowed.error == nil)
        #expect(svg(allowed).contains("from include"))
    }

    @Test func sandboxDoesNotReadFilesThroughBuiltins() async throws {
        let result = try await service.render(diagram("@startuml\n!$d = %load_json(\"data.json\")\nAlice -> Bob : $d.token\n@enduml"), options: options)
        #expect(!svg(result).contains("SECRET-TOKEN"))
    }

    @Test func standardLibraryWorksInTheSandbox() async throws {
        let result = try await service.render(diagram("@startuml\n!include <C4/C4_Container>\nPerson(p, \"Customer\")\n@enduml"), options: options)
        #expect(result.error == nil)
        #expect(svg(result).contains("Customer"))
    }

    @Test func pointsAnErrorInAnIncludedFileAtTheInclude() async throws {
        let result = try await service.render(diagram("@startuml\nAlice -> Bob\n!include bad.iuml\nBob -> Alice\n@enduml"), options: trusted)
        #expect(result.error == DiagramError(
            line: Line(number: 3), message: "Syntax Error? (Assumed diagram type: sequence)",
            includedFile: "bad.iuml", includedFileLine: Line(number: 2)
        ))
    }

    @Test func pointsAnErrorInANestedIncludeAtTheDiagramsInclude() async throws {
        let result = try await service.render(diagram("@startuml\n!include x.iuml\n!include sub/a.iuml\n@enduml"), options: trusted)
        #expect(result.error?.line == Line(number: 3))
        #expect(result.error?.includedFile == "b.iuml")
        #expect(result.error?.includedFileLine == Line(number: 2))
    }

    @Test func findsAnIncludedFileWithItsOwnStartTag() async throws {
        let result = try await service.render(diagram("@startuml\n!include x.iuml\n!include own.iuml\n@enduml"), options: trusted)
        #expect(result.error?.line == Line(number: 3))
        #expect(result.error?.includedFile == "own.iuml")
        #expect(result.error?.includedFileLine == Line(number: 3))
    }

    /// -pipe reads included files as UTF-8 whatever the -charset: a Windows-1251 one shows "�".
    @Test func namesIncludedFilesThatAreNotUTF8() async throws {
        let result = try await service.render(diagram("@startuml\n!include ru.iuml\n@enduml"), options: trusted)
        #expect(result.includesNotInUTF8 == ["ru.iuml"])
        let clean = try await service.render(diagram("@startuml\n!include part.iuml\n@enduml"), options: trusted)
        #expect(clean.includesNotInUTF8.isEmpty)
    }

    @Test func stopsIdleProcessesButKeepsTheNewest() async throws {
        let block = try diagram("@startuml\nAlice -> Bob\n@enduml")
        var pngOptions = options
        pngOptions.format = .png
        _ = try await service.render(block, options: pngOptions)
        _ = try await service.render(block, options: options)
        #expect(service.processIdentifiers.count == 2)

        // Two minutes later the PNG process has idled past its minute; the SVG one is the newest.
        service.stopIdleProcesses(now: .now + .seconds(120))
        #expect(service.processIdentifiers.count == 1)
        #expect(try await service.render(block, options: options).error == nil)
    }

    @Test func stopsProcessesOfFoldersNoLongerInUse() async throws {
        _ = try await service.render(diagram("@startuml\nAlice -> Bob\n@enduml"), options: options)
        service.stopProcesses(keeping: [folder])
        #expect(service.processIdentifiers.count == 1)
        service.stopProcesses(keeping: [])
        #expect(service.processIdentifiers.isEmpty)
    }

    @Test func restartsAProcessThatDied() async throws {
        let block = try diagram("@startuml\nAlice -> Bob\n@enduml")
        _ = try await service.render(block, options: options)
        let pid = try #require(service.processIdentifiers.first)
        kill(pid, SIGKILL)
        try await Task.sleep(for: .milliseconds(100))

        let result = try await service.render(block, options: options)
        #expect(result.error == nil)
        #expect(service.processIdentifiers.first != pid)
    }

    private func pngWidth(_ png: Data) -> Int {
        // IHDR: the width is the big-endian 32-bit number after the 8-byte signature and 8-byte chunk header.
        png.dropFirst(16).prefix(4).reduce(0) { $0 << 8 | Int($1) }
    }
}
