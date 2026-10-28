import SwiftUI

struct BrowserWebContentView: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var toolbarManager: ToolbarManager
    @EnvironmentObject private var mediaController: MediaController
    let tab: Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !toolbarManager.isToolbarHidden {
                URLBar(
                    onSidebarToggle: {
                        NotificationCenter.default.post(
                            name: .toggleSidebar, object: nil
                        )
                    }
                )
                .zIndex(1)
                .transition(
                    .asymmetric(
                        insertion: .push(from: .top),
                        removal: .push(from: .bottom)
                    )
                )
            }

            ZStack {
                // Pages of tabs whose video is in Picture in Picture stay in the
                // window, hidden behind the current page, so "back to tab" works.
                ForEach(parkedTabs, id: \.id) { parkedTab in
                    if let page = parkedTab.browserPage {
                        ParkedBrowserPageView(page: page)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                TabPanelsView(
                    tabs: tabManager.split(containing: tab).map { [$0.left, $0.right] } ?? [tab],
                    focusedTabID: tab.id
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let peek = tabManager.peek {
                    PeekView(
                        peek: peek,
                        onClose: { tabManager.closePeek() },
                        onOpenInTab: { tabManager.openPeekInTab() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if appState.isURLBarEditing {
                    // Visual dimming only: clicks go through to the page (links,
                    // context menu...). The URL bar ends editing by itself on any
                    // click outside of it.
                    Color.black.opacity(0.15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.isURLBarEditing)
        .animation(.easeOut(duration: 0.15), value: tabManager.peek?.id)
        // A page left unloaded by a crash while in the background reloads now.
        .onChange(of: tab.id, initial: true) {
            tab.recoverFromCrashIfNeeded()
        }
        // Peek belongs to the page it was opened from.
        .onChange(of: tab.id) {
            tabManager.closePeek()
        }
    }

    /// Pages in Picture in Picture kept in the window, apart from those shown.
    private var parkedTabs: [Tab] {
        let partnerID = tabManager.splitPartner(of: tab)?.id
        return mediaController.pictureInPictureTabs(excluding: tab.id).filter { $0.id != partnerID }
    }
}
