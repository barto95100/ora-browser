import Foundation
@preconcurrency import WebKit

/// The extensions' user scripts (`chrome.userScripts`) in the tabs' pages:
/// those of the extensions running now that may use the API, on the
/// websites they may read.
@available(macOS 15.4, *)
extension WebExtensionsManager {
    func setUpUserScripts() {
        let injector = ExtensionUserScriptInjector.shared
        complements.loadedContext = { [weak self] id in
            self?.installed.first { $0.id == id }?.context
        }
        complements.userScriptsAllowed = { [weak self] id in
            self?.installed.first { $0.id == id }?.record.allowsUserScripts == true
        }
        complements.userScriptsDidChange = { [weak self] in self?.userScriptsChanged() }
        injector.entries = { [weak self] in self?.userScriptEntries() ?? [] }
        injector.handler = { [weak self] world in self?.complements.userScriptMessages.handler(for: world) }
    }

    /// Scripts, an extension, or the websites it may read changed.
    func userScriptsChanged() {
        ExtensionUserScriptInjector.shared.refresh()
    }

    /// "Allow User Scripts": its scripts run (or stop) from the next load,
    /// and the extension starts again, to see the API (or no longer).
    func setAllowsUserScripts(_ allowed: Bool, id: String) {
        guard let record = installed.first(where: { $0.id == id })?.record,
              record.allowsUserScripts != allowed
        else { return }
        updateRecord(id: id) { $0.allowsUserScripts = allowed }
        userScriptsChanged()
        Task {
            await writeUserScriptsSetting(id: id, evenIfOff: true)
            reload(id: id)
        }
    }

    /// Writes its "Allow User Scripts" in its copy (off: only if asked, a
    /// copy is written without it), as the record says when it is its turn:
    /// one write after another, the last one right.
    func writeUserScriptsSetting(id: String, evenIfOff: Bool) async {
        let previous = userScriptsWrites
        let write = Task { @MainActor [weak self] in
            await previous?.value
            guard let record = self?.installed.first(where: { $0.id == id })?.record,
                  record.bundleIdentifier == nil, record.allowsUserScripts || evenIfOff
            else { return }
            let (allowed, path) = (record.allowsUserScripts, record.path)
            _ = await Task.detached { ExtensionComplementPackage.setUserScriptsAllowed(allowed, at: path) }.value
        }
        userScriptsWrites = write
        await write.value
    }

    private func userScriptEntries() -> [ExtensionUserScriptInjector.Entry] {
        installed.compactMap { item in
            guard let context = item.context, complements.runsUserScripts(context) else { return nil }
            let registered = complements.userScripts.registered(for: item.id)
            guard !registered.scripts.isEmpty else { return nil }
            return ExtensionUserScriptInjector.Entry(
                extensionID: item.id,
                access: Self.userScriptAccess(of: context),
                allowsPrivate: context.hasAccessToPrivateData,
                registered: registered
            )
        }
    }

    static func userScriptAccess(of context: WKWebExtensionContext) -> ExtensionUserScriptMatcher.Access {
        ExtensionUserScriptMatcher.Access(
            allURLs: context.hasAccessToAllURLs,
            granted: context.grantedPermissionMatchPatterns
                .map { (pattern: $0.key.string, expiresAt: $0.value == .distantFuture ? nil : $0.value) }
                .sorted { $0.pattern < $1.pattern },
            denied: context.deniedPermissionMatchPatterns.keys.map(\.string).sorted()
        )
    }
}
