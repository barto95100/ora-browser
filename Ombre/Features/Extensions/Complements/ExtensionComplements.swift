import Foundation
import os.log
@preconcurrency import WebKit

private let logger = Logger(category: "ExtensionComplements")

/// An error an extension sees, as Chrome's (`ExtensionComplements`).
enum ExtensionComplementFailure: LocalizedError, Equatable {
    /// Its manifest doesn't ask for the API.
    case notAllowed(String)
    case unknownCall(String)
    case invalid(String)
    /// "Allow User Scripts" is off (Settings › Extensions).
    case userScriptsOff

    var errorDescription: String? {
        switch self {
        case let .notAllowed(api):
            "'\(api)' requires the \"\(api)\" permission in the manifest." // not shown
        case let .unknownCall(call):
            "'\(call)' is not supported." // not shown
        case let .invalid(reason):
            reason
        case .userScriptsOff:
            "The 'userScripts' API is only available for users " // not shown
                + "when the 'Allow User Scripts' toggle is enabled." // not shown
        }
    }
}

/// Ombre's side of the APIs it adds to extensions (`ExtensionComplementScript`).
///
/// Every message is checked here, whatever the script did: the extension is
/// the one WebKit says sent it (the context of the channel, never something
/// the message says), and it gets an API only if its manifest asks for it,
/// as in Chrome. The channel reaches these APIs only: nothing of the tabs,
/// files or settings of Ombre.
@available(macOS 15.4, *)
@MainActor
final class ExtensionComplements {
    static let applicationIdentifier = ExtensionComplementScript.applicationIdentifier

    typealias Failure = ExtensionComplementFailure

    let privacy: ExtensionPrivacy
    let offscreen: OffscreenDocuments
    let userScripts: ExtensionUserScripts
    let idle: ExtensionIdle
    let notifications: ExtensionNotifications
    let events = ExtensionEvents()
    /// The extension running now, by id (the manager's).
    var loadedContext: (String) -> WKWebExtensionContext? = { _ in nil }
    private(set) lazy var userScriptMessages = ExtensionUserScriptMessages(checks: .init(
        context: { [weak self] in self?.loadedContext($0) },
        allowsUserScripts: { [weak self] in self?.runsUserScripts($0) == true },
        registered: { [weak self] in self?.userScripts.registered(for: $0) ?? .init() }
    ))
    private let grants: ExtensionComplementGrants
    /// Whether the user allowed its user scripts, by id ("Allow User
    /// Scripts", Settings › Extensions): off, as in Chrome.
    var userScriptsAllowed: (String) -> Bool = { _ in false }
    /// The extensions' user scripts changed, or what they may use: the
    /// pages get them again (`ExtensionUserScriptInjector`).
    var userScriptsDidChange: () -> Void = {}
    /// Asks the user for optional permissions (Ombre's dialog); answers
    /// whether they allowed them. None: refused.
    var askUser: (_ names: [String], _ context: WKWebExtensionContext, _ answer: @escaping (Bool) -> Void) -> Void = {
        $2(false)
    }

    init(
        privacy: ExtensionPrivacy = .shared,
        offscreen: OffscreenDocuments = OffscreenDocuments(),
        userScripts: ExtensionUserScripts = ExtensionUserScripts(),
        idle: ExtensionIdle = ExtensionIdle(),
        notifications: ExtensionNotifications = ExtensionNotifications(),
        grants: ExtensionComplementGrants = ExtensionComplementGrants()
    ) {
        self.privacy = privacy
        self.offscreen = offscreen
        self.userScripts = userScripts
        self.idle = idle
        self.notifications = notifications
        self.grants = grants
        userScripts.didChange = { [weak self] _ in self?.userScriptsDidChange() }
        idle.stateChanged = { [weak self] id, state in self?.events.dispatch("idle.onStateChanged", [state], to: id) }
        notifications.event = { [weak self] id, name, args in self?.events.dispatch(name, args, to: id) }
        // A sleeping worker starts again for its events.
        events.wake = { [weak self] id in
            guard let context = self?.loadedContext(id) else { return }
            Task { try? await context.loadBackgroundContent() }
        }
    }

    /// The permissions its manifest asks for (`permissions`) and those it may
    /// ask later (`optional_permissions`), as written by its developer.
    static func declaredPermissions(of webExtension: WKWebExtension) -> (required: Set<String>, optional: Set<String>) {
        let manifest = webExtension.manifest
        let names = { (key: String) in Set((manifest[key] as? [Any] ?? []).compactMap { $0 as? String }) }
        return (names("permissions"), names("optional_permissions"))
    }

