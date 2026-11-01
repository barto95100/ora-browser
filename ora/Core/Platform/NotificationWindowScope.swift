import AppKit

/// Menu commands are posted as notifications that every browser window
/// observes. The command names its window (`NSApp.keyWindow` when it is
/// chosen) as the notification's object, and only that window acts on it.
enum NotificationWindowScope {
    /// Whether a notification whose object is `target` is meant for the view
    /// shown in `window`. A view that does not know its window yet stands for
    /// the key window. A notification without a target window concerns none.
    static func concerns(target: Any?, window: NSWindow?, keyWindow: NSWindow?) -> Bool {
        guard let target = target as? NSWindow, let window = window ?? keyWindow else { return false }
        return target === window
    }
}
