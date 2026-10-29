import SwiftUI

struct BrowserWebContentView: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var toolbarManager: ToolbarManager
    @EnvironmentObject private var mediaController: MediaController
    @EnvironmentObject private var privacyMode: PrivacyMode
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

            HStack(spacing: 0) {
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
                        tabs: panelTabs,
                        focusedTabID: tab.id
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // A tab dragged from the sidebar over the page: split zones.
                    if tabManager.draggingTabID != nil, tabManager.peek == nil {
                        SplitDropOverlay()
                    }

                    if let peek = tabManager.peek {
                        PeekView(
                            peek: peek,
                            onClose: { tabManager.closePeek() },
                            onOpenInTab: { tabManager.openPeekInTab() },
                            onOpenInSplitView: { tabManager.openPeekInSplitView() }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    // An area traced for the tab's note.
                    if let request = appState.areaCapture, panelTabs.contains(where: { $0.id == request.tabID }) {
                        AreaCaptureOverlay(tabs: panelTabs, request: request)
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

                // The tab's note or the space's tasks, beside the page. The side
                // slides in and out; from one to the other it fades (a slide
                // left the note's images, drawn by AppKit, ahead of the rest).
                if appState.showTabNote || appState.showTasks, !privacyMode.isPrivate {
                    Group {
                        if appState.showTabNote {
                            TabNotePanel(tab: tab).transition(.opacity)
                        } else {
                            TasksPanel(tab: tab).transition(.opacity)
                        }
                    }
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.showTabNote || appState.showTasks)
        .animation(.easeInOut(duration: 0.2), value: appState.showTabNote)
        .animation(.easeOut(duration: 0.2), value: appState.isURLBarEditing)
        .animation(.easeOut(duration: 0.15), value: tabManager.peek?.id)
        // A page left unloaded by a crash while in the background reloads now.
        .onChange(of: tab.id, initial: true) {
            tab.recoverFromCrashIfNeeded()
        }
        // Peek belongs to the page it was opened from. In a split, a click on
        // a link of the other side focuses that side, then opens Peek from
        // it: that Peek stays.
        .onChange(of: tab.id) {
            if tabManager.peek?.openerTabID != tab.id {
                tabManager.closePeek()
            }
        }
    }

    /// The tab shown, with its split partner.
    private var panelTabs: [Tab] {
        tabManager.split(containing: tab).map { [$0.left, $0.right] } ?? [tab]
    }

    /// Pages in Picture in Picture kept in the window, apart from those shown.
    private var parkedTabs: [Tab] {
        let partnerID = tabManager.splitPartner(of: tab)?.id
        return mediaController.pictureInPictureTabs(excluding: tab.id).filter { $0.id != partnerID }
    }
}
