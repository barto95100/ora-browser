import AppKit
@testable import Ombre
import Testing

/// The shared "the mouse has moved" helper (INT-16).
@MainActor
struct MouseMovedMonitorTests {
    private final class FakeMonitoring: EventMonitoring {
        var handlers: [(NSEvent) -> NSEvent?] = []
        private(set) var removed = 0

        func addLocalMonitor(
            matching _: NSEvent.EventTypeMask,
            handler: @escaping (NSEvent) -> NSEvent?
        ) -> Any? {
            handlers.append(handler)
            return NSObject()
        }

        func removeMonitor(_: Any) {
            removed += 1
        }
    }

    private func moveEvent() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
    }

    @Test func itAnswersTheFirstMoveOnceThenStops() throws {
        let monitoring = FakeMonitoring()
        let monitor = MouseMovedMonitor(monitoring: monitoring)
        var moves = 0
        monitor.start { moves += 1 }
        #expect(monitor.isWatching)

        let event = try moveEvent()
        #expect(monitoring.handlers.last?(event) === event)
        #expect(moves == 1)
        #expect(!monitor.isWatching)
        #expect(monitoring.removed == 1)
    }

    /// Started again, or stopped: never two monitors, none left behind.
    @Test func itNeverLeavesAMonitorBehind() {
        let monitoring = FakeMonitoring()
        var monitor: MouseMovedMonitor? = MouseMovedMonitor(monitoring: monitoring)
        monitor?.start {}
        monitor?.start {}
        #expect(monitoring.removed == 1)
        monitor?.stop()
        #expect(monitoring.removed == 2)
        monitor?.start {}
        monitor = nil
        #expect(monitoring.removed == 3)
    }
}
