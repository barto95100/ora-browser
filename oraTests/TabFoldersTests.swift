import Foundation
@testable import Ora
import Testing

struct TabFoldersTests {
    private let folder = UUID()
    private let tabs = (0 ..< 3).map { _ in UUID() }

    @Test func foldersAndLooseTabsShareOneOrder() {
        let result = TabFolders.topLevel(
            folders: [.init(id: folder, order: 2)],
            tabs: [
                .init(id: tabs[0], order: 3, folderID: nil),
                .init(id: tabs[1], order: 1, folderID: nil),
                .init(id: tabs[2], order: 9, folderID: folder)
            ]
        )
        #expect(result == [tabs[0], folder, tabs[1]])
    }

    @Test func aTabOfADeletedFolderIsShownOutsideFolders() {
        let result = TabFolders.topLevel(
            folders: [],
            tabs: [.init(id: tabs[0], order: 1, folderID: folder)]
        )
        #expect(result == [tabs[0]])
    }

    @Test func aFolderComesBeforeATabWithTheSameOrder() {
        let result = TabFolders.topLevel(
            folders: [.init(id: folder, order: 1)],
            tabs: [.init(id: tabs[0], order: 1, folderID: nil)]
        )
        #expect(result == [folder, tabs[0]])
    }

    @Test func aFolderListsOnlyItsTabsInOrder() {
        let other = UUID()
        let result = TabFolders.contents(
            of: folder,
            folders: [.init(id: folder, order: 1)],
            tabs: [
                .init(id: tabs[0], order: 1, folderID: folder),
                .init(id: tabs[1], order: 5, folderID: other),
                .init(id: tabs[2], order: 2, folderID: folder)
            ]
        )
        #expect(result == [tabs[2], tabs[0]])
    }

    @Test func aFolderListsItsFoldersAndTabsInOneOrder() {
        let child = UUID()
        let folders: [TabFolders.FolderEntry] = [
            .init(id: folder, order: 1),
            .init(id: child, order: 2, parentID: folder)
        ]
        let pinned: [TabFolders.PinnedTab] = [
            .init(id: tabs[0], order: 3, folderID: folder),
            .init(id: tabs[1], order: 1, folderID: folder),
            .init(id: tabs[2], order: 1, folderID: child)
        ]
        #expect(TabFolders.topLevel(folders: folders, tabs: pinned) == [folder])
        #expect(TabFolders.contents(of: folder, folders: folders, tabs: pinned) == [tabs[0], child, tabs[1]])
        #expect(TabFolders.contents(of: child, folders: folders, tabs: pinned) == [tabs[2]])
    }

    @Test func aFolderOfADeletedFolderIsShownInTheSection() {
        let child = UUID()
        let result = TabFolders.topLevel(folders: [.init(id: child, order: 1, parentID: folder)], tabs: [])
        #expect(result == [child])
    }

    @Test func aFolderCannotGoIntoItselfOrItsFolders() {
        let child = UUID()
        let grandChild = UUID()
        let other = UUID()
        let folders: [TabFolders.FolderEntry] = [
            .init(id: folder, order: 1),
            .init(id: child, order: 1, parentID: folder),
            .init(id: grandChild, order: 1, parentID: child),
            .init(id: other, order: 2)
        ]
        #expect(TabFolders.isFolder(grandChild, within: folder, folders: folders))
        #expect(TabFolders.isFolder(folder, within: folder, folders: folders))
        #expect(!TabFolders.isFolder(other, within: folder, folders: folders))
        #expect(!TabFolders.isFolder(folder, within: child, folders: folders))
        #expect(TabFolders.depth(of: grandChild, folders: folders) == 2)
        #expect(TabFolders.depth(of: folder, folders: folders) == 0)
    }
}
