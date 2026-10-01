import Foundation
import Testing
@testable import PumlCore

/// Process handling, checked against a shell script that stands in for `java -jar plantuml.jar -pipe`.
/// `make test` runs suites one at a time, so descriptor counts are not disturbed by other tests.
@Suite(.serialized) struct PlantUMLPipeTests {
    private let options = RenderOptions(workingDirectory: FileManager.default.temporaryDirectory)
    private let diagram = "@startuml\nA -> B\n@enduml"

    @Test func keepsReadingStderrWhileJavaWrites() throws {
        // Without concurrent reading Java blocks once the 64 KB stderr pipe is full.
        let fake = try FakePlantUML(prelude: "head -c 200000 /dev/zero | tr '\\0' x >&2")
        let pipe = PlantUMLPipe(toolchain: fake.toolchain, options: options)
        let start = Date()
        #expect(try pipe.render(diagram, timeout: 10) == .image(Data("<svg/>".utf8)))
        #expect(Date().timeIntervalSince(start) < 3)
        pipe.terminate()
    }

    @Test func timeoutStopsTheWholeProcessGroup() async throws {
        // `sleep` plays Graphviz `dot`: a child that would outlive a killed Java.
        let fake = try FakePlantUML(prelude: "sleep 600 & echo $! > child.pid", reply: "sleep 600")
        let pipe = PlantUMLPipe(toolchain: fake.toolchain, options: RenderOptions(workingDirectory: fake.folder))
        #expect(throws: RenderFailure.timedOut) { try pipe.render(diagram, timeout: 1) }

        let childPID = try #require(pid_t(String(contentsOf: fake.folder.appendingPathComponent("child.pid"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(await processExits(childPID))
    }

    @Test func terminateDoesNotWaitForARender() async throws {
        let fake = try FakePlantUML(reply: "sleep 600")
        let pipe = PlantUMLPipe(toolchain: fake.toolchain, options: options)
        let render = Task.detached { [diagram] in try pipe.render(diagram, timeout: 30) }
        try await Task.sleep(for: .milliseconds(300))

        let start = Date()
        pipe.terminate()
        #expect(Date().timeIntervalSince(start) < 0.1)
        await #expect(throws: RenderFailure.stopped) { try await render.value }
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(throws: RenderFailure.stopped) { try pipe.render(diagram, timeout: 1) }
    }

    @Test func doesNotRestartJavaForADiagramThatKillsIt() throws {
        // Each launch leaves a line; the reply kills the process, as a recursive !include does.
        let fake = try FakePlantUML(prelude: "echo launched >> launches.log", reply: "kill -9 $$")
        let pipe = PlantUMLPipe(toolchain: fake.toolchain, options: RenderOptions(workingDirectory: fake.folder))
        #expect(throws: RenderFailure.crashed("")) { try pipe.render(diagram, timeout: 5) }
        let launches = try String(contentsOf: fake.folder.appendingPathComponent("launches.log"), encoding: .utf8)
        #expect(launches.split(separator: "\n").count == 1)
        pipe.terminate()
    }

