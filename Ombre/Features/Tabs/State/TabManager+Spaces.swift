import os
import SwiftData
import SwiftUI

private let logger = Logger(category: "TabManager")

/// Spaces: created, activated, deleted.
extension TabManager {
    func initializeActiveContainerAndTab() {
        // Ensure containers are fetched
        let containers = fetchContainers()

        // Get the last accessed container
        if let lastAccessedContainer = containers.first {
            activeContainer = lastAccessedContainer
            // Get the last accessed tab from the active container
            if let lastAccessedTab = lastAccessedContainer.tabs
                .sorted(by: { ($0.lastAccessedAt ?? Date.distantPast) > ($1.lastAccessedAt ?? Date.distantPast) })
                .first
            {
                activeTab = lastAccessedTab
                activeTab?.maybeIsActive = true
            }
        } else {
            let newContainer = createContainer()
            activeContainer = newContainer
        }
    }

    @discardableResult
    func createContainer(name: String = "Default", emoji: String = "•") -> TabContainer {
        let newContainer = TabContainer(name: name, emoji: emoji)
        newContainer.order = nextContainerOrder()
        modelContext.insert(newContainer)
        activeContainer = newContainer
        self.activeTab = nil
        modelContext.saveOrLog("create space")
        PrivacyDefaults.applyToNewSpace(newContainer.id)
        //        _ = fetchContainers() // Refresh containers
        return newContainer
    }

    /// The order of a new space: after all the others.
    func nextContainerOrder() -> Int {
        var descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.order, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.first?.order ?? -1) + 1
    }

    /// Deletes the space at once (it can't be used half deleted), then cleans
    /// up what it leaves outside the database: passwords, browsing time,
    /// focus settings and website data. Each cleanup step goes on when
    /// another fails. Returns the cleanup, for the tests.
    @discardableResult
    func deleteContainer(_ container: TabContainer) -> Task<Void, Never> {
        let containerId = container.id
        if let persistedContainer = fetchContainer(id: containerId) {
            // A Peek opened from the space uses its data store.
            if let peek, persistedContainer.tabs.contains(where: { $0.id == peek.openerTabID }) {
                closePeek()
            }
            let wasActiveContainer = activeContainer?.id == containerId
            prepareForContainerDeletion(isActiveContainer: wasActiveContainer)
            deleteContainerContents(persistedContainer)

            // Save child deletions before deleting the container: SwiftData
            // could fail when the parent and children went in the same save.
            modelContext.saveOrLog("delete space contents")

            if let containerToDelete = fetchContainer(id: containerId) {
                modelContext.delete(containerToDelete)
                modelContext.saveOrLog("delete space")
            }
            activateFallbackContainerIfNeeded(afterDeletingActiveContainer: wasActiveContainer)
        }
        SettingsStore.shared.removeContainerSettings(for: containerId)

        return Task { @MainActor in
            do {
                try PasswordManagerService.shared.deleteEntries(for: containerId)
            } catch {
                logger.error("Deleting the space's passwords failed: \(error.localizedDescription, privacy: .public)")
            }
            BrowsingTimeStore.shared.delete(spaceID: containerId)
            FocusSettings.shared.removeSpace(containerId)
            // Its website data, then its store on disk.
            await PrivacyService.clearAllWebsiteData(for: containerId)
            await BrowserEngine.shared.removeProfile(identifier: containerId)
        }
    }

    func activateContainer(_ container: TabContainer, activateLastAccessedTab: Bool = true) {
        activeContainer = container
        container.lastAccessedAt = Date()

        // Set the most recently accessed tab in the container
        if let lastAccessedTab = container.tabs
            .sorted(by: { $0.lastAccessedAt ?? Date() > $1.lastAccessedAt ?? Date() }).first,
           lastAccessedTab.isWebViewReady
        {
            activeTab?.maybeIsActive = false
            activeTab = lastAccessedTab
            activeTab?.maybeIsActive = true
            lastAccessedTab.lastAccessedAt = Date()
        } else {
            activeTab = nil
        }

        modelContext.saveOrLog("activate space")
    }

    func fetchContainers() -> [TabContainer] {
        do {
            let descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
            return try modelContext.fetch(descriptor)
        } catch {
            // Failed to fetch containers
        }
        return []
    }

    func fetchContainer(id: UUID) -> TabContainer? {
        let descriptor = FetchDescriptor<TabContainer>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            return nil
        }
    }

    func prepareForContainerDeletion(isActiveContainer: Bool) {
        guard isActiveContainer else { return }

        activeTab?.maybeIsActive = false
        activeTab = nil
        activeContainer = nil
    }

    func deleteContainerContents(_ container: TabContainer) {
        for tab in Array(container.tabs) {
            if tab.isWebViewReady {
                tab.destroyWebView()
            }
            mediaController.removeSession(for: tab.id)
            modelContext.delete(tab)
        }

        for folder in Array(container.folders) {
            modelContext.delete(folder)
        }
        // The space's history goes with it (cascade).
    }

    func activateFallbackContainerIfNeeded(afterDeletingActiveContainer wasActiveContainer: Bool) {
        guard wasActiveContainer else { return }

        if let nextContainer = fetchContainers().first {
            activateContainer(nextContainer)
        } else {
            _ = createContainer()
        }
    }
}
