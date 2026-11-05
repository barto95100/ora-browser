import WebKit

/// Sharing a screen or a window with a page (`getDisplayMedia`): the second
/// private WebKit item Ombre ships (see CLAUDE.md, decided by Ludo). macOS has
/// no public way: WebKit asks through a private delegate method (see
/// `BrowserPage`), and its setting must stay on (it is by default: only read
/// here, never set). `ScreenSharingTests` fails when a WebKit drops either.
///
/// macOS's own picker (ScreenCaptureKit) then lets the user choose a screen
/// or a window, which grants the access: Ombre needs no Screen Recording
/// permission of its own, like Safari. Refused there, the page is told so.
enum ScreenSharing {
    static let preferenceKey = "screenCaptureEnabled"
    private static let getter = NSSelectorFromString("_screenCaptureEnabled")
    /// WebKit's private delegate method asking whether a page may share.
    static let delegateSelector = NSSelectorFromString(
        "_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:"
    )

    /// Whether WebKit still has the setting, and has it on.
    static func isEnabled(in preferences: WKPreferences) -> Bool {
        guard preferences.responds(to: getter) else { return false }
        return preferences.value(forKey: preferenceKey) as? Bool == true
    }

    /// WebKit's answers (`_WKDisplayCapturePermissionDecision`): refused, or
    /// the choice of a screen or a window offered to the user.
    enum Decision: Int {
        case deny = 0
        case screenPrompt = 1
    }
}
