import Foundation

/// Display order of the pinned section, which holds folders (like Arc) and
/// pinned tabs outside folders. Folders and those tabs share one order; the
/// tabs of a folder are ordered among themselves.
enum TabFolders {
    struct FolderEntry: Equatable {
        let id: UUID
        let order: Int
    }

    struct PinnedTab: Equatable {
        let id: UUID
        let order: Int
        /// The folder the tab is in; a folder that no longer exists counts as none.
        let folderID: UUID?
    }

    /// Folders and the pinned tabs outside folders, in display order.
    static func topLevel(folders: [FolderEntry], tabs: [PinnedTab]) -> [UUID] {
        let folderIDs = Set(folders.map(\.id))
        let looseTabs = tabs.filter { tab in
            guard let folderID = tab.folderID else { return true }
            return !folderIDs.contains(folderID)
        }
        return sorted(
            folders.map { Item(id: $0.id, order: $0.order, isFolder: true) }
                + looseTabs.map { Item(id: $0.id, order: $0.order, isFolder: false) }
        )
    }

    /// The tabs of a folder, in display order.
    static func contents(of folderID: UUID, tabs: [PinnedTab]) -> [UUID] {
        sorted(tabs.filter { $0.folderID == folderID }.map { Item(id: $0.id, order: $0.order, isFolder: false) })
    }

    private struct Item {
        let id: UUID
        let order: Int
        let isFolder: Bool
    }

    /// Highest order first; at equal orders folders first, then a fixed order,
    /// so the sidebar and the moves always see the same list.
    private static func sorted(_ items: [Item]) -> [UUID] {
        items.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order > rhs.order }
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .map(\.id)
    }
}
