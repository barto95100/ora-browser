import SwiftData
import SwiftUI

/// The context menu of a tab that is in a selection of several tabs: what is
/// done to them all, like Arc.
struct MultipleTabsMenu: View {
    let tabs: [Tab]
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var toastManager: ToastManager
    @Query(sort: TabContainer.displayOrder) private var containers: [TabContainer]

    private var space: TabContainer? {
        tabs.first?.container
    }

    var body: some View {
        Button {
            TabAddresses.copy(tabs, toastManager: toastManager)
            tabManager.clearTabSelection()
        } label: {
            Label("Copy Addresses", systemImage: "link")
        }

        if tabManager.canOpenInSplitView(tabs) {
            Button {
                tabManager.openInSplitView(tabs)
            } label: {
                Label("Open in Split View", systemImage: "rectangle.split.2x1")
            }
        }

        Divider()

        let allPinned = tabs.allSatisfy { $0.type == .pinned }
        Button {
            tabManager.setPinned(tabs, !allPinned)
        } label: {
            Label(allPinned ? "Unpin Tabs" : "Pin Tabs", systemImage: allPinned ? "pin.slash" : "pin")
        }

        if let space, !space.folders.isEmpty {
            Menu("Move to Folder") {
                ForEach(space.folders.sorted { space.path(of: $0) < space.path(of: $1) }) { folder in
                    Button(space.path(of: folder)) {
                        tabManager.moveTabs(tabs, toFolder: folder)
                    }
                }
            }
        }

        let otherSpaces = containers.filter { $0.id != space?.id }
        if !otherSpaces.isEmpty {
            Menu("Move to Container") {
                ForEach(otherSpaces) { container in
                    Button(container.emoji.isEmpty ? container.name : "\(container.emoji) \(container.name)") {
                        tabManager.moveTabs(tabs, to: container)
                        toastManager.show(
                            String(localized: "Moved to \(container.emoji) \(container.name)"),
                            icon: .system("arrow.right.arrow.left")
                        )
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            tabManager.closeTabs(tabs)
        } label: {
            Label("Close \(tabs.count) Tabs", systemImage: "xmark")
        }
    }
}

/// Marks a tab of the sidebar's selection.
struct SelectionRing: View {
    let isShown: Bool
    var cornerRadius: CGFloat = 10
    @Environment(\.theme) private var theme

    var body: some View {
        if isShown {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(theme.activeTabBackground, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}

/// The selection for VoiceOver: each tab says it is selected, and can be
/// added to or taken out of it (as a ⌘-click).
enum TabSelectionAccessibility {
    @MainActor
    static func actions(for tab: Tab, tabManager: TabManager) -> [(name: String, action: () -> Void)] {
        let name = tabManager.isInSelection(tab)
            ? String(localized: "Remove from Selection")
            : String(localized: "Add to Selection")
        return [(name: name, action: { tabManager.toggleSelection(of: tab) })]
    }

    /// Said when the selection changes.
    static func announcement(count: Int) -> String {
        count == 0 ? String(localized: "Selection cleared") : String(localized: "\(count) tabs selected")
    }
}