    @Test func closesTheDescriptorsOfEveryProcess() async throws {
        let fake = try FakePlantUML()
        let before = try openDescriptorCount()
        let pipe = PlantUMLPipe(toolchain: fake.toolchain, options: options)
        for _ in 0..<10 {
            _ = try pipe.render(diagram, timeout: 5)
            let pid = try #require(pipe.processIdentifier)
            kill(pid, SIGKILL)
            // Dead by the next render: a process dying under a render counts as a crash instead.
            try await Task.sleep(for: .milliseconds(50))
            _ = try pipe.render(diagram, timeout: 5)
        }
        pipe.terminate()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try openDescriptorCount() == before)
    }

    @Test func passesAMinimalEnvironmentAndTheSandboxProfile() throws {
        setenv("JAVA_TOOL_OPTIONS", "-Dinjected=1", 1)
        setenv("PLANTUML_ALLOW_JAVASCRIPT_IN_LINK", "true", 1)
        defer {
            unsetenv("JAVA_TOOL_OPTIONS")
            unsetenv("PLANTUML_ALLOW_JAVASCRIPT_IN_LINK")
        }
        let fake = try FakePlantUML(reply: #"printf '<svg>%s | %s</svg>%s\n' "$*" "$(env | tr '\n' ' ')" "$delimiter""#)

        let sandboxed = PlantUMLPipe(toolchain: fake.toolchain, options: options)
        let reply = try sandboxed.render(diagram, timeout: 5)
        sandboxed.terminate()
        guard case .image(let data) = reply else { Issue.record("expected an image, got \(reply)"); return }
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("-DPLANTUML_SECURITY_PROFILE=SANDBOX"))
        #expect(text.contains("PATH=/usr/bin"))
        #expect(!text.contains("JAVA_TOOL_OPTIONS"))
        #expect(!text.contains("PLANTUML_ALLOW_JAVASCRIPT_IN_LINK"))

        var trusting = options
        trusting.trustsLocalFiles = true
        let trusted = PlantUMLPipe(toolchain: fake.toolchain, options: trusting)
        let trustedReply = try trusted.render(diagram, timeout: 5)
        trusted.terminate()
        guard case .image(let trustedData) = trustedReply else { Issue.record("expected an image"); return }
        let trustedText = String(decoding: trustedData, as: UTF8.self)
        #expect(trustedText.contains("-DPLANTUML_SECURITY_PROFILE=ALLOWLIST"))
        #expect(trustedText.contains("-Dplantuml.allowlist.path=\(trusting.workingDirectory.path)"))

        // PlantUML splits the allowlist at ":", so a folder named "a:b" stays in the sandbox.
        let colonFolder = fake.folder.appendingPathComponent("a:b")
        try FileManager.default.createDirectory(at: colonFolder, withIntermediateDirectories: true)
        let colon = PlantUMLPipe(toolchain: fake.toolchain, options: RenderOptions(workingDirectory: colonFolder, trustsLocalFiles: true))
        let colonReply = try colon.render(diagram, timeout: 5)
        colon.terminate()
        guard case .image(let colonData) = colonReply else { Issue.record("expected an image"); return }
        let colonText = String(decoding: colonData, as: UTF8.self)
        #expect(colonText.contains("-DPLANTUML_SECURITY_PROFILE=SANDBOX"))
        #expect(!colonText.contains("allowlist"))
    }

    private func openDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }

    private func processExits(_ pid: pid_t) async -> Bool {
        for _ in 0..<40 {
            if kill(pid, 0) == -1, errno == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

/// A shell script that answers like `plantuml -pipe`: after each `@end…` line it runs `reply`
/// (by default an SVG followed by the delimiter). `prelude` runs once at start. Its folder goes
/// away with it.
final class FakePlantUML {
    let folder: URL
    let toolchain: Toolchain

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    init(prelude: String = "", reply: String = #"printf '<svg/>%s\n' "$delimiter""#) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pumlpad-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("java")
        try """
        #!/bin/sh
        delimiter=""
        previous=""
        for argument in "$@"; do
          [ "$previous" = "-pipedelimitor" ] && delimiter="$argument"
          previous="$argument"
        done
        \(prelude)
        while IFS= read -r line; do
          case "$line" in
            @end*) \(reply) ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
        let jar = folder.appendingPathComponent("plantuml.jar")
        try Data().write(to: jar)
        toolchain = Toolchain(java: script, jar: jar, dot: nil)
    }
}

/// Which renders are retried when their process stops, checked against `FakePlantUML`.
@Suite(.serialized) struct RenderServiceLifecycleTests {
    private let diagram = DiagramBlock(source: "@startuml\nA -> B\n@enduml", startLine: Line(index: 0), kind: "uml")

    /// Quitting during a render used to retry it on a new Java, which outlived the app with its `dot`.
    @Test func startsNoProcessAfterShutdown() async throws {
        let fake = try FakePlantUML(prelude: "echo launched >> launches.log", reply: "sleep 600")
        let service = RenderService(toolchain: fake.toolchain)
        let options = RenderOptions(workingDirectory: fake.folder)
        let render = Task { [diagram] in try await service.render(diagram, options: options) }
        try await Task.sleep(for: .milliseconds(300))
        service.shutdown()
        await #expect(throws: RenderFailure.stopped) { try await render.value }
        await #expect(throws: RenderFailure.stopped) { try await service.render(diagram, options: options) }
        service.warmUp(options: options)
        try await Task.sleep(for: .milliseconds(300))
        #expect(service.processIdentifiers.isEmpty)
        #expect(try launchCount(fake) == 1)
    }

    /// A window closing during a render must not leave a new process behind for its folder.
    @Test func doesNotRestartTheProcessOfAFolderNoLongerInUse() async throws {
        let fake = try FakePlantUML(prelude: "echo launched >> launches.log", reply: "sleep 600")
        let service = RenderService(toolchain: fake.toolchain)
        let options = RenderOptions(workingDirectory: fake.folder)
        let render = Task { [diagram] in try await service.render(diagram, options: options) }
        try await Task.sleep(for: .milliseconds(300))
        service.stopProcesses(keeping: [])
        await #expect(throws: RenderFailure.stopped) { try await render.value }
        try await Task.sleep(for: .milliseconds(300))
        #expect(service.processIdentifiers.isEmpty)
        #expect(try launchCount(fake) == 1)
        service.shutdown()
    }

    /// A process stopped to make room for another one is restarted for the render that waited on it.
    @Test func retriesARenderWhoseProcessMadeRoom() async throws {
        // SVG answers after two seconds, PNG at once.
        let fake = try FakePlantUML(reply: #"case " $* " in *" -tpng "*) ;; *) sleep 2 ;; esac; printf '<svg/>%s\n' "$delimiter""#)
        let service = RenderService(toolchain: fake.toolchain, maxProcesses: 2)
        let svg = RenderOptions(workingDirectory: fake.folder)
        var png = svg
        png.format = .png
        var darkPNG = png
        darkPNG.darkMode = true
        let slow = Task { [diagram] in try await service.render(diagram, options: svg) }
        try await Task.sleep(for: .milliseconds(300))
        _ = try await service.render(diagram, options: png)
        // A third process: the SVG one is the least recently used and makes room.
        _ = try await service.render(diagram, options: darkPNG)
        #expect(try await slow.value.image == Data("<svg/>".utf8))
        service.shutdown()
    }

    private func launchCount(_ fake: FakePlantUML) throws -> Int {
        try String(contentsOf: fake.folder.appendingPathComponent("launches.log"), encoding: .utf8)
            .split(separator: "\n").count
    }
}
