import Foundation
import SwiftData

// MARK: - TabContainer

@Model
class TabContainer: ObservableObject, Identifiable {
    var id: UUID
    var name: String
    var emoji: String
    /// SF Symbol shown instead of the emoji (see `SpaceIcon`).
    var iconSymbol: String?
    /// The space's color (see `SpaceColor`), none by default.
    var colorName: String?
    /// The space's theme (see `SpaceTheme`), none by default.
    var themeName: String?
    var createdAt: Date
    var lastAccessedAt: Date

    @Relationship(deleteRule: .cascade) var tabs: [Tab] = []
    @Relationship(deleteRule: .cascade) var folders: [Folder] = []
    @Relationship var history: [History] = []

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isActive: Bool = true,
        emoji: String = "💩"
    ) {
        let nowDate = Date()
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = nowDate
        self.lastAccessedAt = nowDate
    }

    /// Moves a tab onto another one, in the other's section (favorites,
    /// pinned or normal), like a list: dragged down it goes after the target,
    /// dragged up before it, from another section in its place. Only that
    /// section's tabs are renumbered, so the other sections never move.
    func moveTab(_ moved: Tab, onto target: Tab) {
        guard moved.id != target.id else { return }
        // The pinned section also holds folders.
        if target.type == .pinned {
            movePinned(moved, onto: target)
            return
        }
        // Taken before a change of section: a tab from another section is not
        // in the list yet, so it takes the target's place.
        let ids = displayedTabs(of: target.type).map(\.id)
        if moved.type != target.type {
            moved.switchSections(from: moved, to: target)
        }
        renumber(TabReordering.reordered(ids, moving: moved.id, onto: target.id))
    }

    /// Puts a tab right after another one, in the other's section (a
    /// duplicated tab next to its original).
    func placeTab(_ tab: Tab, after target: Tab) {
        guard tab.id != target.id else { return }
        if target.type == .pinned {
            placePinned(tab, after: target)
            return
        }
        let ids = displayedTabs(of: target.type).map(\.id)
        if tab.type != target.type {
            tab.switchSections(from: tab, to: target)
        }
        renumber(TabReordering.inserted(ids, inserting: tab.id, after: target.id))
    }

    /// Puts a tab last among the normal tabs (dropped under the last one),
    /// taking it out of the favorites or pinned tabs if needed.
    func moveToEndOfNormalTabs(_ tab: Tab) {
        let ids = displayedTabs(of: .normal).map(\.id).filter { $0 != tab.id }
        if tab.type != .normal {
            tab.folderID = nil
            tab.type = .normal
            tab.savedURL = nil
        }
        renumber(ids + [tab.id])
    }

    /// A section's tabs in the order the sidebar shows them: same sort as the
    /// sidebar lists, so tabs sharing an order are seen in the same places.
    private func displayedTabs(of type: TabType) -> [Tab] {
        tabs
            .sorted { $0.order > $1.order }
            .filter { $0.type == type }
    }

    /// Gives the tabs, in display order, distinct orders (highest first).
    private func renumber(_ orderedIDs: [UUID]) {
        let tabsByID = Dictionary(tabs.map { ($0.id, $0) }) { first, _ in first }
        for (index, id) in orderedIDs.enumerated() {
            tabsByID[id]?.order = orderedIDs.count - index
        }
    }
}

/// Reordering of a section's tabs, in display order.
enum TabReordering {
    /// `ids` with `moving` placed at `target`'s position: after it when moving
    /// down, before it when moving up.
    static func reordered(_ ids: [UUID], moving: UUID, onto target: UUID) -> [UUID] {
        guard moving != target, let targetIndex = ids.firstIndex(of: target) else { return ids }
        var result = ids
        if let movingIndex = result.firstIndex(of: moving) {
            result.remove(at: movingIndex)
        }
        result.insert(moving, at: min(targetIndex, result.count))
        return result
    }

    /// `ids` with `inserting` placed right after `target` (taken out of its
    /// previous place if it was already there).
    static func inserted(_ ids: [UUID], inserting: UUID, after target: UUID) -> [UUID] {
        guard inserting != target else { return ids }
        var result = ids.filter { $0 != inserting }
        guard let targetIndex = result.firstIndex(of: target) else { return ids }
        result.insert(inserting, at: targetIndex + 1)
        return result
    }
}
