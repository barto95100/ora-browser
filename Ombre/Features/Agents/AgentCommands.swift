import AppKit

/// What an agent may ask (see `Ombre.sdef`).
enum AgentCommand: Equatable, Sendable {
    case listTabs
    case open(String)
    case activate(String)
    case close(String)
    /// The active tab without an id.
    case read(String?)
    /// A PNG of the page as it shows; the active tab without an id.
    case capture(String?)
    /// Page actions (their own setting): in a tab, the active one without an id.
    case click(tab: String?, selector: String)
    case fill(tab: String?, selector: String, value: String)
    case runScript(tab: String?, code: String)

    /// Acts in a page: allowed only with page actions on.
    var isPageAction: Bool {
        switch self {
        case .click, .fill, .runScript: true
        default: false
        }
    }

    /// Its name in the logs and the sdef.
    var name: String {
        switch self {
        case .listTabs: "list tabs" // not shown
        case .open: "open address" // not shown
        case .activate: "activate tab" // not shown
        case .close: "close tab" // not shown
        case .read: "read tab" // not shown
        case .capture: "capture tab" // not shown
        case .click: "click element" // not shown
        case .fill: "fill field" // not shown
        case .runScript: "run javascript" // not shown
        }
    }
}

/// Why a command was not done; the text goes back to the agent (English, as
/// Apple Events errors are), never shown in Ombre.
struct AgentError: Error, Equatable {
    let message: String
    /// In the log instead of `message`, when that holds what the page or the
    /// agent's code said.
    var logged: String?

    static let off = AgentError(message: "Agent control is off: turn it on in Settings › General.") // not shown
    static let denied = AgentError(message: "The user denied this app control of Ombre for this session.") // not shown
    static let noWindow =
        AgentError(message: "No Ombre window is open (private windows are never controlled).") // not shown
    static let badAddress = AgentError(message: "Only http and https addresses can be opened.") // not shown
    static let noTab = AgentError(message: "No tab with this id: ask list tabs again.") // not shown
    static let unanswered = AgentError(message: "The user didn't answer in time: try again.") // not shown
    static let noActiveTab = AgentError(message: "No tab is active: give a tab id.") // not shown
    static let notLoaded = AgentError(message: "This tab's page isn't loaded: activate it first.") // not shown
    static let notWebPage =
        AgentError(message: "Only web pages (http, https) can be read, captured or acted on.") // not shown
    static let noImage = AgentError(message: "The page couldn't be captured: show its tab first.") // not shown
    static let actionsOff = AgentError(
        message: "Page actions are off: turn on Allow agents to act in pages in Settings › General." // not shown
    )
    static let badSelector = AgentError(message: "This CSS selector isn't valid.") // not shown
    static let noElement = AgentError(message: "No element matches this selector.") // not shown
    static let passwordField = AgentError(message: "Password fields are never filled by agents.") // not shown
    static let notFillable =
        AgentError(message: "This element isn't a text field, a list or editable text.") // not shown
    static let readOnlyField = AgentError(message: "This field is read-only or disabled.") // not shown
    static let disabledElement = AgentError(message: "This element is disabled.") // not shown
    static let noOption = AgentError(message: "No option of this list has this value.") // not shown
    static let valueRefused =
        AgentError(message: "The field refused this text: it expects another format.") // not shown
    static let timedOut = AgentError(message: "The page didn't answer in 15 seconds.") // not shown
    /// WebKit gave up waiting: the script's promise was freed, or its page left.
    static let promiseDropped =
        AgentError(message: "The script's promise was dropped by the page before it answered.") // not shown
    /// Before the element was found: nothing done.
    static let pageChanged =
        AgentError(message: "The page changed while the element was waited for: try again.") // not shown
    static let unsupportedResult = AgentError(
        message: "The script's result isn't JSON (strings, numbers, booleans, arrays, objects, null)." // not shown
    )
    static let resultTooLong = AgentError(message: "The script's result is over 100,000 characters.") // not shown
    /// The page may have been changed although the command failed: the
    /// agent's script ran (it threw, took too long or gave no JSON).
    var mayHaveActed: Bool {
        let ranTheScript: [AgentError] = [.timedOut, .promiseDropped, .resultTooLong, .unsupportedResult]
        return logged != nil || ranTheScript.map(\.message).contains(message)
    }

