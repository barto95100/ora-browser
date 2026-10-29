import SwiftUI

struct BrowserSplitView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toolbarManager: ToolbarManager
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var privacyMode: PrivacyMode

    private var targetSide: SplitSide {
        sidebarManager.sidebarPosition == .primary ? .primary : .secondary
    }

    private var splitFraction: FractionHolder {
        sidebarManager.sidebarPosition == .primary
            ? sidebarManager.currentFraction
            : sidebarManager.currentFraction.inverted()
    }

    /// Minimum share of the window for the sidebar pane and the content pane.
    private func minimumFractions(windowWidth: CGFloat) -> (primary: CGFloat, secondary: CGFloat) {
        let sidebar = SidebarLayout.minimumFraction(forWindowWidth: windowWidth)
        let content = 1 - SidebarLayout.maximumFraction
        return sidebarManager.sidebarPosition == .primary ? (sidebar, content) : (content, sidebar)
    }

    private var prioritySide: SplitSide {
        sidebarManager.sidebarPosition == .primary ? .primary : .secondary
    }

    private var dragToHidePFlag: Bool {
        sidebarManager.sidebarPosition == .primary
    }

    private var dragToHideSFlag: Bool {
        sidebarManager.sidebarPosition == .secondary
    }

    var body: some View {
        GeometryReader { geometry in
            let minimums = minimumFractions(windowWidth: geometry.size.width)
            HSplit(left: { primaryPane() }, right: { secondaryPane() })
                .hide(sidebarManager.hiddenSidebar)
                .splitter { Splitter.invisible() }
                .fraction(splitFraction)
                .constraints(
                    minPFraction: minimums.primary,
                    minSFraction: minimums.secondary,
                    priority: prioritySide,
                    dragToHideP: dragToHidePFlag,
                    dragToHideS: dragToHideSFlag
                )
                .styling(hideSplitter: true)
        }
    }

    private func primaryPane() -> some View {
        paneContent(
            isSidebarPane: sidebarManager.sidebarPosition == .primary,
            isOtherPaneHidden: sidebarManager.hiddenSidebar.side == .secondary
        )
    }

    private func secondaryPane() -> some View {
        paneContent(
            isSidebarPane: sidebarManager.sidebarPosition == .secondary,
            isOtherPaneHidden: sidebarManager.hiddenSidebar.side == .primary
        )
    }

    @ViewBuilder
    private func paneContent(isSidebarPane: Bool, isOtherPaneHidden: Bool) -> some View {
        if isSidebarPane, !isOtherPaneHidden {
            SidebarView()
        } else {
            contentView()
        }
    }

    private func contentView() -> some View {
        Group {
            if appState.showSettings, !privacyMode.isPrivate {
                BrowserContentContainer {
                    InWindowSettingsView()
                }
            } else if let activeTab = tabManager.activeTab {
                BrowserContentContainer {
                    BrowserWebContentView(tab: activeTab)
                }
            } else {
                BrowserContentContainer {
                    HomeView()
                }
            }
        }
        .toast(manager: toastManager)
        // Picking a tab leaves the settings.
        .onChange(of: tabManager.activeTab?.id) { appState.showSettings = false }
    }
}
