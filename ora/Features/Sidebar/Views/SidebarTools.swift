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

    static func isNormal(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return normal.contains(window)
    }
}
