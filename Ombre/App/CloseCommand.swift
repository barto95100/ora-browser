import AppKit

/// What ⌘W closes (INT-09): in a browser window, its tab; in any other
/// window (settings, passwords, a sign-in popup, licenses), the window.
enum CloseCommand {
    enum Action: Equatable {
        case closeTab
        case closeWindow
        case nothing
    }

    static func action(hasKeyWindow: Bool, isBrowserWindow: Bool) -> Action {
        guard hasKeyWindow else { return .nothing }
        return isBrowserWindow ? .closeTab : .closeWindow
    }

    /// ⌘W, from the menu.
    @MainActor static func closeTab() {
        let keyWindow = NSApp.keyWindow
        let isBrowserWindow = keyWindow.map { BrowserWindows.browsing.contains($0) } ?? false
        switch action(hasKeyWindow: keyWindow != nil, isBrowserWindow: isBrowserWindow) {
        case .closeTab:
            NotificationCenter.default.post(name: .closeActiveTab, object: keyWindow)
        case .closeWindow:
            keyWindow?.performClose(nil)
        case .nothing:
            break
        }
    }
}
