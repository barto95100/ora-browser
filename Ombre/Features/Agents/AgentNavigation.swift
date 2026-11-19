import Foundation

/// A tab after an agent's navigation or wait.
struct AgentNavigationReply: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    /// Why the page's last load failed (it shows an error), if it did.
    var loadError: String?
}

/// Agents going back, forward, reloading, and waiting for a page: they only
/// drive Ombre (no page action). Each answers once the load it started is
/// over (`AgentPageActions.loadWait` at most, then as it is).
///
/// `wait` must not answer at once after a click on a link, the old page being
/// loaded: the click's load may start a moment after the click's reply. So
/// every command marks the page when it ends (`BrowserPage.agentMark`), and
/// `wait` waits for the end of a load started since that mark, or starting
/// within `grace` after it is asked; with none, it answers then.
@MainActor
enum AgentNavigation {
    enum Move {
        case back
        case forward
        case reload
    }

    /// A load not started by then won't be: a link's starts within a few
    /// milliseconds of the click (the tests set their own).
    static var grace: Duration = .seconds(1)
    /// `wait`'s limit without one given, and the longest one (within the
    /// two minutes osascript waits, with the user's question).
    static let defaultTimeout = 10
    static let maxTimeout = 60

    static func go(_ move: Move, in tab: Tab) async -> Result<String, AgentError> {
        guard let page = tab.browserPage, tab.isWebViewReady else { return .failure(.notLoaded) }
        if let refusal = refusal(of: move, on: page) { return .failure(refusal) }
        let mark = page.navigationMark
        switch move {
        case .back: page.goBack()
        case .forward: page.goForward()
        case .reload: page.reload()
        }
        _ = await page.waitForNavigation(since: mark, grace: grace, within: AgentPageActions.loadWait)
        guard tab.browserPage === page else { return .failure(.notLoaded) }
        return .success(reply(for: tab))
    }

    /// Why `move` can't be done on `page`, if it can't: nothing done then.
    private static func refusal(of move: Move, on page: BrowserPage) -> AgentError? {
        let list = page.webView.backForwardList
        switch move {
        case .back:
            guard let item = list.backItem else { return .nothingBack }
            return isWebPage(item.url) ? nil : .notWebDestination
        case .forward:
            guard let item = list.forwardItem else { return .nothingForward }
            return isWebPage(item.url) ? nil : .notWebDestination
        case .reload:
            // WebKit would send the form again without asking.
            return page.showsFormResult ? .formResubmission : nil
        }
    }

    /// Waits for the load started since the agent's last command on the page
    /// (or within `grace`), then for an element `selector` matches, if any.
    static func wait(for selector: String?, in tab: Tab, timeout: Int?) async -> Result<String, AgentError> {
        let seconds = timeout ?? defaultTimeout
        guard (1 ... maxTimeout).contains(seconds) else { return .failure(.badTimeout) }
        // A page not ready yet (a tab just opened) is waited for too.
        guard let page = tab.browserPage else { return .failure(.notLoaded) }
        let limit = Duration.seconds(seconds)
        let deadline = ContinuousClock.now + limit
        let mark = page.agentMark ?? page.navigationMark
        let end = await page.waitForNavigation(since: mark, grace: grace, within: limit)
        guard tab.browserPage === page, tab.isWebViewReady else { return .failure(.notLoaded) }
        guard let selector else {
            return end == .stillLoading ? .failure(.stillLoading(after: seconds)) : .success(reply(for: tab))
        }
        let found = await element(selector, on: page, until: deadline)
        guard tab.browserPage === page else { return .failure(.notLoaded) }
        switch found {
        case let .success(element):
            return .success(AgentCommands.action(element, in: tab))
        case let .failure(error):
            let error = error == .noElement ? .nothingMatched(in: seconds) : error
            // No element on an error page: the reason is the failed load.
            return .failure(AgentCommands.loadError(of: tab).map { error.afterFailedLoad($0) } ?? error)
        }
    }

    /// The first element `selector` matches, waited for until `deadline`;
    /// looked for again in the next document if the page changes meanwhile.
    private static func element(
        _ selector: String,
        on page: BrowserPage,
        until deadline: ContinuousClock.Instant
    ) async -> Result<String, AgentError> {
        while true {
            // A second more to answer: the element is waited for till the deadline.
            let found = await AgentPageActions.waitFor(selector, on: page, until: deadline + .seconds(1))
            guard found == .failure(.pageChanged) else { return found }
            let left = deadline - .now
            guard left > .zero else { return .failure(.noElement) }
            _ = await page.waitUntilLoaded(within: left)
        }
    }

    private static func reply(for tab: Tab) -> String {
        AgentCommands.json(AgentNavigationReply(
            id: tab.id.uuidString,
            title: tab.title,
            address: tab.url.absoluteString,
            loadError: AgentCommands.loadError(of: tab)
        ))
    }

    private static func isWebPage(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// "1 second", "10 seconds" (for the agent: English).
    nonisolated static func duration(_ seconds: Int) -> String {
        seconds == 1 ? "1 second" : "\(seconds) seconds" // not shown
    }
}
