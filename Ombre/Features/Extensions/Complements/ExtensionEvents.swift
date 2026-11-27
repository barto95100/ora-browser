import Foundation

/// Events of the added APIs (`idle.onStateChanged`, `notifications.onClicked`…)
/// to an extension's pages and service worker, which have only a channel
/// they call (`ExtensionComplementScript`): each context that listens keeps
/// one call waiting (`next`), answered when an event comes. Nothing runs
/// between events: no polling.
///
/// A context that doesn't ask again soon after an answer is gone (a worker
/// that slept, a closed popup). Events while no worker listens (it slept),
/// or that a worker got as it went, are kept a little for the next worker,
/// which is woken for them: each event once.
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
        let isWorker: Bool
        var queue: [Event] = []
        var waiter: CheckedContinuation<Batch, Never>?
        /// How many times it asked: an answer it doesn't follow is lost.
        var asks = 0
        var askedAt = Date()

        init(isWorker: Bool) {
            self.isWorker = isWorker
        }
    }

    /// An event no worker took (it slept): for the next worker, once.
    private final class Kept {
        let event: Event
        let at: Date
        var givenTo: Set<String>

        init(event: Event, at: Date, givenTo: Set<String>) {
            self.event = event
            self.at = at
            self.givenTo = givenTo
        }
    }

    /// Starts the extension's background (its worker listens again).
    var wake: (String) -> Void = { _ in }
    /// How long an event waits for a worker that starts.
    var keptFor: TimeInterval = 30
    /// How soon a context asks again after an answer, else it is gone.
    var askAgainWithin: Duration = .seconds(2)
    private static let maxKept = 50
    /// Contexts of one extension listening at once (its pages and worker):
    /// beyond, the one that asked longest ago goes.
    static let maxClients = 32

    private var clients: [String: [String: Client]] = [:]
    /// By event number.
    private var kept: [String: [Int: Kept]] = [:]
    private var sequence = 0
    /// Extensions whose worker listened since they started: only theirs
    /// are kept, and their worker woken.
    private var workers: Set<String> = []

    /// The next events for this context of the extension, at once if some
    /// wait, else when one comes.
    func next(extensionID: String, client: String, isWorker: Bool) async throws -> [Event] {
        guard !client.isEmpty, client.count <= 64 else {
            throw ExtensionComplementFailure.invalid("Invalid client.") // not shown
        }
        var list = clients[extensionID] ?? [:]
        let item: Client
        if let known = list[client] {
            item = known
        } else {
            if list.count >= Self.maxClients, let oldest = list.min(by: { $0.value.askedAt < $1.value.askedAt }) {
                oldest.value.waiter?.resume(returning: Batch(events: []))
                oldest.value.waiter = nil
                list[oldest.key] = nil
            }
            item = Client(isWorker: isWorker)
            list[client] = item
            clients[extensionID] = list
        }
        if item.isWorker { workers.insert(extensionID) }
        item.asks += 1
        item.askedAt = Date()
        // One call waits per context: an older one gets nothing.
        item.waiter?.resume(returning: Batch(events: []))
        item.waiter = nil
        if item.isWorker {
            let cutoff = Date().addingTimeInterval(-keptFor)
            kept[extensionID] = kept[extensionID]?.filter { $0.value.at > cutoff }
            for (_, waiting) in (kept[extensionID] ?? [:]).sorted(by: { $0.key < $1.key })
                where waiting.givenTo.insert(client).inserted
            {
                item.queue.append(waiting.event)
            }
        }
        if !item.queue.isEmpty {
            let events = item.queue
            item.queue = []
            answered(item, client: client, extensionID: extensionID, events: events)
            return events
        }
        return await withCheckedContinuation { item.waiter = $0 }.events
    }

    /// An event for every context of the extension that listens; kept for
    /// its worker if none listens now.
    func dispatch(_ name: String, _ args: [Any], to extensionID: String) {
        sequence += 1
        let event: Event = ["name": name, "args": args, "seq": sequence]
        let listening = clients[extensionID] ?? [:]
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
        if !listening.values.contains(where: \.isWorker) {
            keep([event], for: extensionID, given: [])
        }
    }

    /// Given `events`: if it doesn't ask again soon, it is gone; a
    /// worker's wait for the next one.
    private func answered(_ client: Client, client key: String, extensionID: String, events: [Event]) {
        let asks = client.asks
        let delay = askAgainWithin
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, clients[extensionID]?[key] === client, client.asks == asks else { return }
            clients[extensionID]?[key] = nil
            if clients[extensionID]?.isEmpty == true { clients[extensionID] = nil }
            // Itself included: late rather than gone, it doesn't get them twice.
            if client.isWorker { keep(events + client.queue, for: extensionID, given: [key]) }
        }
    }

    private func keep(_ events: [Event], for extensionID: String, given: Set<String>) {
        guard workers.contains(extensionID), !events.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-keptFor)
        var list = (kept[extensionID] ?? [:]).filter { $0.value.at > cutoff }
        for event in events {
            guard let seq = event["seq"] as? Int else { continue }
            if let known = list[seq] {
                known.givenTo.formUnion(given)
            } else {
                list[seq] = Kept(event: event, at: Date(), givenTo: given)
            }
        }
        if list.count > Self.maxKept {
            for seq in list.keys.sorted().prefix(list.count - Self.maxKept) {
                list[seq] = nil
            }
        }
        kept[extensionID] = list
        // A worker that listens now has them: only a sleeping one is woken.
        if clients[extensionID]?.values.contains(where: \.isWorker) != true { wake(extensionID) }
    }

    /// The extension stopped: its waiting calls end, nothing is kept.
    func forget(extensionID: String) {
        for client in (clients.removeValue(forKey: extensionID) ?? [:]).values {
            client.waiter?.resume(returning: Batch(events: []))
            client.waiter = nil
        }
        kept[extensionID] = nil
        workers.remove(extensionID)
    }

    /// How many contexts of the extension listen (for the tests).
    func listeners(of extensionID: String) -> Int {
        clients[extensionID]?.count ?? 0
    }
}
