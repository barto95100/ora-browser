import Foundation

/// An item of the pinned section: a folder, or a pinned tab outside folders.
enum PinnedEntry: Identifiable {
    case folder(Folder)
    case tab(Tab)

    var id: UUID {
        switch self {
        case let .folder(folder): folder.id
        case let .tab(tab): tab.id
        }
    }
}

/// Folders of the pinned section, like Arc (see `TabFolders`).
extension TabContainer {
    /// The pinned section as the sidebar shows it.
    var pinnedEntries: [PinnedEntry] {
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }) { first, _ in first }
        let tabsByID = Dictionary(tabs.map { ($0.id, $0) }) { first, _ in first }
        return pinnedTopLevelIDs.compactMap { id -> PinnedEntry? in
            if let folder = foldersByID[id] { return .folder(folder) }
            return tabsByID[id].map { .tab($0) }
        }
    }

    /// The tabs of a folder, in display order.
    func tabs(in folder: Folder) -> [Tab] {
        let tabsByID = Dictionary(tabs.map { ($0.id, $0) }) { first, _ in first }
        return TabFolders.contents(of: folder.id, tabs: pinnedTabEntries).compactMap { tabsByID[$0] }
    }

    /// The folder a pinned tab is in, if it still exists.
    func folder(of tab: Tab) -> Folder? {
        guard tab.type == .pinned, let folderID = tab.folderID else { return nil }
        return folders.first { $0.id == folderID }
    }

    /// Pinned tabs in sidebar order, without those of closed folders (except
    /// the active tab, which a closed folder still shows).
    func visiblePinnedTabs(activeTabID: UUID?) -> [Tab] {
        pinnedEntries.flatMap { entry -> [Tab] in
            switch entry {
            case let .tab(tab):
                return [tab]
            case let .folder(folder):
                return tabs(in: folder).filter { folder.isOpened || $0.id == activeTabID }
            }
        }
    }

    // MARK: - Moves

    /// Moves a tab onto a pinned tab: into the target's folder, or out of
    /// folders when the target is in none, at the target's position.
    func movePinned(_ moved: Tab, onto target: Tab) {
        guard moved.id != target.id else { return }
        let targetFolderID = folder(of: target)?.id
        // Taken before the move: a tab coming from elsewhere takes the target's place.
        let ids = targetFolderID.map(contentIDs(of:)) ?? pinnedTopLevelIDs
        if moved.type != .pinned {
            moved.switchSections(from: moved, to: target)
        }
        moved.folderID = targetFolderID
        renumberPinned(TabReordering.reordered(ids, moving: moved.id, onto: target.id))
    }

    /// Puts a tab right after a pinned tab, in the same folder (a duplicate).
    func placePinned(_ tab: Tab, after target: Tab) {
        guard tab.id != target.id else { return }
        let targetFolderID = folder(of: target)?.id
        let ids = targetFolderID.map(contentIDs(of:)) ?? pinnedTopLevelIDs
        if tab.type != .pinned {
            tab.switchSections(from: tab, to: target)
        }
        tab.folderID = targetFolderID
        renumberPinned(TabReordering.inserted(ids, inserting: tab.id, after: target.id))
    }

    /// Moves a folder to another place of the pinned section (`targetID`: a
    /// folder or a pinned tab outside folders).
    func moveFolder(_ folder: Folder, onto targetID: UUID) {
        guard folder.id != targetID else { return }
        renumberPinned(TabReordering.reordered(pinnedTopLevelIDs, moving: folder.id, onto: targetID))
    }

    /// Puts a tab at the end of a folder, pinning it if needed.
    func addTab(_ tab: Tab, to folder: Folder) {
        if tab.type != .pinned {
            tab.leaveSplit()
            tab.type = .pinned
            tab.savedURL = tab.url
        }
        let ids = contentIDs(of: folder.id).filter { $0 != tab.id } + [tab.id]
        tab.folderID = folder.id
        renumberPinned(ids)
    }

    /// Takes a tab out of its folder, right after the folder.
    func removeFromFolder(_ tab: Tab) {
        guard let folder = folder(of: tab) else {
            tab.folderID = nil
            return
        }
        let ids = pinnedTopLevelIDs
        tab.folderID = nil
        renumberPinned(TabReordering.inserted(ids, inserting: tab.id, after: folder.id))
    }

    /// Takes the tabs out of a folder about to be deleted, in its place.
    func emptyFolder(_ folder: Folder) {
        let contents = contentIDs(of: folder.id)
        var ids = pinnedTopLevelIDs
        if let index = ids.firstIndex(of: folder.id) {
            ids.replaceSubrange(index ... index, with: contents)
        }
        for tab in tabs where tab.folderID == folder.id {
            tab.folderID = nil
        }
        renumberPinned(ids)
    }

    /// A new folder's place: in place of `tab` (or of its folder), or first.
    func insertFolder(_ folder: Folder, at tab: Tab?) {
        var ids = pinnedTopLevelIDs.filter { $0 != folder.id }
        let anchor = tab.map { self.folder(of: $0)?.id ?? $0.id }
        let index = anchor.flatMap { ids.firstIndex(of: $0) } ?? 0
        ids.insert(folder.id, at: index)
        if let tab, self.folder(of: tab) == nil {
            ids.removeAll { $0 == tab.id }
        }
        renumberPinned(ids)
    }

    // MARK: - Order

    var pinnedTopLevelIDs: [UUID] {
        TabFolders.topLevel(
            folders: folders.map { TabFolders.FolderEntry(id: $0.id, order: $0.order) },
            tabs: pinnedTabEntries
        )
    }

    func contentIDs(of folderID: UUID) -> [UUID] {
        TabFolders.contents(of: folderID, tabs: pinnedTabEntries)
    }

    private var pinnedTabEntries: [TabFolders.PinnedTab] {
        tabs
            .filter { $0.type == .pinned }
            .map { TabFolders.PinnedTab(id: $0.id, order: $0.order, folderID: $0.folderID) }
    }

    /// Gives folders and pinned tabs, in display order, distinct orders.
    private func renumberPinned(_ orderedIDs: [UUID]) {
        let tabsByID = Dictionary(tabs.map { ($0.id, $0) }) { first, _ in first }
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }) { first, _ in first }
        for (index, id) in orderedIDs.enumerated() {
            let order = orderedIDs.count - index
            tabsByID[id]?.order = order
            foldersByID[id]?.order = order
        }
    }
}
