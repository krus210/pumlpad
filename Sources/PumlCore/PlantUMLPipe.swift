import Foundation

public enum OutputFormat: String, Hashable, Sendable {
    case svg, png
}

public enum RenderFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case launchFailed(String)
    case timedOut
    /// The process was gone before it got the diagram.
    case processExited(String)
    /// The process died while rendering the diagram, e.g. on a recursive `!include`.
    case crashed(String)
    /// The process was shut down while the render was waiting for it.
    case stopped

    public var description: String {
        switch self {
        case .launchFailed(let reason): "Could not start PlantUML: \(reason)"
        case .timedOut: "PlantUML took too long and was restarted"
        case .processExited(let stderr): "PlantUML stopped unexpectedly. \(stderr)"
        case .crashed(let stderr): "PlantUML crashed on this diagram. \(stderr)"
        case .stopped: "PlantUML was stopped"
        }
    }
}

/// What `-pipe -pipenostderr` writes for one diagram before the delimiter: the image, or a
/// one-line `-stdrpt:2` error report instead of the image.
enum PipeReply: Equatable {
    case image(Data)
    case report(String)

    init(_ output: Data) {
        // An empty diagram's image comes after a blank line.
        let start = output.firstIndex { ![0x0A, 0x0D, 0x20, 0x09].contains($0) } ?? output.endIndex
        let content = output[start...]
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if content.first == UInt8(ascii: "<") || content.starts(with: pngSignature) {
            self = .image(Data(content))
        } else {
            self = .report(String(decoding: content, as: UTF8.self))
        }
    }
}

/// One long-lived `java -jar plantuml.jar -pipe` process.
///
/// Starting Java takes 0.5–1.5 s, while a running process renders a diagram in 10–150 ms.
/// Diagrams are written to stdin one at a time; for each one stdout carries the image or an error
/// report, then the `-pipedelimitor` line. stderr only gets JVM noise, but it is read all the time:
/// once its 64 KB pipe buffer fills up, Java blocks.
///
/// The process runs in its own process group, so stopping it also stops the Graphviz `dot`
/// it may be running. It gets a minimal environment and a PlantUML security profile:
/// `SANDBOX` (no files, no network) unless the document's folder is trusted.
final class PlantUMLPipe: @unchecked Sendable {
    private struct Child {
        let pid: pid_t
        let input: Int32
        let output: Int32
        let errors: Int32
    }

    private let toolchain: Toolchain
    private let options: RenderOptions
    private let delimiter = "__PUMLPAD_END_\(UUID().uuidString)__"
    /// Serialises renders and the cleanup of a finished process.
    private let renderLock = NSLock()
    /// Guards `child` and `isStopped`; never held while waiting for the process.
    private let stateLock = NSLock()
    private var child: Child?
    private var isStopped = false

    init(toolchain: Toolchain, options: RenderOptions) {
        self.toolchain = toolchain
        self.options = options
    }

    deinit {
        if let child { Self.discard(child) }
    }

