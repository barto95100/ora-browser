import Foundation

/// What an agent may ask (see `Ombre.sdef`).
enum AgentCommand: Equatable, Sendable {
    case listTabs
    case open(String)
    case activate(String)
    case close(String)
    /// The active tab without an id.
    case read(String?)

    /// Its name in the logs and the sdef.
    var name: String {
        switch self {
        case .listTabs: "list tabs" // not shown
        case .open: "open address" // not shown
        case .activate: "activate tab" // not shown
        case .close: "close tab" // not shown
        case .read: "read tab" // not shown
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

    /// Runs `command`; returns its JSON reply, and the site it touched (for
    /// the log).
    static func run(_ command: AgentCommand, in tabManager: TabManager) async
        -> (result: Result<String, AgentError>, host: String?)
    {
        switch command {
        case .listTabs:
            return (.success(json(spaces(in: tabManager))), nil)
        case let .open(address):
            guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil
            else { return (.failure(.badAddress), nil) }
            // Never private: agents only get normal windows.
            let isPrivate = tabManager.isPrivateWindow
            guard let tab = tabManager.openTab(
                url: url,
                historyManager: tabManager.historyManager,
                isPrivate: isPrivate
            )
            else { return (.failure(.noWindow), url.host()) }
            return (.success(json(agentTab(tab, in: tabManager))), url.host())
        case let .activate(id):
            guard let tab = tab(id, in: tabManager) else { return (.failure(.noTab), nil) }
            tabManager.activateTab(id: tab.id)
            return (.success(json(agentTab(tab, in: tabManager))), tab.url.host())
        case let .close(id):
            guard let tab = tab(id, in: tabManager) else { return (.failure(.noTab), nil) }
            let closed = agentTab(tab, in: tabManager)
            tabManager.closeTab(tab: tab)
            return (.success(json(closed)), tab.url.host())
        case let .read(id):
            let found = id.map { tab($0, in: tabManager) } ?? tabManager.activeTab.flatMap { isListed($0) ? $0 : nil }
            guard let tab = found else { return (.failure(id == nil ? .noActiveTab : .noTab), nil) }
            return await (read(tab), tab.url.host())
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

    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
