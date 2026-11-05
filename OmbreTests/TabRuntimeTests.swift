import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// A tab's state in its window (`TabRuntime`, ONG-05): kept by the
    /// window, gone with the tab's page.
    @MainActor
    struct Runtime {
        @Test func windowKeepsOneRuntimePerTab() async throws {
            try await TabManagerTestWindow.run { window in
                let first = try window.open("first")
                let second = try window.open("second")
                let manager = window.tabManager

                // Reading it doesn't make one: the page's view does.
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

        /// Every publish redraws the page's overlays: only changes count.
        @Test func hoveredLinkPublishesOnlyChanges() {
            let runtime = TabRuntime()
            var publishes = 0
            let observation = runtime.objectWillChange.sink { publishes += 1 }
            defer { observation.cancel() }

            runtime.setHoveredLink("https://example.com/")
            runtime.setHoveredLink("https://example.com/")
            runtime.setHoveredLink("")
            runtime.setHoveredLink(nil)

            #expect(publishes == 2)
            #expect(runtime.hoveredLinkURL == nil)
        }

        @Test func failureIsClearedOnce() {
            let runtime = TabRuntime()
            var publishes = 0
            let observation = runtime.objectWillChange.sink { publishes += 1 }
            defer { observation.cancel() }

            runtime.navigationFailed(URLError(.notConnectedToInternet), url: URL(string: "https://example.com/"))
            #expect(runtime.navigationFailure?.url?.host == "example.com")
            runtime.clearNavigationFailure()
            runtime.clearNavigationFailure()

            #expect(runtime.navigationFailure == nil)
            #expect(publishes == 2)
        }
    }
}
