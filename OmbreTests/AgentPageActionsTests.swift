import Foundation
@testable import Ombre
import Testing
import WebKit

/// Page actions of agents, in a real page (private: nothing on disk, no
/// window): click, fill in, JavaScript, in a world of their own.
@MainActor
@Suite(.serialized)
struct AgentPageActionsTests {
    private static let html = """
    <html><body>
    <button id="go" onclick="window.clicks = (window.clicks || 0) + 1">Go</button>
    <input id="name" type="text">
    <input id="secret" type="password" value="kept">
    <input id="box" type="checkbox">
    <textarea id="note"></textarea>
    <select id="size"><option value="s">S</option><option value="l">L</option></select>
    <div id="edit" contenteditable="true"></div>
    <input id="locked" type="text" readonly value="fixed">
    <input id="count" type="number" value="42">
    <fieldset disabled><input id="inset" type="text"></fieldset>
    <button id="off" disabled>Off</button>
    <input id="token" type="hidden" value="csrf-token">
    <button id="icon" onclick="window.icon = 1"><svg width="10" height="10"><path id="dot" d="M0 0h10v10z"/></svg></button>
    <script>
    window.pageSecret = 'page';
    window.inputs = 0;
    document.getElementById('name').addEventListener('input', () => { window.inputs += 1; });
    </script>
    </body></html>
    """

