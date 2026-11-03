import AppKit

/// Horizontal swipes (two fingers on a trackpad, one finger on a Magic Mouse)
/// seen before the views under the mouse get them. The handler decides on the
/// first event of a gesture; when it acts, the whole gesture (momentum
/// included) is kept from the views. Deciding later is not possible: a view
/// that got the start of a gesture (a list, the spaces' page controller) and
/// never its end can crash the app.
@MainActor
final class HorizontalSwipeMonitor {
    enum Direction {
        case fingersRight
        case fingersLeft
    }

    private var monitor: Any?
    private var isSwallowing = false

    /// `accepts`: whether a gesture starting with this event concerns the
    /// caller (its window, its area). `handler`: returns true when it acted.
    func start(
        accepts: @escaping @MainActor (NSEvent) -> Bool,
        handler: @escaping @MainActor (Direction) -> Bool
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.process(event, accepts: accepts, handler: handler) ? nil : event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the event is kept from the views.
    private func process(
        _ event: NSEvent,
        accepts: (NSEvent) -> Bool,
        handler: (Direction) -> Bool
    ) -> Bool {
        // Mouse wheels without phases are plain scrolling.
        guard !event.phase.isEmpty || !event.momentumPhase.isEmpty else { return false }

        if event.phase.contains(.mayBegin) {
            isSwallowing = false
            return false
        }
        guard event.phase.contains(.began) else { return isSwallowing }

        isSwallowing = false
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        // Mostly vertical (or no direction yet): scrolling, left to the views.
        guard abs(deltaX) > abs(deltaY), accepts(event) else { return false }
        // With natural scrolling, content follows the fingers: fingers moving
        // right give positive deltas.
        let fingersRight = event.isDirectionInvertedFromDevice ? deltaX > 0 : deltaX < 0
        isSwallowing = handler(fingersRight ? .fingersRight : .fingersLeft)
        return isSwallowing
    }
}
