import AppKit
import os.log

/// Agents driving Ombre (Apple Events, see `Ombre.sdef`): allowed in the
/// settings, then each app asks the user once per session ("Terminal wants
/// to control Ombre"). Only the front normal window: never a private window,
/// Little Ombre, passwords or the keychain. Each command is logged in the
/// "Agent" category (command, app, site, result; never a page's text). While
/// a session is allowed, the sidebar shows which app drives Ombre (with Stop
/// Agent Control), and a badge on each tab an agent opened, showed, read or
/// closed: until Stop, the setting turned off, or an hour without a command.
@MainActor
final class AgentControl: ObservableObject {
    static let shared = AgentControl()

    /// The app whose command came last, while agents drive Ombre.
    @Published private(set) var drivingApp: String?
    /// The tabs agents touched meanwhile (badges in the sidebar).
    @Published private(set) var touchedTabIDs: Set<UUID> = []

    /// The question is given up after that, before the agent's Apple Event
    /// is (osascript waits 120 s): a late answer would run a command the
    /// agent no longer waits for.
    static let questionTimeout: Duration = .seconds(100)

    private var sessions = AgentSessions()
    /// Commands waiting for the user's answer, by app (nil: no answer).
    private var waiting: [String: [CheckedContinuation<Bool?, Never>]] = [:]
    /// Changes with Stop: an answer to a question asked before is not kept.
    private var generation = 0
    /// The questions shown, closed by Stop.
    private var questions: [(window: NSWindow, sheet: NSWindow)] = []
    /// Ends the indicator and the badges once every session is idle.
    private var endWhenIdle: DispatchWorkItem?
    private let logger = Logger(category: "Agent")

    /// Whether the settings allow agents (the tests set their own).
    var isAllowed: () -> Bool = { SettingsStore.shared.allowsAgentControl }
    /// How long without a command ends the indicator and the badges (the
    /// sessions then expire: see `AgentSessions`); the tests set their own.
    var idleLimit = AgentSessions.idleLimit
    /// Asks the user about a new session: true to allow, nil without an
    /// answer (the tests answer for them; none: the alert).
    var ask: (@MainActor (AgentSender) async -> Bool?)?
    /// The window agents work in: the front normal one.
    var tabManager: () -> TabManager? = { BrowserWindows.frontTabManager }

    /// Runs an agent's command, once the settings and the user allow it.
    func run(_ command: AgentCommand, from sender: AgentSender) async -> Result<String, AgentError> {
        guard isAllowed() else { return log(command, sender, nil, .failure(.off)) }
        // The question shows in that window.
        guard tabManager() != nil else { return log(command, sender, nil, .failure(.noWindow)) }
        switch await authorization(sender) {
        case true: break
        case false: return log(command, sender, nil, .failure(.denied))
        case nil: return log(command, sender, nil, .failure(.unanswered))
        }
        // Turned off while the user was asked.
        guard isAllowed() else { return log(command, sender, nil, .failure(.off)) }
        guard let tabManager = tabManager() else { return log(command, sender, nil, .failure(.noWindow)) }
        noteDriving(by: sender)
        let started = generation
        let done = await AgentCommands.run(command, in: tabManager)
        // Not after Stop meanwhile (a page read waits for its page).
        if case .success = done.result, let tabID = done.tabID, started == generation {
            touchedTabIDs.insert(tabID)
        }
        return log(command, sender, done.host, done.result)
    }

    /// Stop Agent Control (sidebar or address bar), or the setting turned off: every app
    /// asks again next time, and a question shown is closed unanswered.
    func stop() {
        generation += 1
        sessions.endAll()
        for question in questions {
            question.window.endSheet(question.sheet, returnCode: .abort)
        }
        endIndicators()
        logger.notice("agent control stopped")
    }

    private func endIndicators() {
        endWhenIdle?.cancel()
        drivingApp = nil
        touchedTabIDs = []
    }

    /// The user's answer for `sender`'s session: asked once for commands
    /// sent together; kept for the session unless Stop came meanwhile, or the
    /// app is unknown (asked each time: it could be any process).
    private func authorization(_ sender: AgentSender) async -> Bool? {
        switch sessions.decision(for: sender.key) {
        case .allowed: return true
        case .denied: return false
        case .ask: break
        }
        if waiting[sender.key] != nil {
            return await withCheckedContinuation { waiting[sender.key, default: []].append($0) }
        }
        waiting[sender.key] = []
        let asked = generation
        var answer = await (ask ?? askUser)(sender)
        if asked != generation { answer = nil }
        if let answer, sender.key != AgentSender.unknownKey {
            sessions.record(sender.key, isAllowed: answer)
        }
        let said = answer.map { $0 ? "allowed" : "denied" } ?? "no answer" // not shown
        logger.notice("\(sender.name, privacy: .public): session \(said, privacy: .public)")
        for continuation in waiting.removeValue(forKey: sender.key) ?? [] {
            continuation.resume(returning: answer)
        }
        return answer
    }

    /// Shows `sender` at work, until an hour passes without a command (the
    /// allowed sessions are then over; a denied app's answer stays until its
    /// own hour passes).
    private func noteDriving(by sender: AgentSender) {
        if drivingApp != sender.name { drivingApp = sender.name }
        endWhenIdle?.cancel()
        let end = DispatchWorkItem { [weak self] in self?.endIndicators() }
        endWhenIdle = end
        // The clock's time: the Mac's sleep counts, as for the sessions.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + idleLimit, execute: end)
    }

    @discardableResult
    private func log(
        _ command: AgentCommand,
        _ sender: AgentSender,
        _ host: String?,
        _ result: Result<String, AgentError>
    ) -> Result<String, AgentError> {
        let outcome = switch result {
        case .success: "ok"
        case let .failure(error): error.message
        }
        let line = "\(command.name) from \(sender.name) [\(host ?? "-")]: \(outcome)" // not shown
        logger.notice("\(line, privacy: .public)")
        return result
    }

    /// "Terminal wants to control Ombre": Allow for This Session / Deny, on
    /// the front normal window, brought forward. Never under the tests.
    private func askUser(_ sender: AgentSender) async -> Bool? {
        guard !TestHost.isActive, let window = BrowserWindows.front else { return nil }
        let alert = NSAlert()
        alert.messageText = String(localized: "\(sender.name) wants to control Ombre")
        alert.informativeText = String(
            localized: "It will be able to list, open, show, close and read your tabs until you quit Ombre or an hour passes without a command. Never private windows, Little Ombre or passwords."
        ) + "\n\n" + sender.key
        alert.addButton(withTitle: String(localized: "Allow for This Session"))
        alert.addButton(withTitle: String(localized: "Deny"))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let sheet = alert.window
        questions.append((window: window, sheet: sheet))
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: Self.questionTimeout)
            guard !Task.isCancelled else { return }
            window.endSheet(sheet, returnCode: .abort)
        }
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        timeout.cancel()
        questions.removeAll { $0.sheet === sheet }
        switch response {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }
}
