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
///   from the menu (View › Developer); `isVisible` tells whether it was
///   open.
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
            && inspectorClass.instancesRespond(to: visibleGetter)
    }

    /// Opens `panel` for the page; false when WebKit can't.
    @MainActor @discardableResult
    static func show(_ panel: Panel, for webView: WKWebView) -> Bool {
        guard let inspector = inspector(of: webView) else { return false }
        let selector = selector(for: panel)
        guard inspector.responds(to: selector) else { return false }
        let wasVisible = isVisible(inspector)
        inspector.perform(selector)
        // Opening, the inspector shows its last tab once loaded, over the
        // console asked for: asked again then (see `consoleRetries`).
        if panel == .console, !wasVisible {
            Task { @MainActor [weak webView] in
                for delay in consoleRetries {
                    try? await Task.sleep(for: delay)
                    guard let webView, let current = Self.inspector(of: webView), isVisible(current) else { return }
                    current.perform(selector)
                }
            }
        }
        return true
    }

    /// After the inspector opened for its console: long enough for it to
    /// load (a few tenths of a second), short enough not to undo a tab the
    /// user picks afterwards.
    static let consoleRetries: [Duration] = [.milliseconds(400), .milliseconds(1200)]

    @MainActor
    private static func inspector(of webView: WKWebView) -> NSObject? {
        guard webView.responds(to: inspectorGetter) else { return nil }
        return webView.perform(inspectorGetter)?.takeUnretainedValue() as? NSObject
    }

    private static let visibleGetter = NSSelectorFromString("isVisible")

    /// Whether the inspector is open (false when WebKit can't tell).
    @MainActor
    private static func isVisible(_ inspector: NSObject) -> Bool {
        guard inspector.responds(to: visibleGetter) else { return false }
        return inspector.value(forKey: "visible") as? Bool ?? false // not shown
    }
}
