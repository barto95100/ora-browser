import AppKit
@preconcurrency import WebKit

/// Which websites an extension may read and change, like Safari: allowed,
/// refused, or asked the first time (its button then shows a dot).
@available(macOS 15.4, *)
extension WebExtensionsManager {
    /// Grants what the record allows and refuses what it refuses, in place:
    /// the extension keeps running (Bitwarden stays unlocked).
    func applyAccess(_ record: ExtensionRecord, to context: WKWebExtensionContext) {
        context.hasAccessToPrivateData = record.allowsPrivateBrowsing
        for name in record.grantedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: name))
        }
        for name in record.deniedPermissions {
            context.setPermissionStatus(.deniedExplicitly, for: WKWebExtension.Permission(rawValue: name))
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
        // Then what was decided from private windows, until they are all closed.
        for entry in privateSiteDecisions.entries(for: record.id) {
            let string = entry.host == PrivateSiteDecisions.allSites
                ? "<all_urls>" : ExtensionSiteAccess.pattern(forHost: entry.host)
            guard let pattern = try? WKWebExtension.MatchPattern(string: string) else { continue }
            let status: WKWebExtensionContext.PermissionStatus = entry.decision == .allow
                ? .grantedExplicitly : .deniedExplicitly
            context.setPermissionStatus(status, for: pattern, expirationDate: entry.expiresAt)
        }
    }

    /// The website of the tab, if the extension wants it and nothing was
    /// decided yet: its button shows a dot, and a click asks.
    func hostAskingAccess(_ context: WKWebExtensionContext, tab: Tab?) -> String? {
        guard let tab, let record = record(for: context) else { return nil }
        let url = tab.browserPage?.extensionWebView.url ?? tab.url
        guard let host = ExtensionSiteAccess.host(of: url),
              siteDecision(for: host, in: record, isPrivate: tab.isPrivate) == .ask
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

    /// A website's decision from a tab: saved, or from a private tab kept in
    /// memory only (and given to the extension at once).
    func decideSite(_ host: String, _ decision: SiteDecision, forOneDay: Bool = false, id: String, isPrivate: Bool) {
        guard isPrivate else { return setSite(host, decision, forOneDay: forOneDay, id: id) }
        let expiresAt = forOneDay ? Date().addingTimeInterval(24 * 60 * 60) : nil
        privateSiteDecisions.set(decision, for: host, until: expiresAt, extensionID: id)
        applyPrivateDecisions(id: id)
    }

    /// Gives the extension what was just decided in private, and shows it
    /// on its button.
    private func applyPrivateDecisions(id: String) {
        if let item = installed.first(where: { $0.id == id }), let context = item.context {
            applyAccess(item.record, to: context)
        }
        actionDidChange()
    }

    func setOtherSites(_ decision: SiteDecision, id: String) {
        updateRecord(id: id) { $0.otherSites = decision }
    }

    func setPinned(_ pinned: Bool, id: String) {
        updateRecord(id: id) { $0.isPinned = pinned }
    }

    /// Forgets a refused permission (SEC-14): the running extension may
    /// ask for it again, without being removed and installed again.
    func forgetRefusedPermission(_ name: String, id: String) {
        updateRecord(id: id) { $0.forgetRefusal(of: name) }
        installed.first { $0.id == id }?.context?
            .setPermissionStatus(.unknown, for: WKWebExtension.Permission(rawValue: name))
    }

    func setAllowsPrivateBrowsing(_ allowed: Bool, id: String) {
        updateRecord(id: id) { $0.allowsPrivateBrowsing = allowed }
    }

    /// Asks before removing an extension (from its button's menu).
    func confirmRemove(id: String) {
        guard let record = installed.first(where: { $0.id == id })?.record else { return }
        ask(
            title: String(localized: "Remove “\(record.name)”?"),
            message: String(localized: "Its data in Ombre is deleted. The app that brings it stays installed."),
            buttons: [String(localized: "Remove"), String(localized: "Cancel")]
        ) { choice in
            if choice == 0 { self.remove(id: id) }
        }
    }

    /// The extension's options page, in a new tab of the front window.
    func openOptions(_ context: WKWebExtensionContext) {
        guard let url = context.optionsPageURL, let tabManager = focusedNormalWindow?.tabManager else { return }
        _ = tabManager.openTab(
            url: url,
            historyManager: tabManager.historyManager,
            downloadManager: tabManager.downloadManager,
            isPrivate: false
        )
    }

    /// The saved decision, or the one taken in a private window for a
    /// private tab.
    func siteDecision(for host: String, in record: ExtensionRecord, isPrivate: Bool) -> SiteDecision {
        if isPrivate, let decision = privateSiteDecisions.decision(for: host, extensionID: record.id) {
            return decision
        }
        return ExtensionSiteAccess.decision(for: host, in: record)
    }

    /// The last private window closed: what was decided in private goes,
    /// and each extension gets back what its record allows.
    func forgetPrivateSiteDecisions() {
        let ids = privateSiteDecisions.extensionIDs
        privateSiteDecisions.removeAll()
        for item in installed where ids.contains(item.id) {
            if let context = item.context {
                applyAccess(item.record, to: context)
            }
        }
        actionDidChange()
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
        let granted = permissions.filter { record.grantedPermissions.contains($0.rawValue) }
        // Only what wasn't answered yet: a refusal is not asked again.
        let names = record.undecidedPermissions(permissions.map(\.rawValue).sorted())
        guard !names.isEmpty else { return completion(granted) }
        let lines = names.map { "• " + ExtensionPermissionText.describe($0) }.joined(separator: "\n")
        ask(
            title: String(localized: "“\(record.name)” would like to:"),
            message: lines,
            buttons: [String(localized: "Allow"), String(localized: "Don't Allow")]
        ) { choice in
            let allowed = choice == 0
            self.updateRecord(id: record.id) { record in
                if allowed { record.grant(names) } else { record.deny(names) }
            }
            // Never one refused before: it wasn't asked.
            completion(allowed ? granted.union(permissions.filter { names.contains($0.rawValue) }) : granted)
        }
    }

    /// An extension asks for websites while running: all websites, or some.
    /// From a private window (`isPrivate`), the answer is kept in memory
    /// only: a site visited in private leaves no trace in `extensions.json`.
    func askSites(
        hosts: [String],
        allSites: Bool,
        isPrivate: Bool,
        for context: WKWebExtensionContext,
        completion: @escaping (_ allowed: Bool, _ expiresAt: Date?) -> Void
    ) {
        guard let record = record(for: context) else { return completion(false, nil) }
        // Refused for other websites: not asked again (like Safari).
        let undecided = hosts.filter { siteDecision(for: $0, in: record, isPrivate: isPrivate) == .ask }
        if !allSites, undecided.isEmpty {
            let allowed = hosts.allSatisfy { siteDecision(for: $0, in: record, isPrivate: isPrivate) == .allow }
            return completion(allowed, nil)
        }
        if allSites, record.otherSites == .deny { return completion(false, nil) }

        if allSites {
            ask(
                title: String(localized: "Allow “\(record.name)” on all websites?"),
                message: String(localized: "It will be able to read and change every page you visit."),
                buttons: [String(localized: "Allow on All Websites"), String(localized: "Don't Allow")]
            ) { choice in
                if choice == 0 {
                    if isPrivate {
                        self.privateSiteDecisions.set(
                            .allow,
                            for: PrivateSiteDecisions.allSites,
                            extensionID: record.id
                        )
                        self.applyPrivateDecisions(id: record.id)
                    } else {
                        self.setOtherSites(.allow, id: record.id)
                    }
                }
                completion(choice == 0, nil)
            }
            return
        }

        ask(
            title: String(localized: "Allow “\(record.name)” on \(undecided.formatted(.list(type: .and)))?"),
            message: String(localized: "It will be able to read and change these pages."),
            buttons: [
                String(localized: "Allow for One Day"),
                String(localized: "Always Allow"),
                String(localized: "Don't Allow")
            ]
        ) { choice in
            let decision: SiteDecision = choice == 2 ? .deny : .allow
            for host in undecided {
                self.decideSite(host, decision, forOneDay: choice == 0, id: record.id, isPrivate: isPrivate)
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
