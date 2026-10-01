import Testing
@testable import PumlCore

@MainActor
@Suite struct RenderSchedulerTests {
    @Test func burstOfEditsRendersOnce() async {
        let scheduler = RenderScheduler(debounce: .milliseconds(30))
        let log = Log()
        for index in 1...5 {
            scheduler.schedule { log.items.append("render \(index)") }
        }
        await scheduler.waitUntilIdle()
        #expect(log.items == ["render 5"])
    }

    @Test func editsDuringARenderCollapseIntoOneFollowUp() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(5))
        let log = Log()
        let gate = Gate()
        scheduler.scheduleNow {
            log.items.append("first")
            await gate.wait()
        }
        try await Task.sleep(for: .milliseconds(30))
        scheduler.schedule { log.items.append("second") }
        scheduler.schedule { log.items.append("third") }
        try await Task.sleep(for: .milliseconds(30))
        #expect(log.items == ["first"])

        gate.open()
        await scheduler.waitUntilIdle()
        #expect(log.items == ["first", "third"])
    }
}

@MainActor
private final class Log {
    var items: [String] = []
}

@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
