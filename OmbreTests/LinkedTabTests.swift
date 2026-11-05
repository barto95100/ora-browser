import Foundation
import SwiftData
@testable import Ombre
import Testing
import WebKit

extension TabManagerTests {
    /// A page opening a window without a size (`window.open(url)`, sign-in
    /// and payment pages) gets a tab linked to it, like Safari: `window.open`
    /// returns it, the new page has `window.opener` and can post back (MOT-10).
    @MainActor
    struct LinkedTab {
        private func evaluate(_ script: String, in page: BrowserPage) async -> Any? {
            await withCheckedContinuation { continuation in
                page.extensionWebView.evaluateJavaScript(script, in: nil, in: .page) { result in
                    continuation.resume(returning: try? result.get())
                }
            }
        }

        @Test func windowOpenGivesALinkedTab() async throws {
            try await TabManagerTestWindow.run { window in
                let opener = try await window.openLoaded("opener")
                let page = try #require(opener.browserPage)
                page.extensionWebView.loadHTMLString("<p>opener</p>", baseURL: TabManagerTestWindow.url("opener"))
                await window.waitUntil("page loaded") { !page.extensionWebView.isLoading }
                // Without a click: allowed here, so the test can open it.
                page.extensionWebView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
                let tabsBefore = try window.activeSpace.tabs.count
                await window.waitUntil("protections ready") { page.isReadyForNavigation }

                let opened = await evaluate(
                    "window.child = window.open('about:blank'); String(window.child !== null)", in: page
                ) as? String

                #expect(opened == "true")
                let space = try window.activeSpace
                #expect(space.tabs.count == tabsBefore + 1)
                let linked = try #require(space.tabs.first { $0.id != opener.id && $0.isWebViewReady })
                let linkedPage = try #require(linked.browserPage)
                #expect(await evaluate("String(window.opener !== null)", in: linkedPage) as? String == "true")
                // Its page is its own, with the app's scripts (they report to
                // its tab, not the opener's).
                #expect(linkedPage !== page)
                let scripts = await withCheckedContinuation { continuation in
                    linkedPage.evaluateJavaScript("typeof window.__media") { value, _ in
                        continuation.resume(returning: value as? String)
                    }
                }
                #expect(scripts == "object")
                // Protected from its first request: its opener's content rules.
                #expect(linkedPage.spaceContentRuleLists.map(\.identifier) == page.spaceContentRuleLists
                    .map(\.identifier))
            }
        }

        /// A page WebKit is about to load isn't in the history yet (a sign-in
        /// address before its redirects, say): it is once loaded.
        @Test func linkedTabIsRecordedOnlyOnceLoaded() async throws {
            try await TabManagerTestWindow.run { window in
                let opener = try await window.openLoaded("opener")
                let page = try #require(opener.browserPage)
                page.extensionWebView.loadHTMLString("<p>opener</p>", baseURL: TabManagerTestWindow.url("opener"))
                await window.waitUntil("page loaded") { !page.extensionWebView.isLoading }
                page.extensionWebView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
                // Never loads: the test port refuses it.
                let target = TabManagerTestWindow.url("linked")

                _ = await evaluate("window.open('\(target.absoluteString)'); true", in: page)
                try await Task.sleep(for: .milliseconds(300))

                // The tab is there, its page not in the history.
                #expect(try window.activeSpace.tabs.contains { $0.url == target })
                let visits = try window.modelContext.fetch(FetchDescriptor<History>())
                #expect(!visits.contains { $0.url == target })
            }
        }
    }
}
