import Foundation

/// Java, the PlantUML jar and Graphviz on this Mac.
public struct Toolchain: Equatable, Sendable {
    public var java: URL
    public var jar: URL
    /// Graphviz `dot`. Without it PlantUML lays diagrams out with its built-in Smetana engine.
    public var dot: URL?

    public init(java: URL, jar: URL, dot: URL?) {
        self.java = java
        self.jar = jar
        self.dot = dot
    }

    public enum Missing: Error, Equatable, Sendable, CustomStringConvertible {
        case java, plantUML

        public var description: String {
            switch self {
            case .java: "Java not found. Install it with: brew install openjdk"
            case .plantUML: "PlantUML not found. Install it with: brew install plantuml"
            }
        }
    }

    /// Looks the tools up at fixed paths: apps launched from Finder do not inherit the shell's PATH.
    /// `PUMLPAD_JAVA`, `PUMLPAD_PLANTUML_JAR` and `GRAPHVIZ_DOT` override the defaults.
    /// A standalone build (`make app-standalone`) carries its own jar and Java runtime.
    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledJar: URL? = Bundle.main.url(forResource: "plantuml", withExtension: "jar"),
        bundledJava: URL? = Bundle.main.url(forResource: "jre", withExtension: nil)?.appendingPathComponent("bin/java"),
        isFile: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) },
        javaHome: () -> String? = Toolchain.systemJavaHome
    ) -> Result<Toolchain, Missing> {
        let jarCandidates: [String?] = [
            environment["PUMLPAD_PLANTUML_JAR"],
            bundledJar?.path,
            "/opt/homebrew/opt/plantuml/libexec/plantuml.jar",
            "/usr/local/opt/plantuml/libexec/plantuml.jar",
        ]
        guard let jar = jarCandidates.compactMap({ $0 }).first(where: isFile) else { return .failure(.plantUML) }

        // Homebrew's `plantuml` script runs on Homebrew's openjdk, so prefer it over JAVA_HOME.
        let javaCandidates: [String?] = [
            environment["PUMLPAD_JAVA"],
            bundledJava?.path,
            "/opt/homebrew/opt/openjdk/bin/java",
            "/usr/local/opt/openjdk/bin/java",
            environment["JAVA_HOME"].map { "\($0)/bin/java" },
        ]
        var java = javaCandidates.compactMap { $0 }.first(where: isFile)
        if java == nil, let home = javaHome(), isFile("\(home)/bin/java") {
            java = "\(home)/bin/java"
        }
        guard let java else { return .failure(.java) }

        let dotCandidates: [String?] = [
            environment["GRAPHVIZ_DOT"], "/opt/homebrew/bin/dot", "/usr/local/bin/dot", "/opt/local/bin/dot",
        ]
        let dot = dotCandidates.compactMap { $0 }.first(where: isFile)

        return .success(Toolchain(
            java: URL(fileURLWithPath: java),
            jar: URL(fileURLWithPath: jar),
            dot: dot.map { URL(fileURLWithPath: $0) }
        ))
    }

    /// `/usr/libexec/java_home` knows JDKs installed outside Homebrew (Adoptium, Zulu…).
    public static func systemJavaHome() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