    /// The script's own error goes to the agent, not into the log.
    static func scriptFailed(_ reason: String) -> AgentError {
        AgentError(message: "The script failed: \(reason)", logged: "The script failed.") // not shown
    }

    /// Why the page's last load failed, told to the agent after `message`
    /// (never in the log).
    var loadError: String?

    /// What the agent gets.
    var reply: String {
        guard let loadError else { return message }
        return message + " The page's last load failed: \(loadError)" // not shown
    }

    /// The same error, telling why the page's last load failed.
    func afterFailedLoad(_ loadError: String) -> AgentError {
        var error = self
        error.loadError = loadError
        return error
    }

    static func failed(_ reason: String) -> AgentError {
        AgentError(message: "The page couldn't be read: \(reason)") // not shown
    }
}

/// A tab as agents see it.
struct AgentTab: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    /// "normal", "pinned" or "favorite".
    let kind: String
    let active: Bool
}

struct AgentSpace: Codable, Equatable {
    let id: String
    let name: String
    let active: Bool
    let tabs: [AgentTab]
}

/// An element an agent clicked or filled in.
struct AgentAction: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    /// Its tag, id and text, shortened.
    let element: String
    /// Why the page's last load failed (it shows an error), if it did.
    var loadError: String?
}

/// A page's image: a PNG, in base64.
struct AgentCapture: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    let width: Int
    let height: Int
    let png: String
    /// Why the page's last load failed (it shows an error), if it did.
    var loadError: String?
}

struct AgentPage: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    let text: String
    let truncated: Bool
    /// Why the page's last load failed (it shows an error), if it did.
    var loadError: String?
}

/// The commands, done in one window (its `TabManager`): its normal tabs only,
/// a normal window being the only one agents get.
@MainActor
enum AgentCommands {
    /// A page's text is cut there.
    static let maxTextLength = 100_000

    /// What a command did.
    struct Done {
        let result: Result<String, AgentError>
        /// The site it touched (for the log).
        let host: String?
        /// The tab it opened, showed, read or closed (for its badge).
        var tabID: UUID?
    }

    /// Runs `command`.
    static func run(_ command: AgentCommand, in tabManager: TabManager) async -> Done {
        switch command {
        case .listTabs:
            return Done(result: .success(json(spaces(in: tabManager))), host: nil)
        case let .open(address):
            return open(address, in: tabManager)
        case let .activate(id):
            guard let tab = tab(id, in: tabManager) else { return Done(result: .failure(.noTab), host: nil) }
            tabManager.activateTab(id: tab.id)
            return Done(result: .success(json(agentTab(tab, in: tabManager))), host: tab.url.host(), tabID: tab.id)
        case let .close(id):
            guard let tab = tab(id, in: tabManager) else { return Done(result: .failure(.noTab), host: nil) }
            let closed = agentTab(tab, in: tabManager)
            let host = tab.url.host()
            tabManager.closeTab(tab: tab)
            // A pinned or favorite tab stays in the sidebar, with its badge.
            return Done(result: .success(json(closed)), host: host, tabID: tab.id)
        case let .read(id):
            return await onWebPage(id, in: tabManager) { tab in
                await onLoadedPage(tab) { await read(tab, $0, until: $1) }
            }
        case let .capture(id):
            return await onWebPage(id, in: tabManager) { tab in
                await onLoadedPage(tab) { _, deadline in await capture(tab, until: deadline) }
            }
        case let .click(id, selector):
            return await onWebPage(id, in: tabManager) { tab in
                await onLoadedPage(tab) { await AgentPageActions.click(selector, on: $0, until: $1) }
                    .map { action($0, in: tab) }
            }
        case let .fill(id, selector, value):
            return await onWebPage(id, in: tabManager) { tab in
                await onLoadedPage(tab) { await AgentPageActions.fill(selector, with: value, on: $0, until: $1) }
                    .map { action($0, in: tab) }
            }
        case let .runScript(id, code):
            return await onWebPage(id, in: tabManager) { tab in
                await onPage(tab) { await AgentPageActions.run(code, on: $0) }.flatMap { scriptResult($0, in: tab) }
            }
        }
    }

