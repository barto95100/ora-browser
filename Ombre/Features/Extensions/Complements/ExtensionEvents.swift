import Foundation

/// Events of the added APIs (`idle.onStateChanged`, `notifications.onClicked`…)
/// to an extension's pages and service worker, which have only a channel
/// they call (`ExtensionComplementScript`): each context that listens keeps
/// one call waiting (`next`), answered when an event comes. Nothing runs
/// between events: no polling.
///
/// A context that doesn't ask again soon after an answer is gone (a worker
/// that slept, a closed popup): what it was given is kept for the next
/// context, and the worker is woken for it.
///
/// The extension is the one of the channel; `client` only tells its own
/// contexts apart, and reaches nothing of another extension.
@MainActor
final class ExtensionEvents {
    /// One event: `{name: "idle.onStateChanged", args: […]}`.
    typealias Event = [String: Any]

    /// What a waiting call gets (JSON values, on the main actor only).
    private struct Batch: @unchecked Sendable {
        let events: [Event]
    }

    private final class Client {
        var queue: [Event] = []
        var waiter: CheckedContinuation<Batch, Never>?
        /// How many times it asked: an answer it doesn't follow is lost.
        var asks = 0
        var answeredAt = Date()
    }

    /// An event no context took (its worker slept): for each context that
    /// starts within `keptFor`, once.
    private final class Kept {
        let event: Event
        let at: Date
        var givenTo: Set<String> = []

        init(event: Event, at: Date) {
            self.event = event
            self.at = at
        }
    }

    /// Starts the extension's background (its worker listens again).
    var wake: (String) -> Void = { _ in }
    /// How long an event waits for a context that starts.
    var keptFor: TimeInterval = 60
    /// How soon a context asks again after an answer, else it is gone.
    var askAgainWithin: Duration = .seconds(2)
    private static let maxKept = 50
    /// Contexts of one extension listening at once (its pages and worker).
    static let maxClients = 32

    private var clients: [String: [String: Client]] = [:]
    private var kept: [String: [Kept]] = [:]
    /// Extensions that listened since they started: only theirs are kept
    /// (and their worker woken).
    private var listened: Set<String> = []

    /// The next events for this context of the extension, at once if some
    /// wait, else when one comes.
    func next(extensionID: String, client: String) async throws -> [Event] {
        guard !client.isEmpty, client.count <= 64 else {
            throw ExtensionComplementFailure.invalid("Invalid client.") // not shown
        }
        var list = clients[extensionID] ?? [:]
        let item: Client
        if let known = list[client] {
            item = known
        } else {
            guard list.count < Self.maxClients else {
                throw ExtensionComplementFailure.invalid("Too many listening contexts.") // not shown
            }
            item = Client()
            list[client] = item
            clients[extensionID] = list
        }
        listened.insert(extensionID)
        item.asks += 1
        // One call waits per context: an older one gets nothing.
        item.waiter?.resume(returning: Batch(events: []))
        item.waiter = nil
        let cutoff = Date().addingTimeInterval(-keptFor)
        kept[extensionID] = kept[extensionID]?.filter { $0.at > cutoff }
        for waiting in kept[extensionID] ?? [] where waiting.givenTo.insert(client).inserted {
            item.queue.append(waiting.event)
        }
        if !item.queue.isEmpty {
            let events = item.queue
            item.queue = []
            answered(item, client: client, extensionID: extensionID, events: events)
            return events
        }
        return await withCheckedContinuation { item.waiter = $0 }.events
    }

    /// An event for every context of the extension that listens.
    func dispatch(_ name: String, _ args: [Any], to extensionID: String) {
        let event: Event = ["name": name, "args": args]
        guard let listening = clients[extensionID], !listening.isEmpty else {
            keep([event], for: extensionID)
            return
        }
        for (key, client) in listening {
            if let waiter = client.waiter {
                client.waiter = nil
                let events = client.queue + [event]
                client.queue = []
                waiter.resume(returning: Batch(events: events))
                answered(client, client: key, extensionID: extensionID, events: events)
            } else {
                client.queue = Array((client.queue + [event]).suffix(Self.maxKept))
            }
        }
    }

    /// Given `events`: if it doesn't ask again soon, it is gone, and they
    /// wait for the next context.
    private func answered(_ client: Client, client key: String, extensionID: String, events: [Event]) {
        client.answeredAt = Date()
        let asks = client.asks
        let delay = askAgainWithin
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, clients[extensionID]?[key] === client, client.asks == asks else { return }
            clients[extensionID]?[key] = nil
            if clients[extensionID]?.isEmpty == true { clients[extensionID] = nil }
            // The others had them already.
            keep(events + client.queue, for: extensionID, given: Set(clients[extensionID].map { Array($0.keys) } ?? []))
        }
    }

    private func keep(_ events: [Event], for extensionID: String, given: Set<String> = []) {
        guard listened.contains(extensionID), !events.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-keptFor)
        var list = (kept[extensionID] ?? []).filter { $0.at > cutoff }
        list += events.map {
            let item = Kept(event: $0, at: Date())
            item.givenTo = given
            return item
        }
        kept[extensionID] = Array(list.suffix(Self.maxKept))
        wake(extensionID)
    }

    /// The extension stopped: its waiting calls end, nothing is kept.
    func forget(extensionID: String) {
        for client in (clients.removeValue(forKey: extensionID) ?? [:]).values {
            client.waiter?.resume(returning: Batch(events: []))
            client.waiter = nil
        }
        kept[extensionID] = nil
        listened.remove(extensionID)
    }

    /// How many contexts of the extension listen (for the tests).
    func listeners(of extensionID: String) -> Int {
        clients[extensionID]?.count ?? 0
    }
}
