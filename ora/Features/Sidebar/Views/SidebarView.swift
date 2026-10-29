import AppKit
import Inject
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(\.window) var window: NSWindow?
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var privacyMode: PrivacyMode
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toolbarManager: ToolbarManager

    @Query var containers: [TabContainer]
    @Query(filter: nil, sort: [.init(\History.lastAccessedAt, order: .reverse)])
    var histories: [History]

    private let columns = Array(repeating: GridItem(spacing: 10), count: 3)

    @ObserveInjection var inject

    @State private var isHoveringSidebarToggle = false

    /// Downloads transition state
    @State private var dragOffset: CGFloat = 0
    /// Width of the bottom bar: narrow, its tools gather in a menu.
    @State private var bottomBarWidth: CGFloat = 320

    /// Trackpad and Magic Mouse swipes, handled here rather than by the page
    /// controller (whose transition felt slow): one swipe changes space with a
    /// short animation; from the first space, swiping right shows the
    /// downloads (they sit before it), swiping left hides them.
    @State private var swipeMonitor = HorizontalSwipeMonitor()
    @State private var swipeArea = SidebarSwipeArea()

    private var isShowingDownloads: Bool {
        downloadManager.isShowingDownloadsHistory
    }

    private var shouldShowMediaWidget: Bool {
        let activeId = tabManager.activeTab?.id
        let others = media.visibleSessions.filter { session in
            guard let activeId else { return true }
            return session.tabID != activeId
        }
        return media.isVisible && !others.isEmpty
    }

    private var selectedContainerIndex: Binding<Int> {
        Binding(
            get: {
                guard let activeContainer = tabManager.activeContainer else {
                    return 0
                }
                return containers.firstIndex { $0.id == activeContainer.id } ?? 0
            },
            set: { newIndex in
                guard newIndex >= 0, newIndex < containers.count else { return }
                tabManager.activateContainer(containers[newIndex])
            }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = transitionProgress(for: width)

            ZStack(alignment: .leading) {
                // Spaces content - pushes back and blurs out when downloads is shown
                spacesContent
                    .frame(width: width)
                    .offset(x: width * 0.12 * progress)
                    .scaleEffect(CGFloat(1.0) - 0.06 * progress, anchor: .center)
                    .opacity(CGFloat(1.0) - 0.5 * progress)
                    .allowsHitTesting(progress < 0.5)

                // Downloads history - slides in from leading edge
                DownloadsHistoryView()
                    .frame(width: width)
                    .offset(x: -width + width * progress)
                    .shadow(color: .black.opacity(0.08 * Double(progress)), radius: 8, x: 4, y: 0)
                    .allowsHitTesting(progress >= 0.5)
            }
            .clipped()
            // Swipe-to-dismiss gesture on the whole sidebar when downloads is showing
            .simultaneousGesture(downloadsNavigationGesture(width: width))
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { swipeArea.frame = $0 }
        .onChange(of: selectedContainerIndex.wrappedValue, initial: true) { _, index in
            swipeArea.selectedIndex = index
        }
        .onChange(of: containers.map(\.id), initial: true) {
            swipeArea.containers = containers
        }
        // The window is not known yet when the sidebar first appears.
        .onChange(of: window, initial: true) { _, window in
            swipeArea.window = window
        }
        .onAppear {
            swipeMonitor.start(accepts: isInSidebar, handler: handleSwipe)
        }
        .onDisappear {
            swipeMonitor.stop()
        }
        .enableInjection()
    }

    private func isInSidebar(_ event: NSEvent) -> Bool {
        guard let window = swipeArea.window, event.window === window, let contentView = window.contentView
        else { return false }
        // Window coordinates start at the bottom, SwiftUI's at the top.
        let location = event.locationInWindow
        let point = CGPoint(x: location.x, y: contentView.bounds.height - location.y)
        return swipeArea.frame.contains(point)
    }

    private func handleSwipe(_ direction: HorizontalSwipeMonitor.Direction) -> Bool {
        guard !privacyMode.isPrivate else { return false }
        if isShowingDownloads {
            if direction == .fingersLeft {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    downloadManager.isShowingDownloadsHistory = false
                }
            }
            return true
        }
        let index = swipeArea.selectedIndex
        switch direction {
        case .fingersRight where index == 0:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                downloadManager.isShowingDownloadsHistory = true
            }
            return true
        case .fingersRight:
            showSpace(at: index - 1)
            return true
        case .fingersLeft where index + 1 < swipeArea.containers.count:
            showSpace(at: index + 1)
            return true
        case .fingersLeft:
            // Last space: the page controller bounces.
            return false
        }
    }

    private func showSpace(at index: Int) {
        guard swipeArea.containers.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            tabManager.activateContainer(swipeArea.containers[index])
        }
    }

    /// Computes transition progress (0 = spaces visible, 1 = downloads visible)
    /// incorporating both the boolean state and any interactive drag offset.
    private func transitionProgress(for width: CGFloat) -> CGFloat {
        let base: CGFloat = isShowingDownloads ? 1.0 : 0.0
        // dragOffset > 0 means dragging right (toward spaces), < 0 means dragging left (toward downloads)
        let dragContribution = -dragOffset / max(width, 1)
        return min(1, max(0, base + dragContribution))
    }

    // MARK: - Gesture

    /// Handles swipe-to-dismiss (right swipe when in downloads) and
    /// swipe-to-enter (left swipe from first container).
    private func downloadsNavigationGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                if isShowingDownloads {
                    // Swipe right to dismiss downloads
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                } else if selectedContainerIndex.wrappedValue == 0 {
                    // Swipe left from first container to show downloads
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                    }
                }
            }
            .onEnded { value in
                let threshold = width * 0.25
                if isShowingDownloads {
                    if value.translation.width > threshold
                        || value.predictedEndTranslation.width > threshold * 2
                    {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                            downloadManager.isShowingDownloadsHistory = false
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            dragOffset = 0
                        }
                    }
                } else if selectedContainerIndex.wrappedValue == 0 {
                    if -value.translation.width > threshold
                        || -value.predictedEndTranslation.width > threshold * 2
                    {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                            downloadManager.isShowingDownloadsHistory = true
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            dragOffset = 0
                        }
                    }
                } else {
                    dragOffset = 0
                }
            }
    }

    // MARK: - Spaces Content

    private var spacesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sidebarManager.sidebarPosition == .secondary, !toolbarManager.isToolbarHidden {
                Spacer().frame(height: 8)
            } else if appState.isFullscreen, !toolbarManager.isToolbarHidden {
                Spacer().frame(height: 8)
            } else {
                SidebarHeader()
            }
            NSPageView(
                selection: selectedContainerIndex,
                pageObjects: containers,
                idKeyPath: \.name
            ) { container in
                ContainerView(
                    container: container,
                    selectedContainer: container.name,
                    containers: containers
                )
                .padding(.horizontal, 10)
                .environmentObject(tabManager)
                .environmentObject(historyManager)
                .environmentObject(downloadManager)
                .environmentObject(appState)
                .environmentObject(privacyMode)
                .environmentObject(toolbarManager)
            }

            if shouldShowMediaWidget {
                GlobalMediaPlayer()
                    .environmentObject(media)
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !privacyMode.isPrivate {
                // In a narrow sidebar, downloads, notes and tasks gather in one
                // menu, so that the spaces keep their room.
                HStack(spacing: 2) {
                    if bottomBarWidth < 260 {
                        SidebarToolsMenu()
                    } else {
                        DownloadsWidget()
                        NotesButton()
                        SidebarTasksButton()
                    }
                    ContainerSwitcher(onContainerSelected: onContainerSelected)
                        .padding(.horizontal, 4)
                    NewContainerButton()
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { bottomBarWidth = $0 }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(
            EdgeInsets(
                top: 4,
                leading: 0,
                bottom: 10,
                trailing: 0
            )
        )
        // Double click on the sidebar's empty space zooms the window. Behind
        // the content, not around it: a double click gesture around the tabs
        // made every click in the sidebar wait for a possible second click
        // (about half a second) before selecting a tab or opening a folder.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    toggleMaximizeWindow()
                }
        }
    }

    private func onContainerSelected(container: TabContainer) {
        withAnimation(.easeOut(duration: 0.1)) {
            tabManager.activateContainer(container)
        }
    }

    private func toggleMaximizeWindow() {
        window?.toggleMaximized()
    }
}

/// What the swipe monitor needs to know about the sidebar, kept in a
/// reference so its handler always reads the current values.
final class SidebarSwipeArea {
    weak var window: NSWindow?
    var frame: CGRect = .zero
    var selectedIndex = 0
    var containers: [TabContainer] = []
}
