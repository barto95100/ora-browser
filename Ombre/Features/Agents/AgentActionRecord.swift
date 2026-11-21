import Foundation

/// One command of an agent's session, as the Agent Actions panel lists it:
/// when, which app, which command, the site (domain only), the tab's title
/// and how it ended. Like the "Agent" log: never a selector, a text filled
/// in, a script nor a page's content.
struct AgentActionRecord: Identifiable, Equatable, Sendable {
    let id = UUID()
    var date = Date()
    let app: String
    /// The command, as the panel shows it (`AgentCommand.title`).
    let command: String
    let host: String?
    /// The tab, to show it (nothing shown once it's gone).
    let tabID: UUID?
    let tabTitle: String?
    let succeeded: Bool
    /// Why it failed, as the agent was told (English, like Apple Events
    /// errors); the log's version when that holds what the page said.
    let failure: String?

    init(
        app: String,
        command: String,
        host: String?,
        tabID: UUID?,
        tabTitle: String?,
        result: Result<String, AgentError>
    ) {
        self.app = app
        self.command = command
        self.host = host
        self.tabID = tabID
        self.tabTitle = tabTitle
        switch result {
        case .success:
            succeeded = true
            failure = nil
        case let .failure(error):
            succeeded = false
            failure = error.logged ?? error.message
        }
    }
}

extension AgentCommand {
    /// Its name in the Agent Actions panel.
    var title: String {
        switch self {
        case .listTabs: String(localized: "agent.command.listTabs", defaultValue: "List Tabs")
        case .open: String(localized: "agent.command.open", defaultValue: "Open")
        case .activate: String(localized: "agent.command.show", defaultValue: "Show Tab")
        case .close: String(localized: "agent.command.close", defaultValue: "Close Tab")
        case .read: String(localized: "agent.command.read", defaultValue: "Read")
        case .capture: String(localized: "agent.command.capture", defaultValue: "Capture")
        case .click: String(localized: "agent.command.click", defaultValue: "Click")
        case .fill: String(localized: "agent.command.fill", defaultValue: "Fill In")
        case .runScript: String(localized: "agent.command.javascript", defaultValue: "JavaScript")
        case .goBack: String(localized: "agent.command.back", defaultValue: "Back")
        case .goForward: String(localized: "agent.command.forward", defaultValue: "Forward")
        case .reload: String(localized: "agent.command.reload", defaultValue: "Reload")
        case .wait: String(localized: "agent.command.wait", defaultValue: "Wait")
        }
    }
}
