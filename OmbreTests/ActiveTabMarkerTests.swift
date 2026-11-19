import Foundation
@testable import Ombre
import Testing

/// The pill pointing to the active tab out of the sidebar's view.
@MainActor
struct ActiveTabMarkerTests {
    private let tab = UUID()
    /// The list shows 200 to 600 of its 1000 points.
    private let viewport = ActiveTabMarker.Viewport(
        visible: CGRect(x: 0, y: 200, width: 220, height: 400),
        contentHeight: 1000
    )

    private func row(at minY: CGFloat) -> CGRect {
        CGRect(x: 0, y: minY, width: 220, height: 36)
    }

    // MARK: - Where it shows

    @Test func aRowHigherShowsThePillAtTheTop() {
        #expect(ActiveTabMarker.edge(of: row(at: 40), in: viewport.visible) == .top)
    }

    @Test func aRowLowerShowsThePillAtTheBottom() {
        #expect(ActiveTabMarker.edge(of: row(at: 800), in: viewport.visible) == .bottom)
    }

    @Test func aRowInViewShowsNoPill() {
        #expect(ActiveTabMarker.edge(of: row(at: 300), in: viewport.visible) == nil)
    }

    /// Half in view counts as in view; less than half does not.
    @Test func aRowHalfInViewIsInView() {
        #expect(ActiveTabMarker.edge(of: row(at: 190), in: viewport.visible) == nil)
        #expect(ActiveTabMarker.edge(of: row(at: 170), in: viewport.visible) == .top)
        #expect(ActiveTabMarker.edge(of: row(at: 575), in: viewport.visible) == nil)
        #expect(ActiveTabMarker.edge(of: row(at: 590), in: viewport.visible) == .bottom)
    }

    /// Not laid out yet: no pill.
    @Test func anEmptyListShowsNoPill() {
        #expect(ActiveTabMarker.edge(of: row(at: 800), in: .zero) == nil)
    }

    // MARK: - Where it leads

    @Test func aTabOutsideFoldersLeadsToItsRow() {
        let target = ActiveTabMarker.target(tabID: tab, isFavorite: false, enclosing: [])
        #expect(target == .init(tabID: tab, destinationID: tab))
    }

    /// Favorites are always in view, above the list.
    @Test func aFavoriteHasNoPill() {
        #expect(ActiveTabMarker.target(tabID: tab, isFavorite: true, enclosing: []) == nil)
    }

    @Test func aTabInAnOpenFolderLeadsToItsRow() {
        let folder = ActiveTabMarker.Enclosing(id: UUID(), isFolded: false)
        #expect(ActiveTabMarker.target(tabID: tab, isFavorite: false, enclosing: [folder])?.destinationID == tab)
    }

    @Test func aTabInAClosedFolderLeadsToTheFolder() {
        let folder = ActiveTabMarker.Enclosing(id: UUID(), isFolded: true)
        let target = ActiveTabMarker.target(tabID: tab, isFavorite: false, enclosing: [folder])
        #expect(target == .init(tabID: tab, destinationID: folder.id))
    }

    /// The outermost closed folder: the ones inside it have no row.
    @Test(arguments: [true, false])
    func nestedFoldersLeadToTheOutermostClosedOne(isInnerFolded: Bool) {
        let inner = ActiveTabMarker.Enclosing(id: UUID(), isFolded: isInnerFolded)
        let outer = ActiveTabMarker.Enclosing(id: UUID(), isFolded: true)
        let target = ActiveTabMarker.target(tabID: tab, isFavorite: false, enclosing: [inner, outer])
        #expect(target?.destinationID == outer.id)
    }

    /// The outer folder open: the closed one inside it.
    @Test func aClosedFolderInAnOpenOneLeadsToTheClosedOne() {
        let inner = ActiveTabMarker.Enclosing(id: UUID(), isFolded: true)
        let outer = ActiveTabMarker.Enclosing(id: UUID(), isFolded: false)
        let target = ActiveTabMarker.target(tabID: tab, isFavorite: false, enclosing: [inner, outer])
        #expect(target?.destinationID == inner.id)
    }

    @Test func aTabInAFoldedGroupLeadsToTheGroup() {
        let group = ActiveTabMarker.Enclosing(id: UUID(), isFolded: true)
        #expect(ActiveTabMarker.target(tabID: tab, isFavorite: false, enclosing: [group])?.destinationID == group.id)
    }

    // MARK: - Scrolling

    @Test func theRowComesToTheMiddle() {
        // Row from 700 to 736: its middle (718) at the middle of 400 points.
        #expect(ActiveTabMarker.offset(centering: row(at: 700), in: viewport) == 518)
    }

    @Test func theScrollStaysWithinTheList() {
        #expect(ActiveTabMarker.offset(centering: row(at: 20), in: viewport) == 0)
        #expect(ActiveTabMarker.offset(centering: row(at: 960), in: viewport) == 600)
    }

    // MARK: - State

    @Test func theStateFollowsTheTabsRowAndScrollsToTheDestination() {
        let folder = UUID()
        let state = ActiveTabMarkerState()
        let reporter = UUID()
        state.target = .init(tabID: tab, destinationID: folder)
        state.viewport = viewport
        #expect(state.edge == nil)

        state.report(row(at: 760), for: tab, by: reporter)
        #expect(state.edge == .bottom)
        // Scrolls to the folder's row, above the tab's.
        state.report(row(at: 716), for: folder, by: reporter)
        #expect(state.destinationOffset == 534)

        // Scrolled to it: the pill goes.
        state.viewport = .init(visible: CGRect(x: 0, y: 534, width: 220, height: 400), contentHeight: 1000)
        #expect(state.edge == nil)
    }

    /// The same tab's row drawn again (a folder opening): the row leaving
    /// doesn't erase the new one's frame.
    @Test func aRowLeavingKeepsTheNewRowsFrame() {
        let state = ActiveTabMarkerState()
        state.target = .init(tabID: tab, destinationID: tab)
        state.viewport = viewport
        let old = UUID()
        let new = UUID()
        state.report(row(at: 40), for: tab, by: old)
        state.report(row(at: 800), for: tab, by: new)
        state.remove(tab, by: old)
        #expect(state.edge == .bottom)
        state.remove(tab, by: new)
        #expect(state.edge == nil)
    }

    @Test func noTargetNoPill() {
        let state = ActiveTabMarkerState()
        state.target = .init(tabID: tab, destinationID: tab)
        state.viewport = viewport
        state.report(row(at: 40), for: tab, by: UUID())
        #expect(state.edge == .top)
        state.target = nil
        #expect(state.edge == nil)
        #expect(state.destinationOffset == nil)
    }
}
