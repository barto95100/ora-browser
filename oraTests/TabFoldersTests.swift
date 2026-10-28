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
            tabs: [
                .init(id: tabs[0], order: 1, folderID: folder),
                .init(id: tabs[1], order: 5, folderID: other),
                .init(id: tabs[2], order: 2, folderID: folder)
            ]
        )
        #expect(result == [tabs[2], tabs[0]])
    }
}
