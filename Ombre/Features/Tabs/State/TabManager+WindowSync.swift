import Foundation
import SwiftData

/// Several windows show the same spaces, each with its own database context:
/// what one window saves shows in the others at once (like Arc, ONG-02).
///
/// A context doesn't see another's saves until it fetches again: a fetch
/// refreshes the objects it already has, their relationships included, and
/// leaves out what was deleted, but tells no view. So when another window
/// saves, each window fetches again, tells the views reading what changed,
/// and lets go of the tabs and spaces deleted elsewhere (their objects stay
/// readable in its context, never marked deleted).
extension TabManager {
    /// What other windows saved since this window last caught up.
    struct PendingSync {
        var inserted: Set<PersistentIdentifier> = []
        var updated: Set<PersistentIdentifier> = []
        var deleted: Set<PersistentIdentifier> = []

        var all: Set<PersistentIdentifier> {
            inserted.union(updated).union(deleted)
        }
    }

    private nonisolated static let syncedEntities: Set<String> = [
        String(describing: TabContainer.self), String(describing: Tab.self), String(describing: Folder.self),
        String(describing: SpaceTask.self)
    ]

    func startSyncingWithOtherWindows() {
        windowSyncObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            guard let context = note.object as? ModelContext else { return }
            let inserted = Self.identifiers(.insertedIdentifiers, in: note)
            let updated = Self.identifiers(.updatedIdentifiers, in: note)
            let deleted = Self.identifiers(.deletedIdentifiers, in: note)
            // History, downloads…: nothing the window shows from its spaces.
            guard (inserted + updated + deleted).contains(where: { Self.syncedEntities.contains($0.entityName) })
            else { return }
            MainActor.assumeIsolated {
                self?.otherContextSaved(context, inserted: inserted, updated: updated, deleted: deleted)
            }
        }
    }

    func stopSyncingWithOtherWindows() {
        if let windowSyncObserver { NotificationCenter.default.removeObserver(windowSyncObserver) }
        windowSyncObserver = nil
    }

    private nonisolated static func identifiers(
        _ key: ModelContext.NotificationKey, in note: Notification
    ) -> [PersistentIdentifier] {
        note.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
    }

    /// Another window's context saved. Caught up a moment later, not inside
    /// that window's save (it may be halfway through a change), and once for
    /// a burst of saves.
    func otherContextSaved(
        _ context: ModelContext,
        inserted: [PersistentIdentifier],
        updated: [PersistentIdentifier],
        deleted: [PersistentIdentifier]
    ) {
        guard !isTornDown, context !== modelContext, context.container === modelContainer else { return }
        let isScheduled = pendingSync != nil
        var pending = pendingSync ?? PendingSync()
        pending.inserted.formUnion(inserted)
        pending.updated.formUnion(updated)
        pending.deleted.formUnion(deleted)
        pendingSync = pending
        guard !isScheduled else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.catchUpWithOtherWindows() }
        }
    }

    func catchUpWithOtherWindows() {
        guard let pending = pendingSync else { return }
        pendingSync = nil
        guard !isTornDown else { return }

        // Before the fetch, while the objects still show what they were.
        let goneTabs = registered(Tab.self, in: pending.deleted)
        let goneSpaceIDs = Set(registered(TabContainer.self, in: pending.deleted).map(\.id))
        let goneFolderIDs = Set(registered(Folder.self, in: pending.deleted).map(\.id))
        let activeWasGone = activeTab.map { active in goneTabs.contains { $0.id == active.id } } ?? false
        let partner = activeTab.flatMap { activeWasGone ? splitPartner(of: $0) : nil }
        var touchedSpaceIDs = spaceIDs(touchedBy: pending.all)

        // Values and relationships as the other window saved them.
        let spaces = (try? modelContext.fetch(FetchDescriptor<TabContainer>())) ?? []
        let tabs = (try? modelContext.fetch(FetchDescriptor<Tab>())) ?? []
        let folders = (try? modelContext.fetch(FetchDescriptor<Folder>())) ?? []
        let tasks = (try? modelContext.fetch(FetchDescriptor<SpaceTask>())) ?? []
        touchedSpaceIDs.formUnion(spaceIDs(touchedBy: pending.all))

        // A fetch tells no view: they are told, for what changed only.
        let changed = pending.updated
        for tab in tabs where changed.contains(tab.persistentModelID) {
            tab.noteChangedElsewhere()
            tab.syncBackgroundColorFromHex()
        }
        for folder in folders where changed.contains(folder.persistentModelID) {
            folder.noteChangedElsewhere()
        }
        for task in tasks where changed.contains(task.persistentModelID) {
            task.noteChangedElsewhere()
        }
        for space in spaces where touchedSpaceIDs.contains(space.id) {
            space.noteChangedElsewhere()
        }

        for tab in goneTabs {
            letGo(of: tab)
        }
        if let renamingFolderID, goneFolderIDs.contains(renamingFolderID) {
            self.renamingFolderID = nil
        }
        replaceWhatWasGone(
            activeWasGone: activeWasGone, partner: partner, goneTabs: goneTabs, goneSpaceIDs: goneSpaceIDs
        )
    }

    /// The window showed a tab or a space deleted elsewhere: it shows another
    /// one, as if it had closed it itself.
    private func replaceWhatWasGone(activeWasGone: Bool, partner: Tab?, goneTabs: [Tab], goneSpaceIDs: Set<UUID>) {
        if let activeContainer, goneSpaceIDs.contains(activeContainer.id) {
            self.activeContainer = nil
            activeTab?.maybeIsActive = false
            activeTab = nil
        } else if activeWasGone {
            activeTab = nil
            if let partner, !goneTabs.contains(where: { $0.id == partner.id }) {
                activateTab(partner)
            } else if let activeContainer, let next = Self.lastUsedTab(in: activeContainer) {
                activateTab(next)
            }
        }
        // No space shown (its own deleted, or none left a moment ago while
        // the other window made a new one): the first one there is.
        if activeContainer == nil, let first = fetchContainers().first {
            activateContainer(first)
        }
    }

    /// The objects of a type this window holds, among `identifiers`.
    /// `registeredModel` traps on an identifier of another type: sorted first.
    private func registered<Model: PersistentModel>(
        _ type: Model.Type, in identifiers: Set<PersistentIdentifier>
    ) -> [Model] {
        identifiers.filter { $0.entityName == String(describing: type) }
            .compactMap { modelContext.registeredModel(for: $0) as Model? }
    }

    /// The spaces whose tabs, folders or tasks are among `identifiers`, and
    /// those spaces themselves.
    private func spaceIDs(touchedBy identifiers: Set<PersistentIdentifier>) -> Set<UUID> {
        var ids = Set(registered(TabContainer.self, in: identifiers).map(\.id))
        ids.formUnion(registered(Tab.self, in: identifiers).compactMap { $0.parentContainer?.id })
        ids.formUnion(registered(Folder.self, in: identifiers).compactMap { $0.parentContainer?.id })
        ids.formUnion(registered(SpaceTask.self, in: identifiers).compactMap { $0.container?.id })
        return ids
    }

    /// A tab deleted in another window: its page and state here go too.
    private func letGo(of tab: Tab) {
        if peek?.openerTabID == tab.id { closePeek() }
        tab.destroyWebView()
        mediaController.removeSession(for: tab.id)
        dropRuntime(for: tab)
    }
}