    static func spaces(in tabManager: TabManager) -> [AgentSpace] {
        tabManager.fetchContainers().map { container in
            AgentSpace(
                id: container.id.uuidString,
                name: container.name,
                active: container.id == tabManager.activeContainer?.id,
                tabs: container.tabs.filter(isListed).sorted(by: shownFirst)
                    .map { agentTab($0, in: tabManager) }
            )
        }
    }

    /// A tab agents see: not private (none in a normal window), not closing.
    private static func isListed(_ tab: Tab) -> Bool {
        !tab.isPrivate && !tab.isClosing
    }

    /// Favorites, then pinned tabs, then the others, each in the sidebar's order.
    private static func shownFirst(_ lhs: Tab, _ rhs: Tab) -> Bool {
        let rank: [TabType: Int] = [.fav: 0, .pinned: 1, .normal: 2]
        if lhs.type != rhs.type { return rank[lhs.type, default: 2] < rank[rhs.type, default: 2] }
        return lhs.order > rhs.order
    }

    private static func agentTab(_ tab: Tab, in tabManager: TabManager) -> AgentTab {
        let kind = switch tab.type {
        case .fav: "favorite"
        case .pinned: "pinned"
        case .normal: "normal"
        }
        return AgentTab(
            id: tab.id.uuidString,
            title: tab.title,
            address: tab.url.absoluteString,
            kind: kind,
            active: tab.id == tabManager.activeTab?.id
        )
    }

    /// A new tab of the active space, for an http(s) address only.
    private static func open(_ address: String, in tabManager: TabManager) -> Done {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil
        else { return Done(result: .failure(.badAddress), host: nil) }
        // Never private: agents only get normal windows.
        let isPrivate = tabManager.isPrivateWindow
        guard let tab = tabManager.openTab(url: url, historyManager: tabManager.historyManager, isPrivate: isPrivate)
        else { return Done(result: .failure(.noWindow), host: url.host()) }
        return Done(result: .success(json(agentTab(tab, in: tabManager))), host: url.host(), tabID: tab.id)
    }

    /// Reads or captures the web page of `id` (the active tab without one).
    private static func onWebPage(
        _ id: String?,
        in tabManager: TabManager,
        _ action: @MainActor (Tab) async -> Result<String, AgentError>
    ) async -> Done {
        guard let tab = target(id, in: tabManager) else {
            return Done(result: .failure(id == nil ? .noActiveTab : .noTab), host: nil)
        }
        guard isWebPage(tab) else { return Done(result: .failure(.notWebPage), host: nil) }
        // Before the action: a click may lead elsewhere.
        let host = tab.url.host()
        return await Done(result: action(tab), host: host, tabID: tab.id)
    }

    /// Read or captured: a web page only, never an extension's page (a
    /// password manager's vault), a file or Ombre's own pages.
    private static func isWebPage(_ tab: Tab) -> Bool {
        ["http", "https"].contains(tab.url.scheme?.lowercased() ?? "")
    }

    /// The tab of `id`, or the active one without an id.
    private static func target(_ id: String?, in tabManager: TabManager) -> Tab? {
        guard let id else { return tabManager.activeTab.flatMap { isListed($0) ? $0 : nil } }
        return tab(id, in: tabManager)
    }

