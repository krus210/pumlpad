// Render times of Pumlpad's engine, compared with starting Java for every render (what the
// `plantuml` command and simple previewers do). Prints Markdown tables.
//
// Usage: make bench, or swift run -c release PumlBench <samples folder>
// Uses the PlantUML and Java that Pumlpad would find (PUMLPAD_PLANTUML_JAR, PUMLPAD_JAVA).
import Foundation
import PumlCore

struct Sample {
    let name: String
    let block: DiagramBlock
}

@main
@MainActor
struct PumlBench {
    static let warmRuns = 30
    static let coldRuns = 5

    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Samples")
        let toolchain = try Toolchain.discover().get()
        let samples = try loadSamples(from: folder)

        print("## Machine\n")
        print("- \(shell("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string")), macOS \(shell("/usr/bin/sw_vers", "-productVersion"))")
        print("- \(shell(toolchain.java.path, "-version").split(separator: "\n").first ?? "")")
        print("- \(shell(toolchain.java.path, "-jar", toolchain.jar.path, "-version").split(separator: "\n").first ?? "")")
        print("- Graphviz: \(toolchain.dot.map { _ in "installed" } ?? "not installed, Smetana layout")\n")

        let service = RenderService(toolchain: toolchain)
        let options = RenderOptions(workingDirectory: folder)
        let first = try await measure { _ = try await service.render(samples[0].block, options: options) }

        print("## Pumlpad: one warm PlantUML process\n")
        print("First render, including Java start: **\(format(first))**\n")
        print("| Diagram | Median | 95th percentile |")
        print("|---|---:|---:|")
        for sample in samples {
            for _ in 0..<5 { _ = try await service.render(sample.block, options: options) }
            var times: [Duration] = []
            for _ in 0..<warmRuns {
                times.append(try await measure { _ = try await service.render(sample.block, options: options) })
            }
            print("| \(sample.name) | \(format(percentile(times, 0.5))) | \(format(percentile(times, 0.95))) |")
        }
        print("\nPlantUML process memory after these renders: **\(childMemory()) MB** (resident).\n")
        service.shutdown()

        print("## For comparison: a new Java process per render\n")
        print("`java -jar plantuml.jar -tsvg -pipe < diagram`, \(coldRuns) runs each.\n")
        print("| Diagram | Median |")
        print("|---|---:|")
        for sample in samples {
            var times: [Duration] = []
            for _ in 0..<coldRuns {
                times.append(try await measure { try runPlantUMLOnce(toolchain, source: sample.block.source, in: folder) })
            }
            print("| \(sample.name) | \(format(percentile(times, 0.5))) |")
        }
    }

    static func loadSamples(from folder: URL) throws -> [Sample] {
        let sequence = try String(contentsOf: folder.appendingPathComponent("sequence.puml"), encoding: .utf8)
        let c4 = try String(contentsOf: folder.appendingPathComponent("c4-container.puml"), encoding: .utf8)
        let several = try String(contentsOf: folder.appendingPathComponent("multiple-diagrams.puml"), encoding: .utf8)
        let lines = several.split(separator: "\n", omittingEmptySubsequences: false)
        let mindmapLine = lines.firstIndex { $0.hasPrefix("@startmindmap") } ?? 0
        return [
            Sample(name: "Sequence, 5 participants", block: DiagramSource.block(in: sequence)!),
            Sample(name: "Class, 3 classes (Graphviz)", block: DiagramSource.block(in: several, caretLine: Line(index: 3))!),
            Sample(name: "Mind map, 12 nodes", block: DiagramSource.block(in: several, caretLine: Line(index: mindmapLine))!),
            Sample(name: "C4 containers (standard library)", block: DiagramSource.block(in: c4)!),
        ]
    }

    static func runPlantUMLOnce(_ toolchain: Toolchain, source: String, in folder: URL) throws {
        let process = Process()
        process.executableURL = toolchain.java
        process.arguments = ["-Djava.awt.headless=true", "-jar", toolchain.jar.path, "-tsvg", "-pipe"]
        process.currentDirectoryURL = folder
        if let dot = toolchain.dot { process.environment = ["GRAPHVIZ_DOT": dot.path] }
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data((source + "\n").utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    static func measure(_ work: () async throws -> Void) async rethrows -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try await work()
        return clock.now - start
    }

    static func percentile(_ times: [Duration], _ fraction: Double) -> Duration {
        let sorted = times.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction + 0.5))]
    }

    static func format(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return milliseconds >= 100 ? String(format: "%.0f ms", milliseconds) : String(format: "%.1f ms", milliseconds)
    }

    /// Resident memory of this process's children, i.e. the PlantUML JVM.
    static func childMemory() -> Int {
        let pids = shell("/usr/bin/pgrep", "-P", String(getpid())).split(separator: "\n")
        let kilobytes = pids.compactMap { Int(shell("/bin/ps", "-o", "rss=", "-p", String($0)).trimmingCharacters(in: .whitespaces)) }
        return kilobytes.reduce(0, +) / 1024
    }

    static func shell(_ executable: String, _ arguments: String...) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
