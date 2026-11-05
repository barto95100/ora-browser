import AppKit
import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// A `target="_blank"` link clicked in a pinned tab, to another site,
    /// opens in Peek like a plain link (it used to open a new tab). WebKit
    /// only asks for a new window on a real click, so the page's side is a
    /// manual test.
    @MainActor
    struct PeekNewWindowLink {
        private func withPeekSetting(_ behavior: PinnedLinkBehavior, _ body: () async throws -> Void) async rethrows {
            let settings = SettingsStore.shared
            let saved = settings.pinnedLinkBehavior
            settings.pinnedLinkBehavior = behavior
            defer { settings.pinnedLinkBehavior = saved }
            try await body()
        }

        @Test func blankLinkFromPinnedTabOpensPeek() async throws {
            try await withPeekSetting(.peek) {
                try await TabManagerTestWindow.run { window in
                    let pinned = try await window.openLoaded("pinned")
                    window.tabManager.togglePinTab(pinned)
                    let page = try #require(pinned.browserPage)
                    let delegate = try #require(page.delegate)
                    let store = try #require(URL(string: "https://store.example/product"))
                    defer { window.tabManager.closePeek() }

                    // ⌘-click keeps its meaning: a new tab.
                    #expect(!delegate.browserPage(page, opensNewWindowLink: store, modifierFlags: .command))
                    #expect(window.tabManager.peek == nil)

                    #expect(delegate.browserPage(page, opensNewWindowLink: store, modifierFlags: []))
                    #expect(window.tabManager.peek?.url == store)
                }
            }
        }

        @Test func blankLinkFromNormalTabOrSameSiteOpensATab() async throws {
            try await withPeekSetting(.peek) {
                try await TabManagerTestWindow.run { window in
                    let normal = try await window.openLoaded("normal")
                    let page = try #require(normal.browserPage)
                    let delegate = try #require(page.delegate)
                    let store = try #require(URL(string: "https://store.example/product"))
                    #expect(!delegate.browserPage(page, opensNewWindowLink: store, modifierFlags: []))

                    window.tabManager.togglePinTab(normal)
                    let sameSite = TabManagerTestWindow.url("other-page")
                    #expect(!delegate.browserPage(page, opensNewWindowLink: sameSite, modifierFlags: []))
                    #expect(window.tabManager.peek == nil)
                }
            }
        }

        @Test func newTabSettingKeepsTheNewTab() async throws {
            try await withPeekSetting(.newTab) {
                try await TabManagerTestWindow.run { window in
                    let pinned = try await window.openLoaded("pinned")
                    window.tabManager.togglePinTab(pinned)
                    let page = try #require(pinned.browserPage)
                    let store = try #require(URL(string: "https://store.example/product"))
                    #expect(page.delegate?.browserPage(page, opensNewWindowLink: store, modifierFlags: []) == false)
                }
            }
        }
    }
}
