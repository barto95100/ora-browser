import Foundation

/// Coalesces bursts of progress notifications (one per received chunk, on any
/// thread) into a single main-actor update per interval. Nothing runs while no
/// notification arrives: no timer, no polling.
final class DownloadProgressThrottle: @unchecked Sendable {
    typealias Scheduler = (@escaping @MainActor () -> Void) -> Void

    private let lock = NSLock()
    private var isScheduled = false
    private let schedule: Scheduler
    private let action: @MainActor () -> Void

    /// - Parameters:
    ///   - interval: minimum time between two updates (0.25 s: about 4 updates per second).
    ///   - schedule: runs the update later; injectable for tests.
    init(
        interval: Duration = .milliseconds(250),
        schedule: Scheduler? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.action = action
        self.schedule = schedule ?? { work in
            Task { @MainActor in
                try? await Task.sleep(for: interval)
                work()
            }
        }
    }

    /// Safe to call from any thread, as often as needed.
    func signal() {
        lock.lock()
        let alreadyScheduled = isScheduled
        isScheduled = true
        lock.unlock()
        guard !alreadyScheduled else { return }

        schedule { [self] in
            lock.lock()
            isScheduled = false
            lock.unlock()
            action()
        }
    }
}
