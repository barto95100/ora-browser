import Foundation
import os.log
@preconcurrency import WebKit

private let logger = Logger(category: "ExtensionComplements")

/// `chrome.runtime.sendMessage` from the user scripts of a world with
/// messaging (`configureWorld`) to `runtime.onUserScriptMessage` of their
/// extension's service worker, as in Chrome.
///
/// The extension is the one of the world the message comes from (Ombre's
/// handler of that world, which no page reaches), never what the message
/// says. The worker listens through a native port to Ombre's channel
/// (`connectNative`), opened by the complement; woken when it sleeps.
@available(macOS 15.4, *)
@MainActor
final class ExtensionUserScriptMessages {
    static let handlerName = ExtensionComplementScript.userScriptHandlerName
    static let noReceiver = "Could not establish connection. Receiving end does not exist." // not shown
    static let portClosed = "The message port closed before a response was received." // not shown

    /// What a message is checked against, from Ombre.
    struct Checks {
        /// The extension running now, by id.
        var context: @MainActor (String) -> WKWebExtensionContext?
        /// Whether it may use `chrome.userScripts` (its manifest).
        var allowsUserScripts: @MainActor (WKWebExtensionContext) -> Bool
        var registered: @MainActor (String) -> ExtensionUserScripts.Registered
        /// Whether it may read the frame's page (Settings › Extensions).
        var mayRead: @MainActor (WKWebExtensionContext, URL) -> Bool = ExtensionUserScriptMessages.mayRead
    }

    static func mayRead(_ context: WKWebExtensionContext, _ url: URL) -> Bool {
        switch context.permissionStatus(for: url) {
        case .grantedExplicitly, .grantedImplicitly: true
        default: false
        }
    }

    /// A reply from the worker, whatever it holds (a JSON value).
    private struct Reply: @unchecked Sendable {
        let value: Any?
    }

    /// What the message comes from.
    struct Origin {
        let world: ExtensionUserScriptInjector.MessagingWorld
        /// The world WebKit says it was posted in.
        let worldName: String
        let frameURL: URL?
        let isMainFrame: Bool
        let isPrivate: Bool
    }

    var checks: Checks
    /// How long a sleeping worker has to listen again.
    var wakeTimeout: Duration = .seconds(5)

    private var ports: [String: WKWebExtension.MessagePort] = [:]
    private var waiting: [String: [UUID: CheckedContinuation<WKWebExtension.MessagePort?, Never>]] = [:]
    private var pending: [String: (extensionID: String, reply: CheckedContinuation<Reply, Error>)] = [:]
    private var handlers: [String: Handler] = [:]

    init(checks: Checks) {
        self.checks = checks
    }

    /// The handler of a messaging world, one per world (shared by the pages).
    func handler(for world: ExtensionUserScriptInjector.MessagingWorld) -> WKScriptMessageHandlerWithReply {
        if let handler = handlers[world.name] { return handler }
        let handler = Handler(world: world, messages: self)
        handlers[world.name] = handler
        return handler
    }

    /// The worker listens (`connectNative` to Ombre's channel).
    func connect(_ port: WKWebExtension.MessagePort, for context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        if let previous = ports[id], previous !== port { closed(previous, id: id) }
        ports[id] = port
        port.messageHandler = { [weak self, weak port] message, _ in
            MainActor.assumeIsolated {
                guard let self, let port, self.ports[id] === port else { return }
                self.answer(message, extensionID: id)
            }
        }
        port.disconnectHandler = { [weak self, weak port] _ in
            MainActor.assumeIsolated {
                guard let self, let port else { return }
                self.closed(port, id: id)
            }
        }
        for continuation in (waiting.removeValue(forKey: id) ?? [:]).values {
            continuation.resume(returning: port)
        }
    }

    /// The extension stops: what waits for it gets Chrome's error.
    func extensionUnloaded(id: String) {
        if let port = ports[id] {
            closed(port, id: id)
            port.disconnect()
        }
    }

    private func closed(_ port: WKWebExtension.MessagePort, id: String) {
        guard ports[id] === port else { return }
        ports[id] = nil
        for (key, item) in pending where item.extensionID == id {
            pending[key] = nil
            item.reply.resume(throwing: ExtensionComplementFailure.invalid(Self.portClosed))
        }
    }

    /// `{kind: "reply", id, value}` or `{…, error}` from the worker.
    private func answer(_ message: Any?, extensionID: String) {
        guard let message = message as? [String: Any], message["kind"] as? String == "reply",
              let id = message["id"] as? String, let item = pending[id], item.extensionID == extensionID
        else { return }
        pending[id] = nil
        if let error = message["error"] as? String {
            item.reply.resume(throwing: ExtensionComplementFailure.invalid(error))
        } else {
            item.reply.resume(returning: Reply(value: message["value"]))
        }
    }

