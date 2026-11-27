import Foundation
@testable import Ombre
import Testing
import WebKit

/// `chrome.idle` and `chrome.notifications` (`ExtensionIdle`,
/// `ExtensionNotifications`) and their events (`ExtensionEvents`): with a
/// user state, notifications and a controller of the tests' own (never the
/// Mac's, never macOS's notifications).
@MainActor
@Suite(.serialized)
struct ExtensionIdleNotificationsTests {
    /// The user's state, as the tests say.
    final class User {
        var since: TimeInterval = 0
        var locked = false

        var source: ExtensionIdle.Source {
            .init(secondsSinceInput: { self.since }, isLocked: { self.locked })
        }
    }

    /// What would be shown.
    final class Shown {
        var list: [ExtensionNotifications.Shown] = []
        var removed: [String] = []
        var allowed = true

        var presenter: ExtensionNotifications.Presenter {
            .init(
                show: { self.list.append($0) },
                remove: { self.removed += $0 },
                isAllowed: { self.allowed }
            )
        }
    }

    // MARK: - Idle

    @Test func idleStatesAsChrome() throws {
        let user = User()
        let idle = ExtensionIdle(source: user.source, usesSystemEvents: false)
        #expect(try idle.handle("queryState", ["detectionIntervalInSeconds": 60], extensionID: "a") as? String
            == "active")
        user.since = 20
        // From 15 s: shorter asks for 15 s, as in Chrome.
        #expect(try idle.handle("queryState", ["detectionIntervalInSeconds": 5], extensionID: "a") as? String
            == "idle")
        #expect(try idle.handle("queryState", ["detectionIntervalInSeconds": 30], extensionID: "a") as? String
            == "active")
        user.locked = true
        #expect(try idle.handle("queryState", ["detectionIntervalInSeconds": 30], extensionID: "a") as? String
            == "locked")
        #expect(throws: ExtensionComplementFailure.self) {
            try idle.handle("queryState", ["detectionIntervalInSeconds": "x"], extensionID: "a")
        }
        #expect(ExtensionIdle.clamped(1) == 15 && ExtensionIdle.clamped(1_000_000) == 4 * 60 * 60)
    }

    @Test func idleChangesAreToldToWhoListens() throws {
        let user = User()
        let idle = ExtensionIdle(source: user.source, usesSystemEvents: false)
        var told: [String] = []
        idle.stateChanged = { id, state in told.append("\(id) \(state)") }
        _ = try idle.handle("setDetectionInterval", ["intervalInSeconds": 20], extensionID: "a")
        #expect(idle.interval(of: "a") == 20 && idle.interval(of: "b") == 60)
        _ = try idle.handle("watch", [:], extensionID: "a")
        _ = try idle.handle("watch", [:], extensionID: "b")
        #expect(told.isEmpty)
        user.since = 30
        idle.evaluate()
        #expect(told == ["a idle"])
        user.locked = true
        idle.evaluate()
        #expect(Set(told.suffix(2)) == ["a locked", "b locked"])
        user.locked = false
        user.since = 0
        idle.evaluate()
        #expect(Set(told.suffix(2)) == ["a active", "b active"])
        // Gone: no longer told, no longer watched.
        idle.forget(extensionID: "a")
        idle.forget(extensionID: "b")
        #expect(!idle.isWatching)
        user.since = 100
        idle.evaluate()
        #expect(told.count == 5)
    }

    // MARK: - Events

    @Test func eventsReachTheContextsThatListen() async throws {
        let events = ExtensionEvents()
        events.askAgainWithin = .milliseconds(300)
        var woken: [String] = []
        events.wake = { woken.append($0) }
        func args(_ list: [ExtensionEvents.Event]) -> [String] {
            list.compactMap { ($0["args"] as? [String])?.first }
        }
        func next(_ client: String, worker: Bool = true) async throws -> [ExtensionEvents.Event] {
            try await events.next(extensionID: "a", client: client, isWorker: worker)
        }
        // No worker ever listened: nothing kept, nobody woken.
        events.dispatch("idle.onStateChanged", ["idle"], to: "a")
        #expect(woken.isEmpty)

        let first = Task { try await next("worker") }
        let deadline = ContinuousClock.now + .seconds(5)
        while events.listeners(of: "a") == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        events.dispatch("idle.onStateChanged", ["idle"], to: "a")
        let got = try await first.value
        #expect(got.map { $0["name"] as? String } == ["idle.onStateChanged"] && args(got) == ["idle"])
        // Another extension's events never reach it.
        events.dispatch("idle.onStateChanged", ["locked"], to: "b")
        events.dispatch("idle.onStateChanged", ["active"], to: "a")
        #expect(try await args(next("worker")) == ["active"])
        #expect(woken.isEmpty)

        // It doesn't ask again (it slept): what it got is kept for the next
        // worker, which is woken; so is what comes while none listens.
        try await Task.sleep(for: .milliseconds(600))
        #expect(events.listeners(of: "a") == 0 && woken == ["a"])
        events.dispatch("notifications.onClicked", ["m"], to: "a")
        #expect(woken == ["a", "a"])
        // A page doesn't get them; the new worker does, once.
        let page = Task { try await next("popup", worker: false) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await args(next("worker2")) == ["active", "m"])
        events.dispatch("notifications.onClicked", ["p"], to: "a")
        #expect(try await args(page.value) == ["p"])
        #expect(try await args(next("worker2")) == ["p"])
        // The one that was late, not gone: what it had is not given twice,
        // what came after is.
        #expect(try await args(next("worker")) == ["m"])

        // Stopped: what waits ends.
        let waiting = Task { try await next("worker2") }
        try await Task.sleep(for: .milliseconds(100))
        events.forget(extensionID: "a")
        #expect(try await waiting.value.isEmpty)
        await #expect(throws: ExtensionComplementFailure.self) { try await next("") }
    }

    // MARK: - Notifications

    @Test func notificationsAsChrome() async throws {
        let shown = Shown()
        let notifications = ExtensionNotifications(presenter: shown.presenter)
        var told: [String] = []
        notifications.event = { _, name, args in told.append("\(name) \(args.map { "\($0)" }.joined(separator: ","))") }
        let options: [String: Any] = [
            "type": "basic", "iconUrl": "icon.png", "title": "Hello", "message": "World",
            "buttons": [["title": "One"], ["title": "Two"], ["title": "Three"]],
            "iconData": Data([1, 2, 3]).base64EncodedString(), "iconType": "image/png"
        ]
        func call(_ method: String, _ details: [String: Any]) async throws -> Any? {
            try await notifications.handle(method, details, extensionID: "a", extensionName: "Ext")
        }
        // Chrome's required properties.
        await #expect(throws: ExtensionComplementFailure.self) {
            try await call("create", ["options": ["type": "basic", "title": "T"]])
        }
        let id = try #require(try await call("create", ["options": options]) as? String)
        #expect(!id.isEmpty)
        #expect(try await call("create", ["notificationId": "mine", "options": options]) as? String == "mine")
        let first = try #require(shown.list.first)
        #expect(first.title == "Hello" && first.body == "World" && first.subtitle == "Ext")
        #expect(first.buttons == ["One", "Two"] && first.image == Data([1, 2, 3]))
        #expect(first.identifier == ExtensionNotifications.identifier(extensionID: "a", notificationID: id))

        #expect(try await call("update", ["notificationId": "mine", "options": ["message": "Again"]]) as? Bool == true)
        #expect(shown.list.last?.body == "Again" && shown.list.last?.title == "Hello")
        #expect(try await call("update", ["notificationId": "none", "options": [:]]) as? Bool == false)
        #expect(try await Set((call("getAll", [:]) as? [String: Bool] ?? [:]).keys) == [id, "mine"])
        #expect(try await notifications.handle("getAll", [:], extensionID: "b", extensionName: nil)
            as? [String: Bool] == [:])
        #expect(try await call("getPermissionLevel", [:]) as? String == "granted")

        notifications.respond(.button(1), extensionID: "a", notificationID: "mine")
        // Another extension can't answer for it, nor twice.
        notifications.respond(.click, extensionID: "b", notificationID: id)
        notifications.respond(.click, extensionID: "a", notificationID: "mine")
        #expect(told == ["notifications.onButtonClicked mine,1"])
        #expect(try await call("clear", ["notificationId": id]) as? Bool == true)
        #expect(try await call("clear", ["notificationId": id]) as? Bool == false)
        #expect(told.last == "notifications.onClosed \(id),false")

        _ = try await call("create", ["notificationId": "left", "options": options])
        notifications.forget(extensionID: "a")
        #expect(shown.removed.last == ExtensionNotifications.identifier(extensionID: "a", notificationID: "left"))
        #expect(try await (call("getAll", [:]) as? [String: Bool])?.isEmpty == true)
    }

    // MARK: - The channel

    @available(macOS 15.4, *)
    private func context(permissions: [String]) async throws -> WKWebExtensionContext {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("idle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let list = permissions.map { "\"\($0)\"" }.joined(separator: ",")
        let manifest = #"{"manifest_version":3,"name":"I","version":"1","permissions":[\#(list)]}"#
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        return try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
    }

    @available(macOS 15.4, *)
    private func complements(_ user: User, _ shown: Shown) throws -> ExtensionComplements {
        let defaults = try #require(UserDefaults(suiteName: "ExtensionIdleNotificationsTests-\(UUID().uuidString)"))
        return ExtensionComplements(
            privacy: ExtensionPrivacy(settings: ExtensionComplementTests.Setting(), defaults: defaults, key: "p"),
            idle: ExtensionIdle(source: user.source, usesSystemEvents: false),
            notifications: ExtensionNotifications(presenter: shown.presenter),
            grants: ExtensionComplementGrants(defaults: defaults, key: "grants")
        )
    }

    @Test func refusedWithoutThePermission() async throws {
        guard #available(macOS 15.4, *) else { return }
        let complements = try complements(User(), Shown())
        let without = try await context(permissions: ["storage"])
        let query: [String: Any] = [
            "api": "idle",
            "method": "queryState",
            "details": ["detectionIntervalInSeconds": 60]
        ]
        await #expect(throws: ExtensionComplementFailure.notAllowed("idle")) {
            try await complements.handle(query, from: without)
        }
        let create: [String: Any] = ["api": "notifications", "method": "getAll", "details": [:]]
        await #expect(throws: ExtensionComplementFailure.notAllowed("notifications")) {
            try await complements.handle(create, from: without)
        }
        // Its events neither.
        let next: [String: Any] = ["api": "events", "method": "next", "details": ["client": "c", "worker": true]]
        #expect(try await complements.handle(next, from: without) as? [String: Bool] == ["stop": true])
        let with = try await context(permissions: ["idle", "notifications"])
        #expect(try await complements.handle(query, from: with) as? String == "active")
        #expect(try await complements.handle(create, from: with) as? [String: Bool] == [:])

        // Each extension its own events, whatever `client` says.
        let other = try await context(permissions: ["notifications"])
        let waiting = Task { try await complements.handle(next, from: other) as? [[String: Any]] }
        let mine = Task { try await complements.handle(next, from: with) as? [[String: Any]] }
        let deadline = ContinuousClock.now + .seconds(5)
        while complements.events.listeners(of: with.uniqueIdentifier) == 0
            || complements.events.listeners(of: other.uniqueIdentifier) == 0, ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }
        complements.events.dispatch("notifications.onClicked", ["n"], to: with.uniqueIdentifier)
        #expect(try await mine.value?.count == 1)
        complements.events.forget(extensionID: other.uniqueIdentifier)
        #expect(try await waiting.value?.isEmpty == true)
        complements.events.forget(extensionID: with.uniqueIdentifier)
    }

    /// In the service worker of Ombre's copy: the APIs, a picture of its
    /// package, and events that come while the worker waits.
    @Test func inAServiceWorker() async throws {
        guard #available(macOS 15.4, *) else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("idle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = [
            "manifest.json": #"{"manifest_version":3,"name":"I","version":"1","permissions":["idle","notifications"],"background":{"service_worker":"sw.js"}}"#,
            "icon.png": "PNG",
            "sw.js": """
            const say = text => browser.runtime.sendNativeMessage("probe", text);
            chrome.idle.onStateChanged.addListener(state => say("state " + state));
            chrome.notifications.onClicked.addListener(id => say("clicked " + id));
            chrome.idle.setDetectionInterval(20);
            chrome.idle.queryState(60)
              .then(state => chrome.notifications.create("n1", { type: "basic", iconUrl: "icon.png", title: "T", message: "M" })
                .then(id => say(state + " " + id + " " + typeof chrome.notifications.onButtonClicked.addListener)))
              .catch(error => say("error " + error.message));
            """
        ]
        for (path, content) in files {
            try content.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        #expect(ExtensionComplementPackage.add(toFolder: folder)?.apis == ["idle", "notifications"])
        let user = User()
        let shown = Shown()
        let complements = try complements(user, shown)
        let delegate = WorkerProbe(complements: complements)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = delegate
        ExtensionBaseURL.registerScheme()
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
        let id = UUID().uuidString
        context.uniqueIdentifier = id
        ExtensionBaseURL.apply(to: context, id: id)
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: "idle"))
        context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: "notifications"))
        complements.loadedContext = { $0 == id ? context : nil }
        try controller.load(context)
        defer {
            try? controller.unload(context)
            complements.extensionUnloaded(context)
        }
        try await delegate.wait()
        #expect(delegate.messages == ["active n1 function"])
        #expect(shown.list.first?.image == Data("PNG".utf8) && shown.list.first?.title == "T")
        #expect(complements.idle.interval(of: id) == 20)

        // Later, while the worker's call waits.
        try await Task.sleep(for: .seconds(1))
        user.since = 30
        complements.idle.evaluate()
        complements.notifications.respond(.click, extensionID: id, notificationID: "n1")
        let deadline = ContinuousClock.now + .seconds(10)
        while delegate.messages.count < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(delegate.messages.dropFirst() == ["state idle", "clicked n1"])
    }
}
