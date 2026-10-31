import AppKit

/// Local `NSEvent` monitors see the events of every window of the app. A
/// monitor installed for one browser window must only act on the events of
/// that window: Return typed in another window (or in an extension popup,
/// which is a child window) must not confirm this window's dialog.
enum EventWindowScope {
    /// Whether an event that happened in `eventWindow` concerns `window`.
    /// Only the very same window does: no event without a window, no child
    /// window (popovers, extension popups, sheets).
    static func concerns(eventWindow: NSWindow?, window: NSWindow?) -> Bool {
        guard let eventWindow, let window else { return false }
        return eventWindow === window
    }
}
