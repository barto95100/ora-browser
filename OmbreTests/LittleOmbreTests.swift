import AppKit
import Foundation
@testable import Ombre
import Testing

/// Little Ombre: a small window with one page, its page going to a tab.
extension TabManagerTests {
    @MainActor
    @Suite(.serialized)
    struct LittleOmbre {
        /// The page stays as it is only in the space whose data it uses, in a
        /// window of the same privacy.
        @Test func thePageIsKeptOnlyInItsOwnSpace() {
            let space = UUID()
            #expect(TabManager.littleOmbreMove(
                pageSpaceID: space,
                pageIsPrivate: false,
                to: space,
                windowIsPrivate: false
            ) == .adopt)
            #expect(TabManager.littleOmbreMove(
                pageSpaceID: space,
                pageIsPrivate: false,
                to: UUID(),
                windowIsPrivate: false
            ) == .reload)
            #expect(TabManager.littleOmbreMove(
                pageSpaceID: space,
                pageIsPrivate: true,
                to: space,
                windowIsPrivate: false
            ) == .reload)
        }

        @Test func linksFromOtherAppsUseItByDefault() {
            let defaults = UserDefaults.standard
            let key = "settings.littleOmbreForLinks"
            let saved = defaults.object(forKey: key)
            defer { defaults.set(saved, forKey: key) }
            defaults.removeObject(forKey: key)
            #expect(SettingsStore().opensLinksInLittleOmbre)
        }

        @Test func itsPageIsTheActiveSpacesWithItsHistory() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("page"),
                    from: window.tabManager,
                    window: nil
                ))
                defer { little.window.close() }
                #expect(little.model.spaceID == space.id)
                #expect(little.popup.history?.space.id == space.id)
                #expect(!little.popup.context.isPrivate)
                #expect(LittleOmbreWindow.isLittleOmbreWindow(little.window))
            }
        }

        /// "Open in Ombre": the same page in a tab of its space (not loaded
        /// again), shown; Little Ombre closes and leaves its page to the tab.
        @Test func openInOmbreMovesThePageToATab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("page"),
                    from: window.tabManager,
                    window: nil
                ))
                let page = little.popup.page
                await window.waitUntil("address known") { page.currentURL != nil }

                let previous = window.tabManager.activeTab?.id
                little.openInOmbre()
                await window.waitUntil("moved to a tab") { !LittleOmbreWindow.isLittleOmbreWindow(little.window) }

                let tab = try #require(window.tabManager.activeTab)
                #expect(tab.id != previous)
                #expect(tab.browserPage === page)
                #expect(tab.container.id == space.id)
                #expect(!LittleOmbreWindow.isLittleOmbreWindow(little.window))
                #expect(page.delegate === tab.pageDelegate)
            }
        }

        /// Another space has its own data: the address loads again there.
        @Test func anotherSpaceLoadsItAgain() async throws {
            try await TabManagerTestWindow.run { window in
                let other = window.createSpace("Other")
                try window.tabManager.activateContainer(#require(window.spaces().first { $0.id != other.id }))
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("page"),
                    from: window.tabManager,
                    window: nil
                ))
                let page = little.popup.page
                await window.waitUntil("address known") { page.currentURL != nil }

                little.openInOmbre(space: other)
                await window.waitUntil("opened in a tab") { !LittleOmbreWindow.isLittleOmbreWindow(little.window) }

                let tab = try #require(window.tabManager.activeTab)
                #expect(tab.container.id == other.id)
                #expect(tab.browserPage !== page)
                #expect(tab.url.lastPathComponent == "page")
            }
        }

        /// A private window's Little Ombre: its session, nothing recorded.
        @Test func aPrivateWindowsOneRecordsNothing() async throws {
            try await TabManagerTestWindow.run { window in
                window.tabManager.isPrivateWindow = true
                defer { window.tabManager.isPrivateWindow = false }
                let little = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: nil))
                defer { little.window.close() }
                #expect(little.popup.context.isPrivate)
                #expect(little.popup.context.privateSession == window.tabManager.privateSessionID)
                #expect(little.popup.history == nil)
            }
        }

        /// Ombre's passwords are offered there, as in a tab of its space.
        @Test func itOffersThePasswordsOfItsSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let little = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: nil))
                defer { little.window.close() }
                let coordinator = try #require(little.popup.passwordCoordinator)
                #expect(coordinator.host === little.popup)
                #expect(little.popup.passwordSpaceID == space.id)
                #expect(coordinator.tab == nil)
            }
        }

        @Test func closingItLeavesNothing() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = window.tabManager.activeContainer?.tabs.count
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("page"),
                    from: window.tabManager,
                    window: nil
                ))
                little.window.close()
                #expect(!LittleOmbreWindow.isLittleOmbreWindow(little.window))
                #expect(window.tabManager.activeContainer?.tabs.count == tabs)
            }
        }
    }
}

extension TabManagerTests {
    /// Little Ombre goes with what its page uses: its window, its space.
    @MainActor
    @Suite(.serialized)
    struct LittleOmbreLifetime {
        @Test func itClosesWithItsWindowAndItsSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let first = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: nil))
                LittleOmbreWindow.closeAll(from: window.tabManager)
                #expect(!LittleOmbreWindow.isLittleOmbreWindow(first.window))

                let space = try window.activeSpace
                let second = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: nil))
                LittleOmbreWindow.closeAll(inSpace: UUID())
                #expect(LittleOmbreWindow.isLittleOmbreWindow(second.window))
                LittleOmbreWindow.closeAll(inSpace: space.id)
                #expect(!LittleOmbreWindow.isLittleOmbreWindow(second.window))
            }
        }
    }
}
