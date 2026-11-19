import Foundation
@testable import Ombre
import Testing
import WebKit

extension TabManagerTests {
    /// Agents going back, forward, reloading and waiting, in real pages: each
    /// is given to the tab's page as if a server had sent it (no network).
    @MainActor
    @Suite(.serialized)
    struct AgentNavigationTests {
        private let terminal = AgentSender(key: "com.apple.Terminal", name: "Terminal")

        private func control(_ window: TabManagerTestWindow, pageActions: Bool = false) -> AgentControl {
            let control = AgentControl()
            control.isAllowed = { true }
            control.allowsPageActions = { pageActions }
            control.ask = { _ in true }
            control.tabManager = { window.tabManager }
            return control
        }

        /// A tab agents reach, its own load over (it fails: no server).
        private func webTab(_ window: TabManagerTestWindow, _ control: AgentControl) async throws -> Tab {
            let address = TabManagerTestWindow.url("agent-navigation").absoluteString
            let opened = try await control.run(.open(address), from: terminal).get()
            let id = try #require(AgentPageActions.value(of: opened) as? [String: Any])["id"] as? String
            let tab = try #require(window.spaces().flatMap(\.tabs).first { $0.id.uuidString == id })
            await window.waitUntil("its load over") { tab.browserPage?.hasLoaded == true && tab.isWebViewReady }
            // Without the badge of its opening.
            control.stop()
            return tab
        }

