import Foundation
@testable import Ombre
import Testing

@MainActor
struct SpacePageIdentityTests {
    @Test func twoSpacesWithTheSameNameHaveDifferentPages() {
        let first = TabContainer(name: "Work")
        let second = TabContainer(name: "Work")
        #expect(first.pageID != second.pageID)
    }

    @Test func renamingASpaceKeepsItsPage() {
        let space = TabContainer(name: "Work")
        let before = space.pageID
        space.name = "Home"
        #expect(space.pageID == before)
    }
}
