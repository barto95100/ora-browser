import Foundation

/// Folders of the pinned section, like Arc (see `TabContainer+Folders.swift`).
extension TabManager {
    /// Creates a folder in the pinned section: in place of `tab`, which goes
    /// in it, or first. Its name is edited right away.
    @discardableResult
    func createFolder(in container: TabContainer, with tab: Tab? = nil) -> Folder {
        let folder = Folder(name: "New Folder", isOpened: true, container: container)
        modelContext.insert(folder)
        container.folders.append(folder)
        container.insertFolder(folder, at: tab)
        if let tab {
            container.addTab(tab, to: folder)
        }
        renamingFolderID = folder.id
        try? modelContext.save()
        return folder
    }

    func renameFolder(_ folder: Folder, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != folder.name {
            folder.name = name
            try? modelContext.save()
        }
    }

    func toggleFolder(_ folder: Folder) {
        folder.isOpened.toggle()
        try? modelContext.save()
    }

    /// Deletes a folder; its tabs stay pinned, where the folder was.
    func deleteFolder(_ folder: Folder) {
        let container = folder.container
        container.emptyFolder(folder)
        container.folders.removeAll { $0.id == folder.id }
        modelContext.delete(folder)
        if renamingFolderID == folder.id {
            renamingFolderID = nil
        }
        try? modelContext.save()
    }

    /// Puts a pinned tab in a folder, or out of folders (`nil`).
    func moveTab(_ tab: Tab, toFolder folder: Folder?) {
        if let folder {
            tab.container.addTab(tab, to: folder)
        } else {
            tab.container.removeFromFolder(tab)
        }
        try? modelContext.save()
    }
}