    var processIdentifier: pid_t? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return child?.pid
    }

    /// Blocks until PlantUML answers. On timeout or crash the process is dropped and the next
    /// render starts a fresh one. A process found dead before it got the diagram is replaced at
    /// once; one that died on the diagram is not, since the diagram would kill the new one too.
    func render(_ source: String, timeout: TimeInterval) throws -> PipeReply {
        renderLock.lock()
        defer { renderLock.unlock() }
        do {
            return try renderOnce(source, timeout: timeout)
        } catch RenderFailure.processExited {
            // Killed between renders, or the Mac slept.
            return try renderOnce(source, timeout: timeout)
        }
    }

    /// Stops the process without waiting for a render in progress: that render sees the process
    /// die and fails with `RenderFailure.stopped`. Later renders fail the same way.
    func terminate() {
        stateLock.lock()
        isStopped = true
        let pid = child?.pid
        stateLock.unlock()
        if let pid { kill(-pid, SIGKILL) }
        // Descriptors are closed once no render uses them.
        DispatchQueue.global(qos: .utility).async { [self] in
            renderLock.lock()
            defer { renderLock.unlock() }
            takeChild().map(Self.discard)
        }
    }

    private func renderOnce(_ source: String, timeout: TimeInterval) throws -> PipeReply {
        let child = try runningChild()
        var errors = ErrorStream(descriptor: child.errors)
        var delivered = false
        do {
            let deadline = Date(timeIntervalSinceNow: timeout)
            var payload = Data(source.utf8)
            payload.append(0x0A)
            try write(payload, to: child, deadline: deadline, errors: &errors)
            delivered = true
            return PipeReply(try readReply(from: child, deadline: deadline, errors: &errors))
        } catch {
            takeChild().map(Self.discard)
            stateLock.lock()
            let stopped = isStopped
            stateLock.unlock()
            if stopped { throw RenderFailure.stopped }
            switch error as? RenderFailure {
            case .processExited(let stderr) where delivered: throw RenderFailure.crashed(stderr)
            case let failure?: throw failure
            case nil: throw RenderFailure.processExited(errors.text)
            }
        }
    }

    private func runningChild() throws -> Child {
        stateLock.lock()
        defer { stateLock.unlock() }
        if isStopped { throw RenderFailure.stopped }
        if let child { return child }
        let child = try launch()
        self.child = child
        return child
    }

    private func takeChild() -> Child? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let taken = child
        child = nil
        return taken
    }

    // MARK: Process

    private func launch() throws -> Child {
        var arguments = [
            toolchain.java.path,
            "-Djava.awt.headless=true",
            // One diagram at a time: the serial collector and the C1 compiler start faster
            // and keep the resident size around 280 MB instead of ~390 MB.
            "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1", "-Xmx1g",
            // PNG images larger than 4096 px are cropped by default.
            "-DPLANTUML_LIMIT_SIZE=16384",
        ]
        arguments += securityArguments
        arguments += [
            "-jar", toolchain.jar.path,
            "-pipe", "-t\(options.format.rawValue)", "-pipedelimitor", delimiter, "-charset", "UTF-8",
            // Errors come on stdout as `-stdrpt:2` reports instead of pictures.
            "-pipenostderr", "-stdrpt:2",
        ]
        if options.darkMode { arguments.append("--dark-mode") }
        if toolchain.dot == nil { arguments.append("-Playout=smetana") }
        return try Self.spawn(arguments, environment: environment, directory: options.workingDirectory.path)
    }

    /// `LEGACY`, PlantUML's default, lets a diagram read any file (`!include`, `%load_json`,
    /// `<img:…>`) and send it anywhere with `!include http://…`.
    private var securityArguments: [String] {
        let folder = options.workingDirectory.path
        // `plantuml.allowlist.path` is a list separated by ":", so a folder named "x:" would
        // allowlist other folders. Such a folder is never trusted (Services refuses it too).
        guard options.trustsLocalFiles, !folder.contains(":") else { return ["-DPLANTUML_SECURITY_PROFILE=SANDBOX"] }
        // Files under the document's folder; PlantUML compares paths as written, so `../` still
        // leaves it. No URL is allowlisted, so nothing read can leave the Mac.
        return ["-DPLANTUML_SECURITY_PROFILE=ALLOWLIST", "-Dplantuml.allowlist.path=\(folder)"]
    }

    /// Only what Java and Graphviz need: no `JAVA_TOOL_OPTIONS`, `PLANTUML_*` or secrets.
    private var environment: [String: String] {
        var environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": "en_US.UTF-8",
        ]
        environment["GRAPHVIZ_DOT"] = toolchain.dot?.path
        return environment
    }

    private static func spawn(_ arguments: [String], environment: [String: String], directory: String) throws -> Child {
        var input: [Int32] = [-1, -1]
        var output: [Int32] = [-1, -1]
        var errors: [Int32] = [-1, -1]
        guard pipe(&input) == 0, pipe(&output) == 0, pipe(&errors) == 0 else {
            let reason = String(cString: strerror(errno))
            (input + output + errors).filter { $0 >= 0 }.forEach { close($0) }
            throw RenderFailure.launchFailed(reason)
        }
        // The parent's ends must not leak into other processes.
        for descriptor in [input[1], output[0], errors[0]] { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors[1], STDERR_FILENO)
        posix_spawn_file_actions_addchdir_np(&actions, directory)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A new process group, led by Java, and no descriptors besides 0, 1 and 2.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp)
        // The child's ends now live in the child only.
        [input[0], output[1], errors[1]].forEach { close($0) }
        guard status == 0 else {
            [input[1], output[0], errors[0]].forEach { close($0) }
            throw RenderFailure.launchFailed(String(cString: strerror(status)))
        }
        // A write to a dead process must fail with EPIPE instead of killing the app with SIGPIPE.
        _ = fcntl(input[1], F_SETNOSIGPIPE, 1)
        for descriptor in [input[1], errors[0]] {
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        }
        return Child(pid: pid, input: input[1], output: output[0], errors: errors[0])
    }

    /// Kills the whole group (Java and any `dot`), reaps Java and closes the descriptors.
    private static func discard(_ child: Child) {
        kill(-child.pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(child.pid, &status, 0) == -1, errno == EINTR {}
        [child.input, child.output, child.errors].forEach { close($0) }
    }

    // MARK: I/O

    /// stderr read during one render; only its tail is kept, for error messages.
    private struct ErrorStream {
        let descriptor: Int32
        var isOpen = true
        var tail = Data()

        var text: String { String(decoding: tail, as: UTF8.self) }

        mutating func drain() {
            let capacity = 16 * 1024
            var chunk = [UInt8](repeating: 0, count: capacity)
            while true {
                let count = Darwin.read(descriptor, &chunk, capacity)
                if count > 0 {
                    tail.append(chunk, count: count)
                    if tail.count > capacity { tail.removeFirst(tail.count - capacity) }
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    if count == 0 { isOpen = false }
                    return
                }
            }
        }
    }

    private func write(_ payload: Data, to child: Child, deadline: Date, errors: inout ErrorStream) throws {
        var offset = 0
        while offset < payload.count {
            let written = payload.withUnsafeBytes { buffer in
                Darwin.write(child.input, buffer.baseAddress! + offset, buffer.count - offset)
            }
            if written > 0 {
                offset += written
                continue
            }
            guard written < 0, errno == EAGAIN || errno == EINTR else {
                throw RenderFailure.processExited(errors.text)
            }
            // stdin is full: Java is busy. Keep draining stderr so it can make progress.
            try wait(for: child.input, events: POLLOUT, deadline: deadline, errors: &errors)
        }
    }

    private func readReply(from child: Child, deadline: Date, errors: inout ErrorStream) throws -> Data {
        let marker = Data("\(delimiter)\n".utf8)
        let capacity = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: capacity)
        var reply = Data()
        while true {
            let searchStart = max(0, reply.count - capacity - marker.count)
            if let range = reply.range(of: marker, in: searchStart..<reply.count) {
                return reply.subdata(in: 0..<range.lowerBound)
            }
            try wait(for: child.output, events: POLLIN, deadline: deadline, errors: &errors)
            let count = Darwin.read(child.output, &chunk, capacity)
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else { throw RenderFailure.processExited(errors.text) }
            reply.append(chunk, count: count)
        }
    }

    /// Waits until `descriptor` is ready, draining stderr meanwhile.
    private func wait(for descriptor: Int32, events: Int32, deadline: Date, errors: inout ErrorStream) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw RenderFailure.timedOut }
            var descriptors = [
                pollfd(fd: descriptor, events: Int16(events), revents: 0),
                // poll skips negative descriptors: a closed stderr is no longer watched.
                pollfd(fd: errors.isOpen ? errors.descriptor : -1, events: Int16(POLLIN), revents: 0),
            ]
            let ready = poll(&descriptors, 2, Int32(min(remaining, 0.5) * 1000) + 1)
            if ready < 0, errno != EINTR {
                throw RenderFailure.processExited(String(cString: strerror(errno)))
            }
            if descriptors[1].revents != 0 { errors.drain() }
            if descriptors[0].revents != 0 { return }
        }
    }
}
