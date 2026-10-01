import Foundation

public struct RenderOptions: Hashable, Sendable {
    public var format: OutputFormat
    public var darkMode: Bool
    /// Folder that relative `!include` paths resolve against: the document's folder.
    public var workingDirectory: URL
    /// Lets the diagram read files under `workingDirectory` (`!include`, `%load_json`, `<img:…>`).
    /// Off by default: a downloaded `.puml` could otherwise read the user's files.
    public var trustsLocalFiles: Bool

    public init(format: OutputFormat = .svg, darkMode: Bool = false, workingDirectory: URL, trustsLocalFiles: Bool = false) {
        self.format = format
        self.darkMode = darkMode
        self.workingDirectory = workingDirectory.standardizedFileURL
        self.trustsLocalFiles = trustsLocalFiles
    }
}

public struct RenderResult: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// SVG or PNG bytes.
        case image(Data)
        case error(DiagramError)
    }

    public let outcome: Outcome
    public let format: OutputFormat
    public let block: DiagramBlock
    public let duration: Duration
    /// Included files, as written, that are not UTF-8: PlantUML shows their non-ASCII text as "�".
    /// Looked for only when the picture has a "�" or the error is in an included file.
    public var includesNotInUTF8: [String] = []

    public var image: Data? {
        if case .image(let data) = outcome { data } else { nil }
    }

    public var error: DiagramError? {
        if case .error(let error) = outcome { error } else { nil }
    }
}

/// Renders diagrams through warm PlantUML processes.
///
/// A process is bound to one format, colour mode, working directory and file access, so the
/// service keeps one per combination in use, at most `maxProcesses`, and stops the least recently
/// used one. Each process holds 150–300 MB, so idle ones are stopped too: PNG processes serve rare
/// exports and go after a minute, SVG ones serve typing and go after ten. The newest one stays
/// until the app says its folder is no longer used (`stopProcesses(keeping:)`).
public final class RenderService: @unchecked Sendable {
    private struct Entry {
        let pipe: PlantUMLPipe
        let queue: DispatchQueue
        /// The last render or warm-up: orders eviction and times idleness.
        var lastUse: ContinuousClock.Instant
    }

    private let toolchain: Toolchain
    private let maxProcesses: Int
    private let timeout: TimeInterval
    private let idleLimit: [OutputFormat: Duration]
    private let lock = NSLock()
    private var entries: [RenderOptions: Entry] = [:]
    /// Options whose process was stopped to make room for another one. A render that was waiting
    /// for it is retried on a new process; renders of stopped folders and after `shutdown` are not.
    private var evicted: Set<RenderOptions> = []
    private var isShutDown = false
    private var reaper: DispatchSourceTimer?

