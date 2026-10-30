import Foundation

/// Display order of the pinned section, which holds folders (like Arc) and
/// pinned tabs. Folders can hold folders. At each level (the section, or a
/// folder) the folders and tabs share one order.
enum TabFolders {
    struct FolderEntry: Equatable {
        let id: UUID
        let order: Int
        /// The folder it is in; nil, or a folder that no longer exists: the
        /// section itself.
        var parentID: UUID?
    }

    struct PinnedTab: Equatable {
        let id: UUID
        let order: Int
        /// The folder the tab is in; a folder that no longer exists counts as none.
        let folderID: UUID?
    }

    /// Folders and pinned tabs of the section itself, in display order.
    static func topLevel(folders: [FolderEntry], tabs: [PinnedTab]) -> [UUID] {
        contents(of: nil, folders: folders, tabs: tabs)
    }

    /// The folders and tabs directly in a folder (nil: the section), in
    /// display order.
    static func contents(of folderID: UUID?, folders: [FolderEntry], tabs: [PinnedTab]) -> [UUID] {
        let existing = Set(folders.map(\.id))
        func level(_ parentID: UUID?) -> UUID? {
            parentID.flatMap { existing.contains($0) ? $0 : nil }
        }
        let childFolders = folders.filter { $0.id != folderID && level($0.parentID) == folderID }
        let childTabs = tabs.filter { level($0.folderID) == folderID }
        return sorted(
            childFolders.map { Item(id: $0.id, order: $0.order, isFolder: true) }
                + childTabs.map { Item(id: $0.id, order: $0.order, isFolder: false) }
        )
    }

    /// Whether `folderID` is `ancestorID` or inside it, at any depth: a folder
    /// can't go into itself or into one of its folders.
    static func isFolder(_ folderID: UUID, within ancestorID: UUID, folders: [FolderEntry]) -> Bool {
        let parents = Dictionary(folders.map { ($0.id, $0.parentID) }) { first, _ in first }
        var current: UUID? = folderID
        var seen = Set<UUID>()
        while let id = current, seen.insert(id).inserted {
            if id == ancestorID { return true }
            current = parents[id] ?? nil
        }
        return false
    }

    /// How deep a folder is: 0 in the section, 1 in a folder...
    static func depth(of folderID: UUID, folders: [FolderEntry]) -> Int {
        let parents = Dictionary(folders.map { ($0.id, $0.parentID) }) { first, _ in first }
        var depth = 0
        var current = parents[folderID] ?? nil
        var seen: Set<UUID> = [folderID]
        while let id = current, parents[id] != nil, seen.insert(id).inserted {
            depth += 1
            current = parents[id] ?? nil
        }
        return depth
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