        /// `html` shown at `path`, as a server's answer to `method`.
        private func show(
            _ html: String,
            at path: String,
            method: String = "GET",
            in tab: Tab,
            _ window: TabManagerTestWindow
        ) async throws {
            let page = try #require(tab.browserPage)
            let url = TabManagerTestWindow.url(path)
            var request = URLRequest(url: url)
            request.httpMethod = method
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            ))
            page.webView.loadSimulatedRequest(request, response: response, responseData: Data(html.utf8))
            await window.waitUntil("\(path) shown") { page.webView.url == url && page.hasLoaded }
        }

        private func reply(_ result: Result<String, AgentError>) throws -> AgentNavigationReply {
            try JSONDecoder().decode(AgentNavigationReply.self, from: Data(result.get().utf8))
        }

        @Test func backAndForwardMoveThroughTheHistory() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                let tab = try await webTab(window, control)
                try await show("<title>One</title><p>1</p>", at: "one", in: tab, window)
                try await show("<title>Two</title><p>2</p>", at: "two", in: tab, window)
                let id = tab.id.uuidString

                let back = try await reply(control.run(.goBack(id), from: terminal))
                #expect(back.address == TabManagerTestWindow.url("one").absoluteString)
                #expect(back.id == id)
                // Navigating: the tab gets its badge.
                #expect(control.touchedTabIDs == [tab.id])
                let forward = try await reply(control.run(.goForward(nil), from: terminal))
                #expect(forward.address == TabManagerTestWindow.url("two").absoluteString)
            }
        }

        /// Nothing before or after: said, nothing done, no badge.
        @Test func nothingToGoToIsSaid() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                let tab = try await webTab(window, control)
                try await show("<p>only</p>", at: "only", in: tab, window)
                let id = tab.id.uuidString
                #expect(await control.run(.goBack(id), from: terminal) == .failure(.nothingBack))
                #expect(await control.run(.goForward(id), from: terminal) == .failure(.nothingForward))
                #expect(AgentError.nothingBack.message == "Nothing to go back to.")
                #expect(AgentError.nothingForward.message == "Nothing to go forward to.")
                #expect(control.touchedTabIDs.isEmpty)
            }
        }

        /// The answer to a form sent with POST: never sent again silently.
        @Test func aFormsAnswerIsNotReloaded() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                let tab = try await webTab(window, control)
                let page = try #require(tab.browserPage)
                try await show("<p>sent</p>", at: "sent", method: "POST", in: tab, window)
                let loads = page.loadStarts
                #expect(await control.run(.reload(nil), from: terminal) == .failure(.formResubmission))
                #expect(page.loadStarts == loads)
                #expect(control.touchedTabIDs.isEmpty)

                // A page asked for with GET is reloaded.
                try await show("<p>plain</p>", at: "plain", in: tab, window)
                let reload = try await reply(control.run(.reload(tab.id.uuidString), from: terminal))
                #expect(reload.address == TabManagerTestWindow.url("plain").absoluteString)
                #expect(page.loadStarts > loads + 1)
                #expect(control.touchedTabIDs == [tab.id])

                // Back to the form's answer: still not reloaded.
                let back = try await reply(control.run(.goBack(nil), from: terminal))
                #expect(back.address == TabManagerTestWindow.url("sent").absoluteString)
                #expect(await control.run(.reload(nil), from: terminal) == .failure(.formResubmission))
            }
        }

        /// The case agents loop on: a click on a link whose load starts a
        /// moment after the click's reply, the old page being loaded. The
        /// wait is for that load (it fails here: its failure is in the reply).
        @Test func aWaitAfterAClickWaitsForTheLinksLoad() async throws {
            // A page without a window is hidden: WebKit may hold its timers
            // back to the next second, the link's load starting that late.
            let grace = AgentNavigation.grace
            AgentNavigation.grace = .seconds(3)
            defer { AgentNavigation.grace = grace }
            try await TabManagerTestWindow.run { window in
                let control = control(window, pageActions: true)
                let tab = try await webTab(window, control)
                let next = TabManagerTestWindow.url("next").absoluteString
                try await show("""
                <a id="next" href="\(next)" onclick="event.preventDefault();
                    setTimeout(() => { location.href = this.href; }, 300);">Next</a>
                """, at: "links", in: tab, window)
                let id = tab.id.uuidString

                _ = try await control.run(.click(tab: id, selector: "#next"), from: terminal).get()
                let waited = try await reply(control.run(.wait(tab: id, selector: nil, timeout: nil), from: terminal))
                let loadError = try #require(waited.loadError, "The wait answered before the link's load.")
                #expect(loadError.contains("NSURLErrorDomain -1004"), "\(loadError)")
            }
        }

        /// No load since the last command, none starting: answered after
        /// the grace period, without a badge (a wait changes nothing).
        @Test func aWaitWithNothingLoadingAnswers() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                let tab = try await webTab(window, control)
                try await show("<title>Still</title><p>still</p>", at: "still", in: tab, window)
                let clock = ContinuousClock()
                let start = clock.now
                let waited = try await reply(control.run(.wait(tab: nil, selector: nil, timeout: nil), from: terminal))
                #expect(clock.now - start < .seconds(5))
                #expect(waited.address == TabManagerTestWindow.url("still").absoluteString)
                #expect(waited.loadError == nil)
                #expect(control.touchedTabIDs.isEmpty)
            }
        }

        /// With a selector: the element the page adds later, or a clear
        /// error once the timeout is over.
        @Test func aWaitForAnElement() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                let tab = try await webTab(window, control)
                try await show("""
                <script>setTimeout(() => {
                    const el = document.createElement('div'); el.id = 'late'; el.textContent = 'Here';
                    document.body.appendChild(el);
                }, 300);</script>
                """, at: "late", in: tab, window)
                let id = tab.id.uuidString

                let found = try await control.run(.wait(tab: id, selector: "#late", timeout: 5), from: terminal).get()
                let action = try JSONDecoder().decode(AgentAction.self, from: Data(found.utf8))
                #expect(action.element == "div#late \"Here\"")
                #expect(action.address == TabManagerTestWindow.url("late").absoluteString)

                let missing = await control.run(.wait(tab: id, selector: "#never", timeout: 1), from: terminal)
                #expect(missing == .failure(.nothingMatched(in: 1)))
                #expect(AgentError.nothingMatched(in: 1).message == "Nothing matched in 1 second.")
                #expect(AgentError.nothingMatched(in: 10).message == "Nothing matched in 10 seconds.")
                #expect(await control.run(.wait(tab: id, selector: "[[", timeout: 1), from: terminal)
                    == .failure(.badSelector))
                #expect(control.touchedTabIDs.isEmpty)
            }
        }

        @Test(arguments: [0, -3, 61])
        func aTimeoutOutOfRangeIsRefused(timeout: Int) async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window)
                _ = try await webTab(window, control)
                #expect(await control.run(.wait(tab: nil, selector: nil, timeout: timeout), from: terminal)
                    == .failure(.badTimeout))
            }
        }

        /// Only driving: no page action needed; never a private tab, nor a
        /// page that isn't a web page.
        @Test func theRulesOfTheOtherCommands() async throws {
            try await TabManagerTestWindow.run { window in
                let control = control(window, pageActions: false)
                let space = try window.activeSpace
                let privateTab = try window.tabManager.makeTab(
                    url: #require(URL(string: "https://example.com/private")), title: "Private", in: space,
                    isPrivate: true
                )
                let file = try window.tabManager.makeTab(
                    url: #require(URL(string: "file:///Users/someone/notes.html")), title: "Notes", in: space,
                    isPrivate: false
                )
                let commands: (String) -> [AgentCommand] = { id in
                    [.goBack(id), .goForward(id), .reload(id), .wait(tab: id, selector: "p", timeout: 1)]
                }
                for command in commands(privateTab.id.uuidString) {
                    #expect(await control.run(command, from: terminal) == .failure(.noTab))
                    #expect(!command.isPageAction)
                }
                for command in commands(file.id.uuidString) {
                    #expect(await control.run(command, from: terminal) == .failure(.notWebPage))
                }
                #expect(control.touchedTabIDs.isEmpty)
            }
        }
    }
}
