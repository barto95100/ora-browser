import WebKit

/// WebKit's Web Inspector inside Ombre, when Settings › General › "Allow Web
/// Inspector" is on: the fourth private WebKit API tolerated (see CLAUDE.md).
/// No public API gives it on macOS: `isInspectable` only lets Safari's
/// Develop menu inspect the page.
///
/// - The `developerExtrasEnabled` preference adds "Inspect Element" to the
///   page's context menu; the inspector opens docked in the window.
/// - Not in private windows (see `BrowserPage.inspectsInOmbre`).
/// - `_inspector` (`_WKInspector`) and its `show` and `showConsole` open it
///   from the menu (View › Developer).
///
/// Each is used only if WebKit still has it: a macOS without them changes
/// nothing and never crashes (the menu items do nothing then);
/// `WebInspectorTests` fails, to tell.
enum WebInspector {
    enum Panel {
        case inspector
        case console
    }

    static let preferenceKey = "developerExtrasEnabled"
    private static let preferenceSetter = NSSelectorFromString("_setDeveloperExtrasEnabled:")
    private static let preferenceGetter = NSSelectorFromString("_developerExtrasEnabled")
    private static let inspectorGetter = NSSelectorFromString("_inspector")
    static let inspectorClassName = "_WKInspector"

    private static func selector(for panel: Panel) -> Selector {
        switch panel {
        case .inspector: NSSelectorFromString("show")
        case .console: NSSelectorFromString("showConsole")
        }
    }

    /// Whether this WebKit still has the "Inspect Element" preference.
    static func hasPreference(in preferences: WKPreferences) -> Bool {
        preferences.responds(to: preferenceSetter) && preferences.responds(to: preferenceGetter)
    }

    /// Whether "Inspect Element" is in the context menu (nil without the
    /// preference).
    static func inspectsElements(in preferences: WKPreferences) -> Bool? {
        guard hasPreference(in: preferences) else { return nil }
        return preferences.value(forKey: preferenceKey) as? Bool
    }

    /// "Inspect Element" in the context menu, or not.
    static func allowInspectElement(_ allowed: Bool, in preferences: WKPreferences) {
        guard hasPreference(in: preferences) else { return }
        preferences.setValue(allowed, forKey: preferenceKey)
    }

    /// Whether this WebKit can still open the inspector and its console.
    static var canShowPanels: Bool {
        guard WKWebView.instancesRespond(to: inspectorGetter),
              let inspectorClass = NSClassFromString(inspectorClassName) as? NSObject.Type
        else { return false }
        return inspectorClass.instancesRespond(to: selector(for: .inspector))
            && inspectorClass.instancesRespond(to: selector(for: .console))
    }

    /// Opens `panel` for the page; false when WebKit can't.
    @MainActor @discardableResult
    static func show(_ panel: Panel, for webView: WKWebView) -> Bool {
        guard webView.responds(to: inspectorGetter),
              let inspector = webView.perform(inspectorGetter)?.takeUnretainedValue() as? NSObject
        else { return false }
        let selector = selector(for: panel)
        guard inspector.responds(to: selector) else { return false }
        inspector.perform(selector)
        return true
    }
}
