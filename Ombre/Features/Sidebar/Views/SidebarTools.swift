import AppKit
import SwiftUI

/// Sidebar bottom button: the settings, in the window (see `InWindowSettingsView`).
struct SidebarSettingsButton: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            appState.showSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(appState.showSettings ? theme.accent : .secondary)
                .frame(width: 28, height: 32)
                .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Settings (⌘,)")
    }
}

/// Normal browser windows: ⌘, shows the settings in them; elsewhere
/// (private window, settings or passwords window) it opens the settings window.
enum BrowserWindows {
    static let normal = NSHashTable<NSWindow>.weakObjects()
    /// All browser windows, normal and private.
    static let browsing = NSHashTable<NSWindow>.weakObjects()

    /// The browser window that asks to confirm quitting: the key one, else
    /// the frontmost, else a minimized one. Only open windows: one closed but
    /// not yet freed, or hidden with the app, could not show the question
    /// and quitting would wait forever. None when only the settings or
    /// passwords window is open (or the app is hidden): the app quits now.
    static func quitTarget(
        keyWindow: NSWindow?,
        orderedWindows: [NSWindow],
        browserWindows: [NSWindow],
        isOpen: (NSWindow) -> Bool = { $0.isVisible || $0.isMiniaturized }
    ) -> NSWindow? {
        let candidates = browserWindows.filter(isOpen)
        let isCandidate = { (window: NSWindow) in candidates.contains { $0 === window } }
        if let keyWindow, isCandidate(keyWindow) { return keyWindow }
        return orderedWindows.first(where: isCandidate) ?? candidates.first
    }

    static func isNormal(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return normal.contains(window)
    }

    /// The normal window in front: the key one, or the frontmost (from the
    /// separate settings window, say).
    static var front: NSWindow? {
        if isNormal(NSApp.keyWindow) { return NSApp.keyWindow }
        return NSApp.orderedWindows.first { isNormal($0) }
    }

    /// Opens the settings at a section, in the front normal window.
    static func showSettings(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsContentView.selectedTabDefaultsKey)
        if let window = front {
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .showSettings, object: window, userInfo: ["open": true])
        }
    }

    /// Asks the front normal window to delete a space (from the settings).
    static func deleteSpace(_ spaceID: UUID) {
        if let window = front {
            NotificationCenter.default.post(name: .deleteSpace, object: window, userInfo: ["spaceID": spaceID])
        }
    }

    /// Asks the front normal window to import from another browser.
    static func showImport() {
        if let window = front {
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .showImport, object: window)
        }
    }
}
