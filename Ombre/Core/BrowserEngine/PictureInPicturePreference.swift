import WebKit

/// Picture in Picture for pages: the one private WebKit setting Ombre ships
/// (see CLAUDE.md). On macOS it is off unless set, and no public setting
/// exists (`WKWebViewConfiguration.allowsPictureInPictureMediaPlayback` is
/// iOS only): without it, a page's own button and the automatic Picture in
/// Picture on a tab switch both get "NotSupportedError".
///
/// Set only if WebKit still has it, so a macOS without it changes nothing
/// and never crashes; `PictureInPicturePreferenceTests` fails then, to tell.
enum PictureInPicturePreference {
    static let key = "allowsPictureInPictureMediaPlayback"
    private static let setter = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")

    /// Whether this WebKit still has the setting.
    static func isAvailable(in preferences: WKPreferences) -> Bool {
        preferences.responds(to: setter)
    }

    static func enable(in preferences: WKPreferences) {
        guard isAvailable(in: preferences) else { return }
        preferences.setValue(true, forKey: key)
    }
}
