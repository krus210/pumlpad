import Foundation
import os

/// Logs how long the app took to show its first diagram; `scripts/bench-launch.sh` reads it with
/// `log show --predicate 'subsystem == "com.sskorolev.pumlpad"'`.
@MainActor
enum LaunchTiming {
    private static let logger = Logger(subsystem: "com.sskorolev.pumlpad", category: "performance")
    private static var reported = false

    static func firstPreviewShown() {
        guard !reported, let seconds = secondsSinceProcessStart() else { return }
        reported = true
        logger.notice("First preview \(Int(seconds * 1000)) ms after launch")
    }

    /// From the kernel's record of when this process started, so it includes AppKit's own start-up.
    private static func secondsSinceProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date().timeIntervalSince1970 - (Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }
}
