/// Runs the live preview render after typing pauses, one render at a time.
///
/// Edits made while a render is running are collapsed into a single follow-up render
/// of the latest text, so the preview never falls behind by more than one render.
@MainActor
public final class RenderScheduler {
    private let debounce: Duration
    private var pending: (@MainActor () async -> Void)?
    private var timer: Task<Void, Never>?
    private var running = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(debounce: Duration) {
        self.debounce = debounce
    }

    /// Replaces any job that has not started yet with `job`.
    public func schedule(_ job: @escaping @MainActor () async -> Void) {
        pending = job
        timer?.cancel()
        timer = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.runPending()
        }
    }

    /// Skips the debounce, e.g. when a document opens.
    public func scheduleNow(_ job: @escaping @MainActor () async -> Void) {
        pending = job
        timer?.cancel()
        timer = Task { [weak self] in await self?.runPending() }
    }

    /// Drops the job that has not started yet, e.g. when the window closes. A running one finishes.
    public func cancel() {
        pending = nil
        timer?.cancel()
        timer = nil
        if !running { resumeIdleWaiters() }
    }

    var isIdle: Bool { !running && pending == nil }

    func waitUntilIdle() async {
        guard !isIdle else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func runPending() async {
        guard !running else { return }
        running = true
        while let job = pending {
            pending = nil
            await job()
        }
        running = false
        resumeIdleWaiters()
    }

    private func resumeIdleWaiters() {
        idleWaiters.forEach { $0.resume() }
        idleWaiters.removeAll()
    }
}
