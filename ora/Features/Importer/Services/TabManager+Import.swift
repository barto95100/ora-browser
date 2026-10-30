import Foundation
import SwiftData

extension TabManager {
    /// Adds the imported spaces next to the existing ones, without changing the
    /// space or tab in use. A name already taken gets the browser's name after it.
    /// Returns the new spaces.
    @discardableResult
    func importSpaces(_ data: ImportedBrowserData, from browser: String) -> [TabContainer] {
        var names = Set((try? modelContext.fetch(FetchDescriptor<TabContainer>()))?.map(\.name) ?? [])
        let created = data.spaces.map { space in
            let name = Self.importedName(space.name, browser: browser, taken: names)
            names.insert(name)
            let container = TabContainer(name: name, emoji: space.emoji ?? "•")
            // Not the space to open at the next launch.
            container.lastAccessedAt = .distantPast
            modelContext.insert(container)
            PrivacyDefaults.applyToNewSpace(container.id)

            for (index, favorite) in space.favorites.enumerated() {
                addImportedTab(favorite, type: .fav, order: space.favorites.count - index, to: container)
            }
            addImportedItems(space.pinned, in: nil, to: container)
            return container
        }
        try? modelContext.save()
        return created
    }

    nonisolated static func importedName(_ name: String, browser: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let suffixed = "\(name) (\(browser))"
        guard taken.contains(suffixed) else { return suffixed }
        var number = 2
        while taken.contains("\(name) (\(browser) \(number))") {
            number += 1
        }
        return "\(name) (\(browser) \(number))"
    }

    private func addImportedItems(_ items: [ImportedPinnedItem], in folder: Folder?, to container: TabContainer) {
        for (index, item) in items.enumerated() {
            let order = items.count - index
            switch item {
            case let .tab(tab):
                let added = addImportedTab(tab, type: .pinned, order: order, to: container)
                added.folderID = folder?.id
            case let .folder(name, isOpen, children):
                let child = Folder(name: name, isOpened: isOpen, container: container)
                child.order = order
                child.parentID = folder?.id
                modelContext.insert(child)
                container.folders.append(child)
                addImportedItems(children, in: child, to: container)
            }
        }
    }

    @discardableResult
    private func addImportedTab(_ imported: ImportedTab, type: TabType, order: Int, to container: TabContainer) -> Tab {
        let tab = Tab(
            url: imported.url,
            title: imported.title,
            favicon: imported.faviconURL,
            container: container,
            type: type,
            order: order,
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: self,
            isPrivate: false
        )
        tab.savedURL = imported.url
        modelContext.insert(tab)
        container.tabs.append(tab)
        return tab
    }
}
