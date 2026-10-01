// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pumlpad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pumlpad", targets: ["Pumlpad"]),
    ],
    targets: [
        // Rendering engine: PlantUML process management, diagram extraction, error mapping.
        // Foundation only, so it is testable without a UI.
        .target(name: "PumlCore"),
        // AppKit application: document windows, editor, preview, export.
        .executableTarget(name: "Pumlpad", dependencies: ["PumlCore"]),
        // Render timings for docs/benchmarks.md; not part of the app.
        .executableTarget(name: "PumlBench", dependencies: ["PumlCore"]),
        .testTarget(name: "PumlCoreTests", dependencies: ["PumlCore"]),
    ]
)
