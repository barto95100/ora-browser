import AppKit

/// Mouse button presses in the app, seen before the view under the mouse gets
/// them: web pages take clicks before SwiftUI gestures can. The event always
/// goes on to its view.
@MainActor
final class MouseDownMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping @MainActor (NSEvent) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