    public init(
        toolchain: Toolchain,
        maxProcesses: Int = 3,
        timeout: TimeInterval = 30,
        idleLimit: [OutputFormat: Duration] = [.svg: .seconds(600), .png: .seconds(60)]
    ) {
        self.toolchain = toolchain
        self.maxProcesses = maxProcesses
        self.timeout = timeout
        self.idleLimit = idleLimit
        let reaper = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "pumlpad.plantuml.reaper"))
        reaper.schedule(deadline: .now() + 30, repeating: 30)
        reaper.setEventHandler { [weak self] in self?.stopIdleProcesses(now: .now) }
        reaper.resume()
        self.reaper = reaper
    }

    deinit {
        reaper?.cancel()
        entries.values.forEach { $0.pipe.terminate() }
    }

    public func render(_ block: DiagramBlock, options: RenderOptions) async throws -> RenderResult {
        do {
            return try await renderOnce(block, options: options)
        } catch RenderFailure.stopped where takeEviction(of: options) {
            return try await renderOnce(block, options: options)
        }
    }

    /// Starts the process ahead of the first render, e.g. while the user picks an export file name.
    public func warmUp(options: RenderOptions) {
        guard let entry = entry(for: options) else { return }
        let timeout = timeout
        entry.queue.async {
            _ = try? entry.pipe.render("@startuml\n@enduml", timeout: timeout)
        }
    }

    /// Stops the processes of folders no open document uses, e.g. after the last window closes
    /// or a document moves elsewhere.
    public func stopProcesses(keeping folders: Set<URL>) {
        let kept = Set(folders.map(\.standardizedFileURL))
        stop { !kept.contains($0.workingDirectory) }
    }

    /// Stops every process for good: later renders fail with `RenderFailure.stopped`.
    public func shutdown() {
        lock.lock()
        isShutDown = true
        lock.unlock()
        stop { _ in true }
    }

    func stopIdleProcesses(now: ContinuousClock.Instant) {
        lock.lock()
        let newest = entries.max { $0.value.lastUse < $1.value.lastUse }?.key
        let idle = entries.filter { options, entry in
            options != newest && now - entry.lastUse > idleLimit[options.format, default: .seconds(600)]
        }
        idle.keys.forEach { entries[$0] = nil }
        lock.unlock()
        idle.values.forEach { $0.pipe.terminate() }
    }

    /// PIDs of running PlantUML processes.
    var processIdentifiers: [Int32] {
        lock.lock()
        let pipes = entries.values.map(\.pipe)
        lock.unlock()
        return pipes.compactMap(\.processIdentifier)
    }

    private func renderOnce(_ block: DiagramBlock, options: RenderOptions) async throws -> RenderResult {
        guard let entry = entry(for: options) else { throw RenderFailure.stopped }
        let timeout = timeout
        let includes = options.trustsLocalFiles ? IncludeTree(folder: options.workingDirectory) : nil
        return try await withCheckedThrowingContinuation { continuation in
            entry.queue.async {
                let clock = ContinuousClock()
                let start = clock.now
                do {
                    let outcome: RenderResult.Outcome = switch try entry.pipe.render(block.source, timeout: timeout) {
                    case .image(let data): .image(data)
                    case .report(let report): .error(DiagramError.parse(report: report, block: block, includes: includes))
                    }
                    var result = RenderResult(outcome: outcome, format: options.format, block: block, duration: clock.now - start)
                    if let includes, Self.mayShowUnreadableText(outcome) {
                        result.includesNotInUTF8 = includes.filesNotInUTF8(in: block.source)
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A "�" in the picture, or an error in an included file, may come from a file in another encoding.
    private static func mayShowUnreadableText(_ outcome: RenderResult.Outcome) -> Bool {
        switch outcome {
        case .image(let data):
            data.range(of: Data("\u{FFFD}".utf8)) != nil || data.range(of: Data("&#65533;".utf8)) != nil
        case .error(let error):
            error.isInIncludedFile
        }
    }

    private func takeEviction(of options: RenderOptions) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return evicted.remove(options) != nil
    }

    /// `terminate` does not wait for renders in progress; they fail with `RenderFailure.stopped`
    /// and are not retried.
    private func stop(where shouldStop: (RenderOptions) -> Bool) {
        lock.lock()
        let stopping = entries.filter { shouldStop($0.key) }
        stopping.keys.forEach { entries[$0] = nil }
        evicted = evicted.filter { !shouldStop($0) }
        lock.unlock()
        stopping.values.forEach { $0.pipe.terminate() }
    }

    /// The process for `options`, started if needed; `nil` after `shutdown`.
    private func entry(for options: RenderOptions) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard !isShutDown else { return nil }
        let now = ContinuousClock.now
        if var entry = entries[options] {
            entry.lastUse = now
            entries[options] = entry
            return entry
        }
        if entries.count >= maxProcesses, let (key, oldest) = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries[key] = nil
            evicted.insert(key)
            oldest.pipe.terminate()
        }
        let entry = Entry(
            pipe: PlantUMLPipe(toolchain: toolchain, options: options),
            queue: DispatchQueue(label: "pumlpad.plantuml.\(options.format.rawValue)"),
            lastUse: now
        )
        entries[options] = entry
        return entry
    }
}
