import SwiftUI

/*
 * KeyModifierListener is an ObservableObject that monitors keyboard modifier key changes and global key down events.
 *
 * It publishes the current modifier flags via the `modifierFlags` property, which updates whenever modifier keys are pressed or released.
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

final class KeyModifierListener: ObservableObject {
    @Published var modifierFlags = NSEvent.ModifierFlags([])

    /// The browser window that owns this listener. Key down handlers only see
    /// the events typed in it (see `EventWindowScope`); none until it is known.
    weak var window: NSWindow?

    init() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.modifierFlags = event.modifierFlags
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleGlobalKeyDown(event) {
                return nil
            }
            return event
        }
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
