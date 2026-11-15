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

    /// Its name in the logs and the sdef.
    var name: String {
        switch self {
        case .listTabs: "list tabs" // not shown
        case .open: "open address" // not shown
        case .activate: "activate tab" // not shown
        case .close: "close tab" // not shown
        case .read: "read tab" // not shown
        case .capture: "capture tab" // not shown
        }
    }
}

/// Why a command was not done; the text goes back to the agent (English, as
/// Apple Events errors are), never shown in Ombre.
struct AgentError: Error, Equatable {
    let message: String

    static let off = AgentError(message: "Agent control is off: turn it on in Settings › General.") // not shown
    static let denied = AgentError(message: "The user denied this app control of Ombre for this session.") // not shown
    static let noWindow =
        AgentError(message: "No Ombre window is open (private windows are never controlled).") // not shown
    static let badAddress = AgentError(message: "Only http and https addresses can be opened.") // not shown
    static let noTab = AgentError(message: "No tab with this id: ask list tabs again.") // not shown
    static let unanswered = AgentError(message: "The user didn't answer in time: try again.") // not shown
    static let noActiveTab = AgentError(message: "No tab is active: give a tab id.") // not shown
    static let notLoaded = AgentError(message: "This tab's page isn't loaded: activate it first.") // not shown
    static let notWebPage = AgentError(message: "Only web pages (http, https) can be read or captured.") // not shown
    static let noImage = AgentError(message: "The page couldn't be captured: show its tab first.") // not shown
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

/// A page's image: a PNG, in base64.
struct AgentCapture: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    let width: Int
    let height: Int
    let png: String
}

struct AgentPage: Codable, Equatable {
    let id: String
    let title: String
    let address: String
    let text: String
    let truncated: Bool
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
            return await onWebPage(id, in: tabManager, read)
        case let .capture(id):
            return await onWebPage(id, in: tabManager, capture)
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
        return await Done(result: action(tab), host: tab.url.host(), tabID: tab.id)
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

    /// The page's visible text, cut in the page (a huge page isn't copied whole).
    private static let textScript = """
    (() => { const t = document.body ? document.body.innerText : ''; \
    return [t.slice(0, \(maxTextLength)), t.length > \(maxTextLength)]; })()
    """ // not shown

    private static func read(_ tab: Tab) async -> Result<String, AgentError> {
        guard let page = tab.browserPage, tab.isWebViewReady else { return .failure(.notLoaded) }
        let reply: Result<(String, Bool), AgentError> = await withCheckedContinuation { continuation in
            page.evaluateJavaScript(textScript) { value, error in
                if let error {
                    continuation.resume(returning: .failure(.failed(PageLog.describe(error))))
                } else if let parts = value as? [Any], let text = parts.first as? String {
                    continuation.resume(returning: .success((text, parts.last as? Bool ?? false)))
                } else {
                    continuation.resume(returning: .success(("", false)))
                }
            }
        }
        return reply.map { text, truncated in
            json(AgentPage(
                id: tab.id.uuidString,
                title: tab.title,
                address: tab.url.absoluteString,
                text: text,
                truncated: truncated
            ))
        }
    }

    /// The widest image sent, in pixels (a Retina window's page is twice its
    /// points): enough to read a page, a few megabytes at most.
    static let maxImageWidth = 2560

    private static func capture(_ tab: Tab) async -> Result<String, AgentError> {
        guard tab.browserPage != nil, tab.isWebViewReady else { return .failure(.notLoaded) }
        let configuration = BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: false)
        let image: NSImage? = await withCheckedContinuation { continuation in
            tab.takeSnapshot(configuration: configuration) { image, _ in continuation.resume(returning: image) }
        }
        guard let image, let png = AgentImage.png(of: image, maxWidth: maxImageWidth) else {
            return .failure(.noImage)
        }
        return .success(json(AgentCapture(
            id: tab.id.uuidString,
            title: tab.title,
            address: tab.url.absoluteString,
            width: png.width,
            height: png.height,
            png: png.data.base64EncodedString()
        )))
    }

    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
