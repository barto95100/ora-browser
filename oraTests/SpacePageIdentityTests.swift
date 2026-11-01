import Foundation
@testable import Ora
import Testing

@MainActor
struct SpacePageIdentityTests {
    @Test func twoSpacesWithTheSameNameHaveDifferentPages() {
        let first = TabContainer(name: "Work")
        let second = TabContainer(name: "Work")
        #expect(first.pageID != second.pageID)
    }

    @Test func aPageShowsItsOwnSpaceEvenWithTheSameName() {
        let first = TabContainer(name: "Work")
        let second = TabContainer(name: "Work")
        let pages = [first, second]
        let found = PageIdentity.object(withID: second.pageID, in: pages, idKeyPath: \.pageID)
        #expect(found?.id == second.id)
    }

    @Test func renamingASpaceKeepsItsPage() {
        let space = TabContainer(name: "Work")
        let before = space.pageID
        space.name = "Home"
        #expect(space.pageID == before)
    }

    @Test func anUnknownPageFindsNoSpace() {
        let pages = [TabContainer(name: "Work")]
        let found = PageIdentity.object(withID: UUID().uuidString, in: pages, idKeyPath: \.pageID)
        #expect(found == nil)
    }
}