    /// Whether the extension may use `api` now: asked for in its manifest,
    /// or optional and granted since (`permissions.request`).
    func allows(_ api: String, for context: WKWebExtensionContext) -> Bool {
        let declared = Self.declaredPermissions(of: context.webExtension)
        if declared.required.contains(api) { return true }
        return declared.optional.contains(api) && grants.isGranted(api, id: context.uniqueIdentifier)
    }

    /// Its user scripts may run: the API asked for and allowed by the user.
    func runsUserScripts(_ context: WKWebExtensionContext) -> Bool {
        allows("userScripts", for: context) && userScriptsAllowed(context.uniqueIdentifier)
    }

    /// One call: `{api, method, details}`. Its value, or an error the
    /// extension sees as Chrome's.
    func handle(_ message: Any?, from context: WKWebExtensionContext) async throws -> Any? {
        guard let message = message as? [String: Any],
              let api = message["api"] as? String,
              let method = message["method"] as? String
        else { throw Failure.invalid("Invalid call.") } // not shown
        let details = message["details"] as? [String: Any] ?? [:]
        if api == "permissions" { return try await permissions(method, details, context: context) }
        if api == "events", method == "next" {
            // Only for an extension that may have events: else it stops
            // asking (until a listener is added again).
            guard allows("idle", for: context) || allows("notifications", for: context) else {
                return ["stop": true]
            }
            return try await events.next(
                extensionID: context.uniqueIdentifier,
                client: details["client"] as? String ?? "",
                isWorker: details["worker"] as? Bool == true
            )
        }
        guard ExtensionComplementScript.permissions.contains(api) else { throw Failure.unknownCall(api) }
        guard allows(api, for: context) else {
            let name = context.webExtension.displayName ?? context.uniqueIdentifier
            logger.notice("\(name, privacy: .public) refused: \(api, privacy: .public)")
            throw Failure.notAllowed(api)
        }
        switch api {
        case "privacy":
            return try privacy.handle(
                method,
                details,
                extensionID: context.uniqueIdentifier,
                extensionName: context.webExtension.displayShortName ?? context.webExtension.displayName
            )
        case "offscreen":
            return try await offscreen.handle(method, details, context: context)
        case "idle":
            return try idle.handle(method, details, extensionID: context.uniqueIdentifier)
        case "notifications":
            return try await notifications.handle(
                method,
                details,
                extensionID: context.uniqueIdentifier,
                extensionName: context.webExtension.displayShortName ?? context.webExtension.displayName
            )
        case "userScripts":
            guard userScriptsAllowed(context.uniqueIdentifier) else { throw Failure.userScriptsOff }
            return try userScripts.handle(method, details, extensionID: context.uniqueIdentifier)
        default:
            throw Failure.unknownCall(api)
        }
    }

