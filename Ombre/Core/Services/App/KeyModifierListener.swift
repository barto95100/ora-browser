import Combine
import SwiftUI

/*
 * KeyModifierListener is an ObservableObject that monitors keyboard modifier key changes and global key down events.
 *
 * It sends each change of the modifier keys held through `modifierFlagsChanged` (not published: no view redraws for them).
 *
 * Additionally, it allows registering custom handlers for key down events using `registerKeyDownHandler`.
 * Handlers only receive the key down events of the listener's `window`.
 * If any registered handler returns true, the event is consumed and not propagated further.
 *
 *
 * Why not use onKeyPressed?
 *
 * SwiftUI's .onKeyPress modifier is attached to specific views and only triggers when that view has keyboard focus.
 * In contrast, KeyModifierListener uses NSEvent monitors to capture modifier flag changes and key down events
 * globally across the entire application,
 * regardless of focus. This enables app-wide keyboard shortcuts and consistent modifier state tracking.
 *
 * Also, it's not possible to use onKeyPressed to detect modifier key changes like if modifier is released.
 *
 * Usage:
 * let listener = KeyModifierListener()
 * @StateObject var keyListener = listener // In a SwiftUI View
 *
 * listener.registerKeyDownHandler { event in
 *     if event.modifierFlags.contains(.command) && event.keyCode == 12 { // Command + Q
 *         print("Command + Q pressed")
 *         return true // Consume the event
 *     }
 *     return false
 * }
 */

/// Adds and removes local event monitors; `NSEvent` in the app, a fake in tests.
protocol EventMonitoring {
    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    func removeMonitor(_ monitor: Any)
}

struct SystemEventMonitoring: EventMonitoring {
    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

final class KeyModifierListener: ObservableObject {
    /// The modifier keys held. Not published: the window's root view
    /// observes this object, and was redrawn at each ⌘, ⇧, ⌥ or ⌃.
    private(set) var modifierFlags = NSEvent.ModifierFlags([])
    /// Each change of the keys held, for the one view that needs it (the tab
    /// switcher, waiting for ⌃ to be released).
    let modifierFlagsChanged = PassthroughSubject<NSEvent.ModifierFlags, Never>()

    /// The browser window that owns this listener. Key down handlers only see
    /// the events typed in it (see `EventWindowScope`); none until it is known.
    weak var window: NSWindow?

    private let monitoring: EventMonitoring
    /// Removed with the listener: a closed window stops seeing the keys.
    private var monitors: [Any] = []

    init(monitoring: EventMonitoring = SystemEventMonitoring()) {
        self.monitoring = monitoring
        let flagsMonitor = monitoring.addLocalMonitor(matching: .flagsChanged) { [weak self] event in
            self?.flagsChanged(to: event.modifierFlags)
            return event
        }

        let keyDownMonitor = monitoring.addLocalMonitor(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleGlobalKeyDown(event) {
                return nil
            }
            return event
        }
        monitors = [flagsMonitor, keyDownMonitor].compactMap { $0 }
    }

    deinit {
        for monitor in monitors {
            monitoring.removeMonitor(monitor)
        }
    }

    /// Only the keys (not the device bits), and only on a change.
    func flagsChanged(to flags: NSEvent.ModifierFlags) {
        let keys = flags.intersection(.deviceIndependentFlagsMask)
        guard keys != modifierFlags else { return }
        modifierFlags = keys
        modifierFlagsChanged.send(keys)
    }

    typealias KeyDownHandler = (NSEvent) -> Bool

    private var keyDownHandlers: [KeyDownHandler] = []

    func registerKeyDownHandler(_ handler: @escaping KeyDownHandler) {
        keyDownHandlers.append(handler)
    }

    private func handleGlobalKeyDown(_ event: NSEvent) -> Bool {
        guard EventWindowScope.concerns(eventWindow: event.window, window: window) else { return false }
        for handler in keyDownHandlers {
            if handler(event) {
                return true
            }
        }
        return false
    }
}