    /// The tab of `id` in the window's spaces (any case), never a private one.
    private static func tab(_ id: String, in tabManager: TabManager) -> Tab? {
        guard let uuid = UUID(uuidString: id.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return tabManager.fetchContainers().lazy.flatMap(\.tabs).first { $0.id == uuid && isListed($0) }
    }

    /// `action` on the tab's page once it has loaded (`AgentPageActions.loadWait`
    /// at most: then as it is), before the command's deadline. A tab just
    /// opened is waited for too.
    private static func onLoadedPage<Value>(
        _ tab: Tab,
        _ action: @MainActor (BrowserPage, ContinuousClock.Instant) async -> Result<Value, AgentError>
    ) async -> Result<Value, AgentError> {
        let deadline = AgentPageActions.deadline()
        guard let page = tab.browserPage else { return .failure(.notLoaded) }
        _ = await page.waitUntilLoaded(within: AgentPageActions.loadWait)
        // Unloaded or replaced meanwhile.
        guard tab.browserPage === page, tab.isWebViewReady else { return .failure(.notLoaded) }
        let result = await action(page, deadline)
        // No element on an error page: the reason is the failed load.
        if case let .failure(error) = result, let loadError = loadError(of: tab) {
            return .failure(error.afterFailedLoad(loadError))
        }
        return result
    }

    /// `action` on the tab's loaded page.
    private static func onPage<Value>(
        _ tab: Tab,
        _ action: @MainActor (BrowserPage) async -> Result<Value, AgentError>
    ) async -> Result<Value, AgentError> {
        guard let page = tab.browserPage, tab.isWebViewReady else { return .failure(.notLoaded) }
        return await action(page)
    }

    static func action(_ element: String, in tab: Tab) -> String {
        json(AgentAction(
            id: tab.id.uuidString,
            title: tab.title,
            address: tab.url.absoluteString,
            element: element,
            loadError: loadError(of: tab)
        ))
    }

    /// Why the tab's last load failed, so that an empty page isn't taken for
    /// one: the system's words (in Ombre's language) and the error's code.
    static func loadError(of tab: Tab) -> String? {
        guard let error = tab.browserPage?.lastLoadFailure else { return nil }
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (\(PageLog.describe(error)))"
    }

    /// The tab and the script's result (JSON text, any value), as JSON.
    static func scriptResult(_ result: String, in tab: Tab) -> Result<String, AgentError> {
        let value = AgentPageActions.value(of: result) ?? NSNull()
        let reply: [String: Any] = [
            "id": tab.id.uuidString,
            "title": tab.title,
            "address": tab.url.absoluteString,
            "result": value
        ]
        guard let text = AgentPageActions.json(reply) else { return .failure(.unsupportedResult) }
        return .success(text)
    }

    /// The page's visible text, cut in the page (a huge page isn't copied whole).
    private static let textScript = """
    (() => { const t = document.body ? document.body.innerText : ''; \
    return [t.slice(0, \(maxTextLength)), t.length > \(maxTextLength)]; })()
    """ // not shown

    private static func read(
        _ tab: Tab,
        _ page: BrowserPage,
        until deadline: ContinuousClock.Instant
    ) async -> Result<String, AgentError> {
        let reply: Result<(String, Bool), AgentError> = await AgentPageActions.answer(until: deadline) { reply in
            page.evaluateJavaScript(textScript) { value, error in
                MainActor.assumeIsolated {
                    if let error {
                        reply(.failure(.failed(PageLog.describe(error))))
                    } else if let parts = value as? [Any], let text = parts.first as? String {
                        reply(.success((text, parts.last as? Bool ?? false)))
                    } else {
                        reply(.success(("", false)))
                    }
                }
            }
        }
        return reply.map { text, truncated in
            json(AgentPage(
                id: tab.id.uuidString,
                title: tab.title,
                address: tab.url.absoluteString,
                text: text,
                truncated: truncated,
                loadError: loadError(of: tab)
            ))
        }
    }

    /// The widest image sent, in pixels (a Retina window's page is twice its
    /// points): enough to read a page, a few megabytes at most.
    static let maxImageWidth = 2560

    private static func capture(
        _ tab: Tab,
        until deadline: ContinuousClock.Instant
    ) async -> Result<String, AgentError> {
        let configuration = BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: false)
        let snapshot: Result<NSImage?, AgentError> = await AgentPageActions.answer(until: deadline) { reply in
            tab.takeSnapshot(configuration: configuration) { image, _ in reply(.success(image)) }
        }
        let image: NSImage
        switch snapshot {
        case let .failure(error): return .failure(error)
        case let .success(taken):
            guard let taken else { return .failure(.noImage) }
            image = taken
        }
        guard let png = AgentImage.png(of: image, maxWidth: maxImageWidth) else { return .failure(.noImage) }
        return .success(json(AgentCapture(
            id: tab.id.uuidString,
            title: tab.title,
            address: tab.url.absoluteString,
            width: png.width,
            height: png.height,
            png: png.data.base64EncodedString(),
            loadError: loadError(of: tab)
        )))
    }

    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