    /// `permissions.contains`, `request`, `remove` for the added APIs only.
    private func permissions(
        _ method: String,
        _ details: [String: Any],
        context: WKWebExtensionContext
    ) async throws -> Any {
        if method == "granted" {
            return ExtensionComplementScript.permissions.filter { allows($0, for: context) }.sorted()
        }
        let names = (details["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        guard names.allSatisfy(ExtensionComplementScript.permissions.contains) else {
            throw Failure.invalid("Only the permissions Ombre adds can be asked here.") // not shown
        }
        let declared = Self.declaredPermissions(of: context.webExtension)
        let id = context.uniqueIdentifier
        switch method {
        case "contains":
            return names.allSatisfy { allows($0, for: context) }
        case "request":
            // As Chrome: only what the manifest lists, asked to the user
            // (as Ombre's other optional permissions); a refusal isn't asked again.
            guard names.allSatisfy({ declared.required.contains($0) || declared.optional.contains($0) }) else {
                throw Failure.invalid("Only permissions specified in the manifest may be requested.") // not shown
            }
            let undecided = names.filter {
                !declared.required.contains($0) && !grants.isGranted($0, id: id) && !grants.isDenied($0, id: id)
            }
            if !undecided.isEmpty {
                let allowed = await withCheckedContinuation { continuation in
                    askUser(undecided, context) { continuation.resume(returning: $0) }
                }
                for name in undecided {
                    if allowed { grants.grant(name, id: id) } else { grants.deny(name, id: id) }
                }
                // Its registered scripts run again.
                if allowed, undecided.contains("userScripts") { userScriptsDidChange() }
            }
            return names.allSatisfy { allows($0, for: context) }
        case "remove":
            // Required ones can't be removed, as in Chrome.
            guard names.allSatisfy({ !declared.required.contains($0) }) else {
                throw Failure.invalid("You cannot remove required permissions.") // not shown
            }
            for name in names {
                grants.revoke(name, id: id)
            }
            if names.contains("userScripts") { userScriptsDidChange() }
            return true
        default:
            throw Failure.unknownCall("permissions.\(method)")
        }
    }

    /// The extension is gone: its documents, its settings and its grants.
    func extensionUnloaded(_ context: WKWebExtensionContext) {
        offscreen.close(for: context.uniqueIdentifier)
        userScriptMessages.extensionUnloaded(id: context.uniqueIdentifier)
        idle.forget(extensionID: context.uniqueIdentifier)
        notifications.forget(extensionID: context.uniqueIdentifier)
        events.forget(extensionID: context.uniqueIdentifier)
    }

    /// Turned off: what it changed goes back, as in Chrome.
    func extensionDisabled(id: String) {
        privacy.release(extensionID: id)
    }

    func extensionRemoved(id: String) {
        privacy.release(extensionID: id)
        grants.forget(id: id)
        userScripts.forget(id: id)
    }

    /// Its service worker listens for its user scripts' messages
    /// (`connectNative` to Ombre's channel, from its complement).
    func connect(_ port: WKWebExtension.MessagePort, for context: WKWebExtensionContext) -> Bool {
        guard runsUserScripts(context) else { return false }
        userScriptMessages.connect(port, for: context)
        return true
    }

    /// Extension pages get the complement and its channel (`handler`).
    static func configure(_ configuration: WKWebViewConfiguration, handler: WKScriptMessageHandlerWithReply) {
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(
            source: ExtensionComplementScript.pageSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        ))
        content.addScriptMessageHandler(handler, contentWorld: .page, name: ExtensionComplementScript.handlerName)
        configuration.userContentController = content
    }

    /// From an extension page (`ExtensionComplementScript.handlerName`): the
    /// extension is the one of the frame's origin, an extension page's.
    func reply(to message: WKScriptMessage, controller: WKWebExtensionController) async -> (Any?, String?) {
        let origin = message.frameInfo.securityOrigin
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        components.path = "/"
        guard origin.protocol == ExtensionBaseURL.scheme, let url = components.url,
              let context = controller.extensionContext(for: url)
        else { return (nil, "Not an extension page.") } // not shown
        do {
            return try await (["value": handle(message.body, from: context) ?? NSNull()], nil)
        } catch {
            return (["error": error.localizedDescription], nil)
        }
    }
}

/// Optional permissions of the added APIs granted to an extension
/// (`permissions.request`), kept between launches.
@MainActor
final class ExtensionComplementGrants {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "extensions.complementGrants") {
        self.defaults = defaults
        self.key = key
    }

    private var all: [String: [String]] {
        get { defaults.dictionary(forKey: key) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: key) }
    }

    func isGranted(_ name: String, id: String) -> Bool {
        all[id]?.contains(name) == true
    }

    func grant(_ name: String, id: String) {
        var names = Set(all[id] ?? [])
        names.insert(name)
        all[id] = names.sorted()
    }

    /// Refused by the user: not asked again (until the extension is removed).
    func deny(_ name: String, id: String) {
        grant("denied:" + name, id: id)
    }

    func isDenied(_ name: String, id: String) -> Bool {
        isGranted("denied:" + name, id: id)
    }

    func revoke(_ name: String, id: String) {
        var names = Set(all[id] ?? [])
        names.remove(name)
        all[id] = names.isEmpty ? nil : names.sorted()
    }

    func forget(id: String) {
        all[id] = nil
    }
}

/// The pages' channel to `ExtensionComplements`, without holding the manager.
@available(macOS 15.4, *)
@MainActor
final class ExtensionComplementHandler: NSObject, WKScriptMessageHandlerWithReply {
    /// The complements and the controller of the extensions (weak: not held).
    var target: () -> (ExtensionComplements, WKWebExtensionController)? = { nil }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let (complements, controller) = target() else { return (nil, "Ombre isn't ready.") } // not shown
        return await complements.reply(to: message, controller: controller)
    }
}
