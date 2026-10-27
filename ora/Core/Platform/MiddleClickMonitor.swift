import AppKit

/// Middle-button (mouse wheel) clicks, which SwiftUI has no gesture for. The
/// handler runs when the button is released and returns whether it handled
/// the click (the event then goes no further).
@MainActor
final class MiddleClickMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping @MainActor () -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2 else { return event }
            let handled = MainActor.assumeIsolated { handler() }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
