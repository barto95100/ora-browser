import AppKit
import SwiftUI

/// Sidebar bottom button: the settings window (see `SettingsWindow`).
struct SidebarSettingsButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false

    var body: some View {
        Button {
            SettingsWindow.show(opening: openWindow)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 32)
                .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Settings (⌘,)")
    }
}

/// The browser windows, normal and private.
@MainActor
enum BrowserWindows {
    static let normal = NSHashTable<NSWindow>.weakObjects()
    /// Each normal window's tab manager (for agents, see `AgentControl`).
    static let tabManagers = NSMapTable<NSWindow, TabManager>.weakToWeakObjects()
    /// All browser windows, normal and private.
    static let browsing = NSHashTable<NSWindow>.weakObjects()

    /// The tab manager of the normal window in front.
    static var frontTabManager: TabManager? {
        front.flatMap { tabManagers.object(forKey: $0) }
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

    /// Asks the front normal window to delete a space (from the settings).
    static func deleteSpace(_ spaceID: UUID) {
        if let window = front {
            NotificationCenter.default.post(name: .deleteSpace, object: window, userInfo: ["spaceID": spaceID])
        }
    }

    /// Asks the front normal window for a new space's editor (from the
    /// settings, which may be a window of their own, without its managers).
    static func newSpace() {
        if let window = front {
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .newSpace, object: window)
        }
    }

    /// Asks the front normal window to import from another browser.
    static func showImport(from source: ImportSource) {
        if let window = front {
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .showImport, object: window, userInfo: ["source": source])
        }
    }
}
