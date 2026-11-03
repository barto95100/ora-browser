import Foundation

/// An item of the pinned section or of a folder: a folder, or a pinned tab.
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

/// Folders of the pinned section, like Arc; folders can hold folders (see
/// `TabFolders`).
extension TabContainer {
    /// The pinned section as the sidebar shows it, its first level.
    var pinnedEntries: [PinnedEntry] {
        entries(of: pinnedTopLevelIDs)
    }

    /// The folders and tabs of a folder, in display order.
    func entries(in folder: Folder) -> [PinnedEntry] {
        entries(of: contentIDs(of: folder.id))
    }

    /// The tabs directly in a folder, in display order.
    func tabs(in folder: Folder) -> [Tab] {
        entries(in: folder).compactMap { entry in
            if case let .tab(tab) = entry { return tab }
            return nil
        }
    }

    /// The folder a pinned tab is in, if it still exists.
    func folder(of tab: Tab) -> Folder? {
        guard tab.type == .pinned, let folderID = tab.folderID else { return nil }
        return folders.first { $0.id == folderID }
    }

    /// The folder a folder is in, if any.
    func parent(of folder: Folder) -> Folder? {
        guard let parentID = folder.parentID else { return nil }
        return folders.first { $0.id == parentID }
    }

    /// Whether a tab is in a folder, at any depth.
    func contains(_ tab: Tab, in folder: Folder) -> Bool {
        guard let tabFolder = self.folder(of: tab) else { return false }
        return TabFolders.isFolder(tabFolder.id, within: folder.id, folders: folderEntries)
    }

    /// Folders that `folder` can go into: not itself nor one of its own.
    func folders(acceptingFolder folder: Folder) -> [Folder] {
        folders.filter { !TabFolders.isFolder($0.id, within: folder.id, folders: folderEntries) }
    }

    /// "Parent › Child" for menus.
    func path(of folder: Folder) -> String {
        var names = [folder.name]
        var current = parent(of: folder)
        var seen: Set<UUID> = [folder.id]
        while let parent = current, seen.insert(parent.id).inserted {
            names.insert(parent.name, at: 0)
            current = self.parent(of: parent)
        }
        return names.joined(separator: " › ")
    }

    /// Pinned tabs in sidebar order, without those of closed folders (except
    /// the active tab, which a closed folder still shows).
    func visiblePinnedTabs(activeTabID: UUID?) -> [Tab] {
        visibleTabs(in: pinnedEntries, isOpen: true, activeTabID: activeTabID)
    }

