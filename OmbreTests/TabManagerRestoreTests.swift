import AppKit
import Foundation
@testable import Ombre
import SwiftData
import Testing

extension TabManagerTests {
    /// Reopening closed tabs (⌘Z, "Undo Close Tab").
    @MainActor
    struct Restore {
        @Test func restoreLastTabBringsBackTheClosedTab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let kept = try await window.openLoaded("kept")
                let closed = try await window.openLoaded("closed")
                closed.title = "Closed page"
                let closedID = closed.id
                let closedOrder = closed.order
                await window.close(closed)
                #expect(window.tabManager.activeTab?.id == kept.id)

                window.tabManager.restoreLastTab()

                let restored = try #require(window.tabs(withID: closedID).first)
                #expect(restored !== closed)
                #expect(restored.url == TabManagerTestWindow.url("closed"))
                #expect(restored.title == "Closed page")
                #expect(restored.order == closedOrder)
                #expect(restored.type == .normal)
                #expect(restored.container.id == space.id)
                #expect(window.tabManager.activeTab?.id == closedID)
                // Only tabs at or above its order move up: "kept" is below.
                #expect(kept.order == 1)
                #expect(space.tabs.count == 2)
            }
        }

        /// ⌘Z before the closed tab is deleted (its media is still being
        /// stopped) cancels the close.
        @Test func restoreBeforeTheCloseEndsKeepsTheRestoredTab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                _ = try await window.openLoaded("kept")
                let closed = try await window.openLoaded("closed")
                let closedID = closed.id
                window.tabManager.closeTab(tab: closed)

                window.tabManager.restoreLastTab()
                // Long enough for the close to have ended.
                try await Task.sleep(for: .seconds(1))
                try window.modelContext.save()

                // The close was cancelled: the same tab is back.
                #expect(window.tabs(withID: closedID).map(ObjectIdentifier.init) == [ObjectIdentifier(closed)])
                #expect(!closed.isClosing)
                // Its page was torn down by the close, then loaded again.
                #expect(closed.browserPage != nil)
                #expect(closed.isWebViewReady)
                #expect(space.tabs.contains { $0.id == closedID })
                #expect(window.tabManager.activeTab?.id == closedID)
            }
        }

        @Test func restoreShiftsTabsAtOrAboveTheRestoredOrder() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let closed = window.addUnloadedTab("closed", order: 1, in: space)
                let above = window.addUnloadedTab("above", order: 2, in: space)
                await window.close(closed)
                let newcomer = try window.open("newcomer", focus: false)
                #expect(newcomer.order == 2)

                window.tabManager.restoreLastTab()

                #expect(above.order == 3)
                #expect(newcomer.order == 3)
                #expect(window.tabs(withID: closed.id).first?.order == 1)
            }
        }

        @Test func restoreIsLastInFirstOutAndKeepsFiveTabs() async throws {
            try await TabManagerTestWindow.run { window in
                // Nothing closed yet: nothing happens.
                window.tabManager.restoreLastTab()
                #expect(try window.activeSpace.tabs.isEmpty)
                #expect(window.tabManager.activeTab == nil)

                var closedIDs: [UUID] = []
                for index in 1 ... 7 {
                    let tab = try window.open("tab\(index)", focus: false)
                    closedIDs.append(tab.id)
                    await window.close(tab)
                }

                var restoredIDs: [UUID] = []
                for _ in 1 ... 6 {
                    window.tabManager.restoreLastTab()
                    if let id = window.tabManager.activeTab?.id, restoredIDs.last != id {
                        restoredIDs.append(id)
                    }
                }

                // The last five, newest first; the two oldest are forgotten.
                #expect(restoredIDs == Array(closedIDs.suffix(5).reversed()))
                #expect(try window.activeSpace.tabs.count == 5)
            }
        }

        @Test func closingRegistersUndoCloseTabInWindowUndoManager() async throws {
            try await TabManagerTestWindow.run { window in
                let undoManager = UndoManager()
                undoManager.groupsByEvent = false
                window.tabManager.windowUndoManager = undoManager
                let closed = try window.open("closed", focus: false)
                let closedID = closed.id

                undoManager.beginUndoGrouping()
                window.tabManager.closeTab(tab: closed)
                undoManager.endUndoGrouping()
                await window.waitUntilClosed(closed)

                #expect(undoManager.canUndo)
                #expect(undoManager.undoActionName == "Close Tab")
                undoManager.undo()
                #expect(window.tabs(withID: closedID).count == 1)
                #expect(window.tabManager.activeTab?.id == closedID)
            }
        }

        @Test func restoreGoesToActiveSpaceWhenItsSpaceIsGone() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                let work = window.createSpace("Work")
                let closed = try window.open("closed", focus: false)
                let closedID = closed.id
                await window.close(closed)
                window.tabManager.activateContainer(defaultSpace)
                // The space is gone (deleted from the database).
                window.modelContext.delete(work)
                try window.modelContext.save()

                window.tabManager.restoreLastTab()

                let restored = try #require(window.tabs(withID: closedID).first)
                #expect(restored.container.id == defaultSpace.id)
                #expect(window.tabManager.activeContainer?.id == defaultSpace.id)
                #expect(window.tabManager.activeTab?.id == closedID)
            }
        }
    }
}
