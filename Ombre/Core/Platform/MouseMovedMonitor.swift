import AppKit

/// The first mouse move after `start`: hover effects wait for it, so a list
/// shown under a still pointer doesn't select the row under it. One shared
/// helper instead of a monitor copied in each view; it removes itself after
/// the move, at `stop`, or when it goes.
@MainActor
final class MouseMovedMonitor {
    /// Also used by deinit, which isn't on the main actor: only read there.
    private nonisolated(unsafe) let monitoring: EventMonitoring
    private nonisolated(unsafe) var monitor: Any?

    init(monitoring: EventMonitoring = SystemEventMonitoring()) {
        self.monitoring = monitoring
    }

    var isWatching: Bool {
        monitor != nil
    }

    func start(_ moved: @escaping @MainActor () -> Void) {
        stop()
        monitor = monitoring.addLocalMonitor(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated {
                self?.stop()
                moved()
            }
            return event
        }
    }

    func stop() {
        if let monitor { monitoring.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        if let monitor { monitoring.removeMonitor(monitor) }
    }
}
