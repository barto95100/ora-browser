import AppKit
@preconcurrency import WebKit

/// What WebKit asks Ombre for the extensions: windows, new tabs, popups,
/// permissions, messages to their app.
@available(macOS 15.4, *)
extension WebExtensionsManager: WKWebExtensionControllerDelegate {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        orderedAllWindows
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        focusedWindow
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        // Not in a private window for an extension not allowed there.
        let window = Self.window(
            for: configuration.window as? ExtensionWindow,
            focused: focusedWindow,
            focusedNormal: focusedNormalWindow,
            allowsPrivate: extensionContext.hasAccessToPrivateData
        )
        guard let tabManager = window?.tabManager, let url = configuration.url else {
            completionHandler(nil, nil)
            return
        }
        let tab = tabManager.openTab(
            url: url,
            historyManager: tabManager.historyManager,
            downloadManager: tabManager.downloadManager,
            focusAfterOpening: configuration.shouldBeActive,
            isPrivate: window?.isPrivateWindow ?? false
        )
        if let tab { tabOpened(tab) }
        completionHandler(tab.map { adapter(for: $0) }, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        completionHandler(openWindow(configuration, for: extensionContext), nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        openOptions(extensionContext)
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let popover = action.popupPopover else {
            completionHandler(nil)
            return
        }
        #if DEBUG
            // Stays open while another app is in front (Safari's web
            // inspector, to debug the popup); a click in the window closes it.
            popover.behavior = .semitransient
        #endif
        // Under the button clicked; asked by the extension itself (Bitwarden's
        // "Unlock your account"): see `present(_:for:)`.
        completionHandler(present(popover, for: context) ? nil : Failure.noAnchor)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        actionDidChange()
    }

    // MARK: - Permissions

    // Asked while running, beyond what was reviewed at install: the user
    // decides (see `WebExtensionsManager+SiteAccess.swift`).

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        askPermissions(permissions, for: extensionContext) { completionHandler($0, nil) }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let hosts = Array(Set(urls.compactMap { ExtensionSiteAccess.host(of: $0) })).sorted()
        guard !hosts.isEmpty else {
            completionHandler([], nil)
            return
        }
        askSites(
            hosts: hosts,
            allSites: false,
            isPrivate: isPrivate(tab),
            for: extensionContext
        ) { allowed, expiresAt in
            completionHandler(allowed ? urls : [], expiresAt)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let allSites = matchPatterns.contains { $0.matchesAllHosts || $0.matchesAllURLs }
        let hosts = Array(Set(matchPatterns.compactMap(\.host))).sorted()
        guard allSites || !hosts.isEmpty else {
            completionHandler([], nil)
            return
        }
        let isPrivate = isPrivate(tab)
        askSites(hosts: hosts, allSites: allSites, isPrivate: isPrivate, for: extensionContext) { allowed, expiresAt in
            // All websites allowed: kept with the websites it asked for at
            // install, which follow "Other Websites" (not from private).
            if allowed, allSites, !isPrivate {
                let patterns = matchPatterns.map(\.string)
                self.updateRecord(id: extensionContext.uniqueIdentifier) { record in
                    record.grantedMatchPatterns = Array(Set(record.grantedMatchPatterns).union(patterns)).sorted()
                }
            }
            completionHandler(allowed ? matchPatterns : [], expiresAt)
        }
    }

    /// Whether the extension asks from a private tab (or, without a tab,
    /// while a private window is in front).
    func isPrivate(_ tab: (any WKWebExtensionTab)?) -> Bool {
        if let tab = (tab as? ExtensionTab)?.tab { return tab.isPrivate }
        if let page = tab as? ExtensionPageTab { return page.isPrivatePage }
        return focusedWindow?.isPrivateWindow ?? false
    }

    /// Where a tab the extension opens goes: the window it named, or the
    /// front one; never a private window when it isn't allowed there.
    static func window(
        for requested: ExtensionWindow?,
        focused: ExtensionWindow?,
        focusedNormal: ExtensionWindow?,
        allowsPrivate: Bool
    ) -> ExtensionWindow? {
        if let requested {
            return requested.isPrivateWindow && !allowsPrivate ? nil : requested
        }
        return allowsPrivate ? focused : focusedNormal
    }

    // MARK: - Messages to the extension's app

    // Only Safari can reach the app part of a Safari extension: refused, and
    // logged once per command and per launch (never the content) to see what
    // is asked. A connection is closed rather than refused (`NativeAppPort`).
    // Exceptions: Bitwarden's "showPopover" (shows its popup), and its "sleep", which its app answers after 10 s to
    // keep the background alive; refused at once, it was asked again at once,
    // endlessly. Answered the same way, like its app does.

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let command = ((message as? [String: Any])?["command"] as? String) ?? "?"
        // Bitwarden's "Open popup" (shortcut, notification) on Safari: its
        // app shows the popup.
        if command == "showPopover" {
            showPopup(of: extensionContext)
            replyHandler(nil, nil)
            return
        }
        if command == "sleep" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                replyHandler(message, nil)
            }
            return
        }
        if loggedNativeCommands.insert("\(extensionContext.uniqueIdentifier):\(command)").inserted {
            let name = name(of: extensionContext)
            logger.notice("\(name, privacy: .public) native message: \(command, privacy: .public)")
        }
        replyHandler(nil, Failure.nativeMessagingUnsupported)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        if loggedNativeCommands.insert("\(extensionContext.uniqueIdentifier):connect").inserted {
            logger.notice("\(self.name(of: extensionContext), privacy: .public) native connection closed")
        }
        NativeAppPort.decline(port, completionHandler: completionHandler)
    }

    private func name(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? context.uniqueIdentifier
    }
}
