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
        complements.userScriptsDidChange = { [weak self] in self?.userScriptsChanged() }
        injector.entries = { [weak self] in self?.userScriptEntries() ?? [] }
        injector.handler = { [weak self] world in self?.complements.userScriptMessages.handler(for: world) }
    }

    /// Scripts, an extension, or the websites it may read changed.
    func userScriptsChanged() {
        ExtensionUserScriptInjector.shared.refresh()
    }

    private func userScriptEntries() -> [ExtensionUserScriptInjector.Entry] {
        installed.compactMap { item in
            guard let context = item.context, complements.allows("userScripts", for: context) else { return nil }
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