    /// Checks a message, as Chrome would refuse it; the extension's context.
    func check(_ origin: Origin) throws -> WKWebExtensionContext {
        let id = origin.world.extensionID
        guard origin.worldName == origin.world.name, let context = checks.context(id) else {
            throw ExtensionComplementFailure.invalid(Self.noReceiver)
        }
        guard checks.allowsUserScripts(context) else {
            throw ExtensionComplementFailure.notAllowed("userScripts")
        }
        guard checks.registered(id).world(origin.world.worldId).messaging else {
            throw ExtensionComplementFailure
                .invalid("Messaging is not enabled for this user script world.") // not shown
        }
        guard !origin.isPrivate || context.hasAccessToPrivateData,
              let url = origin.frameURL, checks.mayRead(context, url)
        else {
            throw ExtensionComplementFailure.invalid("Cannot access the contents of this page.") // not shown
        }
        return context
    }

    /// A message from a user script: the worker's answer.
    func send(_ body: Any?, from origin: Origin) async throws -> Any? {
        let context = try check(origin)
        let id = context.uniqueIdentifier
        guard let port = await port(for: context) else {
            throw ExtensionComplementFailure.invalid(Self.noReceiver)
        }
        let messageID = UUID().uuidString
        var sender: [String: Any] = ["id": id]
        if let url = origin.frameURL {
            sender["url"] = url.absoluteString
            if let scheme = url.scheme, let host = url.host {
                sender["origin"] = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
            }
        }
        if origin.isMainFrame { sender["frameId"] = 0 }
        let message = (body as? [String: Any])?["message"] ?? NSNull()
        let reply: Reply = try await withCheckedThrowingContinuation { continuation in
            pending[messageID] = (id, continuation)
            port.sendMessage(
                ["kind": "message", "id": messageID, "message": message, "sender": sender]
            ) { [weak self] error in
                guard let error else { return }
                MainActor.assumeIsolated {
                    guard let item = self?.pending.removeValue(forKey: messageID) else { return }
                    logger.notice("User script message not delivered: \(error.localizedDescription, privacy: .public)")
                    item.reply.resume(throwing: ExtensionComplementFailure.invalid(Self.noReceiver))
                }
            }
        }
        return reply.value
    }

    /// Its worker's port, waking it when it sleeps.
    private func port(for context: WKWebExtensionContext) async -> WKWebExtension.MessagePort? {
        let id = context.uniqueIdentifier
        if let port = ports[id], !port.isDisconnected { return port }
        Task { try? await context.loadBackgroundContent() }
        let timeout = wakeTimeout
        let key = UUID()
        return await withCheckedContinuation { continuation in
            waiting[id, default: [:]][key] = continuation
            // Only this wait: another, later, has its own time.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, let item = waiting[id]?.removeValue(forKey: key) else { return }
                item.resume(returning: nil)
            }
        }
    }

    /// `chrome.runtime` of a messaging world: `id` and `sendMessage`,
    /// through Ombre's handler of that world only.
    static func runtimeSource(extensionID: String) -> String {
        let id = (try? JSONSerialization.data(withJSONObject: extensionID, options: .fragmentsAllowed))
            .flatMap { String(bytes: $0, encoding: .utf8) } ?? "\"\""
        return #"""
        (() => {
        const handlers = window.webkit && window.webkit.messageHandlers;
        const handler = handlers && handlers.\#(handlerName);
        if (!handler || globalThis.chrome && globalThis.chrome.runtime) return;
        const post = message => handler.postMessage(message);
        const id = \#(id);
        function sendMessage(...values) {
            const callback = typeof values[values.length - 1] === "function" ? values.pop() : undefined;
            if (values.length > 1 && values[0] === id) values.shift();
            const promise = Promise.resolve(post({ message: values[0] === undefined ? null : values[0] }))
                .then(reply => {
                    if (reply && typeof reply.error === "string") throw new Error(reply.error);
                    return reply ? reply.value : undefined;
                });
            if (!callback) return promise;
            promise.then(value => callback(value), () => callback(undefined));
            return undefined;
        }
        const runtime = Object.freeze({
            id: id,
            sendMessage: sendMessage,
            connect: () => { throw new Error("runtime.connect is not supported in user scripts."); }
        });
        globalThis.chrome = Object.freeze({ runtime: runtime });
        globalThis.browser = globalThis.chrome;
        })();
        """# // not shown
    }

    /// A messaging world's handler: what it receives comes from that world.
    final class Handler: NSObject, WKScriptMessageHandlerWithReply {
        let world: ExtensionUserScriptInjector.MessagingWorld
        weak var messages: ExtensionUserScriptMessages?

        init(world: ExtensionUserScriptInjector.MessagingWorld, messages: ExtensionUserScriptMessages) {
            self.world = world
            self.messages = messages
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) async -> (Any?, String?) {
            guard let messages else { return (nil, Self.notReady) }
            let origin = Origin(
                world: world,
                worldName: message.world.name ?? "",
                frameURL: message.frameInfo.request.url,
                isMainFrame: message.frameInfo.isMainFrame,
                isPrivate: message.webView.map { !$0.configuration.websiteDataStore.isPersistent } ?? true
            )
            do {
                return try await (["value": messages.send(message.body, from: origin) ?? NSNull()], nil)
            } catch {
                return (["error": error.localizedDescription], nil)
            }
        }

        private static let notReady = "Ombre isn't ready." // not shown
    }
}
