import AppKit

/// A password action that failed, with the Keychain's reason.
@MainActor
enum PasswordFailureAlert {
    static func present(title: String, error: Error, in window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        // On the window itself, not on a sheet it shows; never on a closed one.
        if let window = window?.sheetParent ?? window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