    private func visibleTabs(in entries: [PinnedEntry], isOpen: Bool, activeTabID: UUID?) -> [Tab] {
        entries.flatMap { entry -> [Tab] in
            switch entry {
            case let .tab(tab):
                return isOpen || tab.id == activeTabID ? [tab] : []
            case let .folder(folder):
                let isFolderOpen = isOpen && folder.isOpened
                return visibleTabs(in: self.entries(in: folder), isOpen: isFolderOpen, activeTabID: activeTabID)
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
        let ids = contentIDs(of: targetFolderID)
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
        let ids = contentIDs(of: targetFolderID)
        if tab.type != .pinned {
            tab.switchSections(from: tab, to: target)
        }
        tab.folderID = targetFolderID
        renumberPinned(TabReordering.inserted(ids, inserting: tab.id, after: target.id))
    }

    /// Moves a folder to the place of a folder or a pinned tab (`targetID`),
    /// at that one's level: into its folder, or the section.
    func moveFolder(_ folder: Folder, onto targetID: UUID) {
        guard folder.id != targetID else { return }
        let targetParentID: UUID?
        if let targetFolder = folders.first(where: { $0.id == targetID }) {
            targetParentID = targetFolder.parentID
        } else if let targetTab = tabs.first(where: { $0.id == targetID }) {
            targetParentID = self.folder(of: targetTab)?.id
        } else {
            return
        }
        if let targetParentID, TabFolders.isFolder(targetParentID, within: folder.id, folders: folderEntries) {
            return
        }
        let ids = contentIDs(of: targetParentID)
        folder.parentID = targetParentID
        renumberPinned(TabReordering.reordered(ids, moving: folder.id, onto: targetID))
    }

    /// Puts a folder at the end of another one (nil: the section); not into
    /// itself or one of its folders.
    func moveFolder(_ folder: Folder, into parent: Folder?) {
        if let parent, TabFolders.isFolder(parent.id, within: folder.id, folders: folderEntries) { return }
        let ids = contentIDs(of: parent?.id).filter { $0 != folder.id } + [folder.id]
        folder.parentID = parent?.id
        renumberPinned(ids)
    }

    /// Puts a tab at the end of a folder, pinning it if needed.
    func addTab(_ tab: Tab, to folder: Folder) {
        if tab.type != .pinned {
            tab.type = .pinned
            tab.savedURL = tab.url
        }
        let ids = contentIDs(of: folder.id).filter { $0 != tab.id } + [tab.id]
        tab.folderID = folder.id
        renumberPinned(ids)
    }

    /// Takes a tab out of its folder, right after the folder (in the folder's
    /// own folder, if any).
    func removeFromFolder(_ tab: Tab) {
        guard let folder = folder(of: tab) else {
            tab.folderID = nil
            return
        }
        let ids = contentIDs(of: folder.parentID)
        tab.folderID = folder.parentID
        renumberPinned(TabReordering.inserted(ids, inserting: tab.id, after: folder.id))
    }

    /// Takes the tabs and folders out of a folder about to be deleted, in its
    /// place.
    func emptyFolder(_ folder: Folder) {
        let contents = contentIDs(of: folder.id)
        var ids = contentIDs(of: folder.parentID)
        if let index = ids.firstIndex(of: folder.id) {
            ids.replaceSubrange(index ... index, with: contents)
        }
        for tab in tabs where tab.folderID == folder.id {
            tab.folderID = folder.parentID
        }
        for child in folders where child.parentID == folder.id {
            child.parentID = folder.parentID
        }
        renumberPinned(ids)
    }

    /// A new folder's place: in a folder (`parent`) first; in place of `tab`
    /// (in the tab's folder); or first in the section.
    func insertFolder(_ folder: Folder, at tab: Tab?, in parent: Folder? = nil) {
        let parentID = parent?.id ?? tab.flatMap { self.folder(of: $0)?.id }
        folder.parentID = parentID
        var ids = contentIDs(of: parentID).filter { $0 != folder.id }
        let index = tab.flatMap { ids.firstIndex(of: $0.id) } ?? 0
        ids.insert(folder.id, at: index)
        if let tab {
            ids.removeAll { $0 == tab.id }
        }
        renumberPinned(ids)
    }

    // MARK: - Order

    var pinnedTopLevelIDs: [UUID] {
        TabFolders.topLevel(folders: folderEntries, tabs: pinnedTabEntries)
    }

    /// The folders and tabs directly in a folder (nil: the section).
    func contentIDs(of folderID: UUID?) -> [UUID] {
        TabFolders.contents(of: folderID, folders: folderEntries, tabs: pinnedTabEntries)
    }

    private var folderEntries: [TabFolders.FolderEntry] {
        folders.map { TabFolders.FolderEntry(id: $0.id, order: $0.order, parentID: $0.parentID) }
    }

    private var pinnedTabEntries: [TabFolders.PinnedTab] {
        tabs
            .filter { $0.type == .pinned }
            .map { TabFolders.PinnedTab(id: $0.id, order: $0.order, folderID: $0.folderID) }
    }

    private func entries(of ids: [UUID]) -> [PinnedEntry] {
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }) { first, _ in first }
        let tabsByID = Dictionary(tabs.map { ($0.id, $0) }) { first, _ in first }
        return ids.compactMap { id -> PinnedEntry? in
            if let folder = foldersByID[id] { return .folder(folder) }
            return tabsByID[id].map { .tab($0) }
        }
    }

    /// Gives folders and pinned tabs of one level, in display order, distinct
    /// orders.
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
