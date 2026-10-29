import AppKit
import SwiftUI

/// Downloads, notes and tasks in one button, for a narrow sidebar. Like the
/// downloads button, a ring around it fills as downloads go on.
struct SidebarToolsMenu: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    private var isDownloading: Bool {
        !downloadManager.activeDownloads.isEmpty
    }

    /// Progress of all downloads going on (0...1).
    private var totalProgress: Double {
        let active = downloadManager.activeDownloads
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { $0 + $1.displayProgress } / Double(active.count)
    }

    var body: some View {
        // A button opening a menu: a SwiftUI `Menu` would not draw the ring.
        Button(action: showMenu) {
            ZStack {
                if isDownloading {
                    Circle()
                        .stroke(theme.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: totalProgress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: totalProgress)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(theme.accent)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 28, height: 32)
            .background(isHovered ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Downloads, Notes, Tasks")
    }

    private func showMenu() {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        let downloadsTitle = isDownloading
            ? "Downloads (\(Int((totalProgress * 100).rounded())) %)"
            : "Downloads"
        menu.addItem(ClosureMenuItem(downloadsTitle, symbol: "arrow.down.circle") {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                downloadManager.isShowingDownloadsHistory.toggle()
            }
        })
        menu.addItem(ClosureMenuItem("Notes", symbol: "note.text", key: "n") {
            appState.showLauncher = false
            appState.showHistory = false
            appState.showNotes.toggle()
        })
        let tasks = ClosureMenuItem("Tasks", symbol: "checklist", key: "t") {
            appState.showTasks.toggle()
        }
        tasks.isEnabled = tabManager.activeTab != nil
        menu.addItem(tasks)
        menu.autoenablesItems = false
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

/// A menu item running a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    /// `key`: the shortcut shown (⌥⌘), the app menu runs it.
    init(_ title: String, symbol: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = [.command, .option]
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}
