import AppKit
@preconcurrency import WebKit

/// Which websites an extension may read and change, like Safari: allowed,
/// refused, or asked the first time (its button then shows a dot).
@available(macOS 15.4, *)
extension WebExtensionsManager {
    /// Grants what the record allows and refuses what it refuses, in place:
    /// the extension keeps running (Bitwarden stays unlocked).
    func applyAccess(_ record: ExtensionRecord, to context: WKWebExtensionContext) {
        for name in record.grantedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: name))
        }

        let granted = ExtensionSiteAccess.grantedPatterns(for: record)
        let denied = ExtensionSiteAccess.deniedPatterns(for: record)
        let grantedStrings = Set(granted.map(\.pattern))
        let deniedStrings = Set(denied)

        // What no longer applies goes back to "not decided".
        for pattern in context.grantedPermissionMatchPatterns.keys where !grantedStrings.contains(pattern.string) {
            context.setPermissionStatus(.unknown, for: pattern)
        }
        for pattern in context.deniedPermissionMatchPatterns.keys where !deniedStrings.contains(pattern.string) {
            context.setPermissionStatus(.unknown, for: pattern)
        }

        for item in granted {
            guard let pattern = try? WKWebExtension.MatchPattern(string: item.pattern) else { continue }
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: item.expiresAt)
        }
        for string in denied {
            guard let pattern = try? WKWebExtension.MatchPattern(string: string) else { continue }
            context.setPermissionStatus(.deniedExplicitly, for: pattern)
        }
    }

    /// The website of the tab, if the extension wants it and nothing was
    /// decided yet: its button shows a dot, and a click asks.
    func hostAskingAccess(_ context: WKWebExtensionContext, tab: Tab?) -> String? {
        guard let tab, let record = record(for: context) else { return nil }
        let url = tab.browserPage?.extensionWebView.url ?? tab.url
        guard let host = ExtensionSiteAccess.host(of: url),
              ExtensionSiteAccess.decision(for: host, in: record) == .ask
        else { return nil }
        switch context.permissionStatus(for: url, in: adapter(for: tab)) {
        case .requestedImplicitly, .requestedExplicitly: return host
        default: return nil
        }
    }

    /// A website's decision: for one day, always, or refused; `.ask`
    /// forgets it.
    func setSite(_ host: String, _ decision: SiteDecision, forOneDay: Bool = false, id: String) {
        let expiresAt = forOneDay ? Date().addingTimeInterval(24 * 60 * 60) : nil
        updateRecord(id: id) { record in
            record.siteRules = ExtensionSiteAccess.setting(decision, for: host, until: expiresAt, in: record.siteRules)
        }
    }

    func setOtherSites(_ decision: SiteDecision, id: String) {
        updateRecord(id: id) { $0.otherSites = decision }
    }

    func setPinned(_ pinned: Bool, id: String) {
        updateRecord(id: id) { $0.isPinned = pinned }
    }

    /// Asks before removing an extension (from its button's menu).
    func confirmRemove(id: String) {
        guard let record = installed.first(where: { $0.id == id })?.record else { return }
        ask(
            title: "Remove “\(record.name)”?",
            message: "Its data in Ora is deleted. The app that brings it stays installed.",
            buttons: ["Remove", "Cancel"]
        ) { choice in
            if choice == 0 { self.remove(id: id) }
        }
    }

    /// The extension's options page, in a new tab of the front window.
    func openOptions(_ context: WKWebExtensionContext) {
        guard let url = context.optionsPageURL, let tabManager = focusedWindow?.tabManager else { return }
        _ = tabManager.openTab(
            url: url,
            historyManager: tabManager.historyManager,
            downloadManager: tabManager.downloadManager,
            isPrivate: false
        )
    }

    // MARK: - Asked while running

    /// An extension asks for more (an optional permission): allowed or not,
    /// remembered.
    func askPermissions(
        _ permissions: Set<WKWebExtension.Permission>,
        for context: WKWebExtensionContext,
        completion: @escaping (Set<WKWebExtension.Permission>) -> Void
    ) {
        guard let record = record(for: context) else { return completion([]) }
        let names = permissions.map(\.rawValue).sorted()
        let lines = names.map { "• " + ExtensionPermissionText.describe($0) }.joined(separator: "\n")
        ask(
            title: "“\(record.name)” would like to:",
            message: lines,
            buttons: ["Allow", "Don't Allow"]
        ) { choice in
            guard choice == 0 else { return completion([]) }
            self.updateRecord(id: record.id) { record in
                record.grantedPermissions = Array(Set(record.grantedPermissions).union(names)).sorted()
            }
            completion(permissions)
        }
    }

    /// An extension asks for websites while running: all websites, or some.
    func askSites(
        hosts: [String],
        allSites: Bool,
        for context: WKWebExtensionContext,
        completion: @escaping (_ allowed: Bool, _ expiresAt: Date?) -> Void
    ) {
        guard let record = record(for: context) else { return completion(false, nil) }
        // Refused for other websites: not asked again (like Safari).
        let undecided = hosts.filter { ExtensionSiteAccess.decision(for: $0, in: record) == .ask }
        if !allSites, undecided.isEmpty {
            let allowed = hosts.allSatisfy { ExtensionSiteAccess.decision(for: $0, in: record) == .allow }
            return completion(allowed, nil)
        }
        if allSites, record.otherSites == .deny { return completion(false, nil) }

        if allSites {
            ask(
                title: "Allow “\(record.name)” on all websites?",
                message: "It will be able to read and change every page you visit.",
                buttons: ["Allow on All Websites", "Don't Allow"]
            ) { choice in
                if choice == 0 { self.setOtherSites(.allow, id: record.id) }
                completion(choice == 0, nil)
            }
            return
        }

        ask(
            title: "Allow “\(record.name)” on \(undecided.joined(separator: ", "))?",
            message: "It will be able to read and change these pages.",
            buttons: ["Allow for One Day", "Always Allow", "Don't Allow"]
        ) { choice in
            let decision: SiteDecision = choice == 2 ? .deny : .allow
            for host in undecided {
                self.setSite(host, decision, forOneDay: choice == 0, id: record.id)
            }
            let expiresAt = choice == 0 ? Date().addingTimeInterval(24 * 60 * 60) : nil
            completion(decision == .allow, expiresAt)
        }
    }

    /// A question in the front window (or alone if there is none).
    func ask(title: String, message: String, buttons: [String], answer: @escaping (Int) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        let index: (NSApplication.ModalResponse) -> Int = { response in
            response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        }
        if let window = focusedWindow?.window {
            alert.beginSheetModal(for: window) { answer(index($0)) }
        } else {
            answer(index(alert.runModal()))
        }
    }
}
