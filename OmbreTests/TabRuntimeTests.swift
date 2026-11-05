import Foundation
import Observation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// A tab's state in its window (`TabRuntime`, ONG-05): kept by the
    /// window, gone with the tab's page.
    @MainActor
    struct Runtime {
        @Test func windowKeepsOneRuntimePerTab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try #require(window.tabManager.activeContainer)
                let first = window.addUnloadedTab("first", order: 1, in: space)
                let second = window.addUnloadedTab("second", order: 2, in: space)
                let manager = window.tabManager

                // Reading it, or a page state, doesn't make one: a page does.
                #expect(first.runtime == nil)
                #expect(first.browserPage == nil)
                #expect(!first.isWebViewReady)
                first.isWebViewReady = false
                #expect(first.runtime == nil)
                let runtime = manager.runtime(for: first)
                #expect(first.runtime === runtime)
                #expect(manager.runtime(for: first) === runtime)
                #expect(manager.runtime(for: second) !== runtime)
            }
        }

        /// The page's view keeps watching the same runtime when the page is
        /// rebuilt (new privacy settings, unloaded then shown): it is reset,
        /// not replaced.
        @Test func runtimeOutlivesThePage() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("page")
                let runtime = window.tabManager.runtime(for: tab)
                runtime.navigationFailed(URLError(.cannotConnectToHost), url: tab.url)
                runtime.setHoveredLink("https://example.com/")

                tab.destroyWebView()

                #expect(tab.runtime === runtime)
                #expect(runtime.navigationFailure == nil)
                #expect(runtime.hoveredLinkURL == nil)
            }
        }

        /// An error arriving after the page went is not kept for later.
        @Test func errorAfterThePageWentIsDropped() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("page")
                let runtime = window.tabManager.runtime(for: tab)

                tab.setNavigationError(URLError(.timedOut), for: tab.url)
                await window.waitUntil("error shown") { runtime.navigationFailure != nil }

                tab.destroyWebView()
                tab.setNavigationError(URLError(.timedOut), for: tab.url)
                // The error is handed over on the main queue: after this turn.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                #expect(runtime.navigationFailure == nil)
            }
        }

        @Test func runtimeGoesWithTheTab() async throws {
            try await TabManagerTestWindow.run { window in
                let other = try window.open("other")
                let tab = try window.open("closing")
                _ = window.tabManager.runtime(for: tab)
                _ = window.tabManager.runtime(for: other)

                await window.close(tab)

                #expect(window.tabManager.existingRuntime(for: tab.id) == nil)
                #expect(window.tabManager.existingRuntime(for: other.id) != nil)
            }
        }

        @Test func closingTheWindowDropsEveryRuntime() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try window.open("page")
                _ = window.tabManager.runtime(for: tab)

                window.tabManager.tearDown()

                #expect(window.tabManager.runtimes.isEmpty)
            }
        }

        /// The page lives in the window's runtime; a view reading it through
        /// the tab redraws when it changes, even if the runtime came later.
        @Test func pageLivesInTheRuntime() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try #require(window.tabManager.activeContainer)
                let tab = window.addUnloadedTab("page", order: 1, in: space)
                var redrawn = false
                withObservationTracking { _ = tab.isWebViewReady } onChange: { redrawn = true }

                tab.isWebViewReady = true

                #expect(redrawn)
                let runtime = try #require(tab.runtime)
                #expect(runtime.isPageReady)

                redrawn = false
                withObservationTracking { _ = tab.showsCrashRecoveryNotice } onChange: { redrawn = true }
                runtime.showsCrashRecoveryNotice = true
                #expect(redrawn)
                #expect(tab.showsCrashRecoveryNotice)

                tab.destroyWebView()
                #expect(tab.runtime === runtime)
                #expect(runtime.page == nil)
                #expect(!tab.isWebViewReady)
                #expect(!tab.showsCrashRecoveryNotice)
            }
        }

        /// A hovered link redraws the page's overlay, not what reads the
        /// page's state through the tab (sidebar, URL bar).
        @Test func hoveredLinkLeavesTheTabsReadersAlone() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("page")
                let runtime = try #require(tab.runtime)
                var redrawn = false
                withObservationTracking {
                    _ = tab.isWebViewReady
                    _ = tab.browserPage
                } onChange: { redrawn = true }

                runtime.setHoveredLink("https://example.com/")

                #expect(!redrawn)
            }
        }

        /// Closing a tab that was never loaded leaves no runtime behind.
        @Test func unloadedTabGetsNoRuntime() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try #require(window.tabManager.activeContainer)
                let tab = window.addUnloadedTab("pinned", type: .pinned, order: 1, in: space)

                tab.destroyWebView()

                #expect(tab.runtime == nil)
                #expect(window.tabManager.existingRuntime(for: tab.id) == nil)
            }
        }

        /// Every change redraws the page's overlays: only real ones count.
        @Test func hoveredLinkChangesOnlyWhenDifferent() {
            let runtime = TabRuntime()
            var changes = 0
            withObservationTracking { _ = runtime.hoveredLinkURL } onChange: { changes += 1 }
            runtime.setHoveredLink(nil)
            runtime.setHoveredLink("")
            #expect(changes == 0)

            runtime.setHoveredLink("https://example.com/")
            #expect(changes == 1)
            #expect(runtime.hoveredLinkURL == "https://example.com/")

            withObservationTracking { _ = runtime.hoveredLinkURL } onChange: { changes += 1 }
            runtime.setHoveredLink("https://example.com/")
            #expect(changes == 1)
            runtime.setHoveredLink(nil)
            #expect(changes == 2)
        }

        @Test func failureIsClearedOnce() {
            let runtime = TabRuntime()
            runtime.navigationFailed(URLError(.notConnectedToInternet), url: URL(string: "https://example.com/"))
            #expect(runtime.navigationFailure?.url?.host == "example.com")

            var changes = 0
            withObservationTracking { _ = runtime.navigationFailure } onChange: { changes += 1 }
            runtime.clearNavigationFailure()
            #expect(changes == 1)
            withObservationTracking { _ = runtime.navigationFailure } onChange: { changes += 1 }
            runtime.clearNavigationFailure()

            #expect(runtime.navigationFailure == nil)
            #expect(changes == 1)
        }
    }
}
