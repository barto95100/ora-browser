//
//  SidebarHeader.swift
//  ora
//

import AppKit
import SwiftUI

struct SidebarHeader: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toolbarManager: ToolbarManager

    private var sidebarIcon: String {
        sidebarManager.sidebarPosition == .secondary ? "sidebar.right" : "sidebar.left"
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarManager.sidebarPosition != .secondary, !appState.isFullscreen {
                WindowControls(isFullscreen: appState.isFullscreen)
                    .frame(height: 30)
            }

            // Next to the window buttons, like Arc and Safari (the address bar
            // shows it only while the sidebar is hidden).
            if !toolbarManager.isToolbarHidden, sidebarManager.sidebarPosition == .primary {
                URLBarButton(
                    systemName: sidebarIcon,
                    isEnabled: true,
                    foregroundColor: theme.foreground.opacity(0.7),
                    action: { sidebarManager.toggleSidebar() }
                )
                .modifier(TitleBarHint(
                    text: "Toggle Sidebar (\(KeyboardShortcuts.App.toggleSidebar.currentChord.display))"
                ))
                Spacer()
            }

            if toolbarManager.isToolbarHidden {
                HStack(spacing: 0) {
                    if sidebarManager.sidebarPosition == .primary {
                        URLBarButton(
                            systemName: sidebarIcon,
                            isEnabled: true,
                            foregroundColor: theme.foreground.opacity(0.7),
                            action: { sidebarManager.toggleSidebar() }
                        )
                        .oraShortcutHelp("Toggle Sidebar", for: KeyboardShortcuts.App.toggleSidebar)
                        Spacer()
                    }

                    URLBarButton(
                        systemName: "chevron.left",
                        isEnabled: tabManager.activeTab?.canGoBack ?? false,
                        foregroundColor: theme.foreground.opacity(0.7),
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.goBack()
                            }
                        }
                    )
                    .oraShortcutHelp("Go Back", for: KeyboardShortcuts.Navigation.back)

                    URLBarButton(
                        systemName: "chevron.right",
                        isEnabled: tabManager.activeTab?.canGoForward ?? false,
                        foregroundColor: theme.foreground.opacity(0.7),
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.goForward()
                            }
                        }
                    )
                    .oraShortcutHelp("Go Forward", for: KeyboardShortcuts.Navigation.forward)

                    URLBarButton(
                        systemName: "arrow.clockwise",
                        isEnabled: tabManager.activeTab != nil,
                        foregroundColor: theme.foreground.opacity(0.7),
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.reload()
                            }
                        }
                    )
                    .oraShortcutHelp("Reload This Page", for: KeyboardShortcuts.Navigation.reload)

                    if sidebarManager.sidebarPosition == .secondary {
                        Spacer()
                        URLBarButton(
                            systemName: sidebarIcon,
                            isEnabled: true,
                            foregroundColor: theme.foreground.opacity(0.7),
                            action: { sidebarManager.toggleSidebar() }
                        )
                        .oraShortcutHelp("Toggle Sidebar", for: KeyboardShortcuts.App.toggleSidebar)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
    }
}

/// A tooltip shown by Ora: macOS shows none in the title bar area, where the
/// window buttons and this one are. In its own small window, so a narrow
/// sidebar does not cut it.
private struct TitleBarHint: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if isHovering { isShown = true }
                    }
                } else {
                    isShown = false
                }
            }
            .background(TitleBarHintAnchor(text: text, isShown: isShown))
    }
}

/// Places the hint's window under the view it describes.
private struct TitleBarHintAnchor: NSViewRepresentable {
    let text: String
    let isShown: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isShown {
            context.coordinator.show(text, below: nsView)
        } else {
            context.coordinator.hide()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hide()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var panel: NSPanel?

        func show(_ text: String, below view: NSView) {
            guard let window = view.window else { return }
            let label = NSHostingView(rootView: TitleBarHintLabel(text: text))
            label.frame.size = label.fittingSize
            let panel = panel ?? Self.makePanel()
            self.panel = panel
            panel.contentView = label
            let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
            let origin = NSPoint(x: anchor.minX, y: anchor.minY - label.frame.height - 6)
            panel.setFrame(NSRect(origin: origin, size: label.frame.size), display: true)
            if panel.parent == nil {
                window.addChildWindow(panel, ordered: .above)
            }
            panel.orderFront(nil)
        }

        func hide() {
            guard let panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }

        private static func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            return panel
        }
    }
}

private struct TitleBarHintLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .fixedSize()
    }
}