    private func makePage() -> BrowserPage {
        let privacy = SpacePrivacySettings()
        return BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: privacy,
                enablesWebNotifications: true
            ),
            delegate: nil
        )
    }

    /// As the page itself would.
    private func inPage(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.extensionWebView.evaluateJavaScript(script, in: nil, in: .page) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    /// Loads the test page and waits for its script.
    private func loadedPage() async throws -> BrowserPage {
        let page = makePage()
        page.extensionWebView.loadHTMLString(Self.html, baseURL: URL(string: "https://example.com/"))
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if await inPage(page, "window.pageSecret") as? String == "page" { return page }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The page never loaded")
        return page
    }

    @Test func clickClicksTheFirstMatch() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        #expect(await AgentPageActions.click("#go", on: page) == .success("button#go \"Go\""))
        #expect(await inPage(page, "window.clicks") as? Int == 1)
        #expect(await AgentPageActions.click("#missing", on: page) == .failure(.noElement))
        #expect(await AgentPageActions.click("[[nope", on: page) == .failure(.badSelector))
        #expect(await AgentPageActions.click("#off", on: page) == .failure(.disabledElement))
        // An SVG icon in a button: its click reaches the button.
        #expect(await AgentPageActions.click("#icon path", on: page) == .success("path#dot"))
        #expect(await inPage(page, "window.icon") as? Int == 1)
    }

    /// The reply never holds a field's value: a password, a hidden token.
    @Test func aFieldsValueIsNeverInTheReply() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        #expect(await AgentPageActions.click("#secret", on: page) == .success("input#secret"))
        #expect(await AgentPageActions.click("#token", on: page) == .success("input#token"))
    }

    /// Filled as typing would: the page's own listener sees it.
    @Test func fillSetsTheFieldAndTellsThePage() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        #expect(await AgentPageActions.fill("#name", with: "Ludo", on: page) == .success("input#name"))
        #expect(await inPage(page, "document.getElementById('name').value") as? String == "Ludo")
        #expect(await inPage(page, "window.inputs") as? Int == 1)
        _ = await AgentPageActions.fill("#note", with: "two\nlines", on: page)
        #expect(await inPage(page, "document.getElementById('note').value") as? String == "two\nlines")
        _ = await AgentPageActions.fill("#size", with: "l", on: page)
        #expect(await inPage(page, "document.getElementById('size').value") as? String == "l")
        _ = await AgentPageActions.fill("#edit", with: "text", on: page)
        #expect(await inPage(page, "document.getElementById('edit').textContent") as? String == "text")
    }

    @Test func passwordFieldsAndButtonsAreNeverFilled() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        #expect(await AgentPageActions.fill("#secret", with: "x", on: page) == .failure(.passwordField))
        #expect(await inPage(page, "document.getElementById('secret').value") as? String == "kept")
        #expect(await AgentPageActions.fill("#box", with: "x", on: page) == .failure(.notFillable))
        #expect(await AgentPageActions.fill("#go", with: "x", on: page) == .failure(.notFillable))
    }

    /// Nothing filled is never said filled.
    @Test func aFieldThatKeepsItsValueIsSaid() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        #expect(await AgentPageActions.fill("#locked", with: "x", on: page) == .failure(.readOnlyField))
        #expect(await inPage(page, "document.getElementById('locked').value") as? String == "fixed")
        #expect(await AgentPageActions.fill("#size", with: "xl", on: page) == .failure(.noOption))
        #expect(await inPage(page, "document.getElementById('size').value") as? String == "s")
        #expect(await AgentPageActions.fill("#inset", with: "x", on: page) == .failure(.readOnlyField))
        #expect(await AgentPageActions.fill("#count", with: "twelve", on: page) == .failure(.valueRefused))
        // Put back as it was.
        #expect(await inPage(page, "document.getElementById('count').value") as? String == "42")
        // A text field takes the text as given.
        #expect(await AgentPageActions.fill("#name", with: "Ludo", on: page) == .success("input#name"))
        #expect(await AgentPageActions.fill("#count", with: "12", on: page) == .success("input#count"))
    }

    /// The code is an async function's body; its result comes back as JSON.
    @Test func javaScriptGivesItsResultAsJSON() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        #expect(await AgentPageActions.run("return 1 + 1", on: page) == .success("2"))
        #expect(await AgentPageActions.run("return true", on: page) == .success("true"))
        #expect(await AgentPageActions.run("return () => 1", on: page) == .failure(.unsupportedResult))
        #expect(await AgentPageActions.run("return { b: [1, 'x'], a: null }", on: page)
            == .success(#"{"b":[1,"x"],"a":null}"#))
        #expect(await AgentPageActions.run("await Promise.resolve(); return document.title", on: page)
            == .success(#""""#))
        #expect(await AgentPageActions.run("document.title = 'Set'", on: page) == .success("null"))
        #expect(await inPage(page, "document.title") as? String == "Set")
    }

    /// Its own world: the page's variables and the app's scripts and
    /// handlers aren't there.
    @Test func javaScriptRunsApartFromThePageAndTheApp() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        // The app's script is there, in its own world.
        let inApp = await withCheckedContinuation { continuation in
            page.evaluateJavaScript("typeof window.__passwordManager") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
        #expect(inApp == "object")
        #expect(await AgentPageActions.run("return typeof window.pageSecret", on: page) == .success(#""undefined""#))
        #expect(await AgentPageActions.run("return typeof window.__passwordManager", on: page)
            == .success(#""undefined""#))
        let handlers = await AgentPageActions.run(
            "return typeof (window.webkit && window.webkit.messageHandlers.passwordManager)", on: page
        )
        #expect(handlers == .success(#""undefined""#))
        #expect(await AgentPageActions.run("return document.getElementById('go').textContent", on: page)
            == .success(#""Go""#))
    }

    @Test func javaScriptFailuresAreSaid() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }

        guard case let .failure(error) = await AgentPageActions.run("throw new Error('boom')", on: page) else {
            Issue.record("No failure")
            return
        }
        #expect(error.message.hasPrefix("The script failed:"))
        // What it threw, for the agent.
        #expect(error.message.hasSuffix("Error: boom"))
        #expect(error.mayHaveActed)
        #expect(AgentError.timedOut.mayHaveActed)
        #expect(!AgentError.noElement.mayHaveActed)
        // The log never gets what the page or the code said.
        #expect(error.logged == "The script failed.")
        #expect(await AgentPageActions.run("return 'x'.repeat(100001)", on: page) == .failure(.resultTooLong))
    }

    @Test func aScriptThatNeverAnswersIsGivenUp() async throws {
        let page = try await loadedPage()
        defer { page.teardown() }
        let saved = AgentPageActions.timeout
        AgentPageActions.timeout = .milliseconds(200)
        defer { AgentPageActions.timeout = saved }

        #expect(await AgentPageActions.run("await new Promise(() => {})", on: page) == .failure(.timedOut))
    }

    @Test func resultsAreJSONOnly() {
        #expect(AgentPageActions.json(NSNull()) == "null")
        #expect(AgentPageActions.json("a/b") == #""a/b""#)
        #expect(AgentPageActions.json(Date()) == nil)
    }
}
