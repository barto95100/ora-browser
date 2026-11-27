import Foundation

/// Events of the added APIs (`idle.onStateChanged`, `notifications.onClicked`…)
/// to an extension's pages and service worker, which have only a channel
/// they call (`ExtensionComplementScript`): each context that listens keeps
/// one call waiting (`next`), answered when an event comes. Nothing runs
/// between events: no polling.
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
        /// Its last answer: a context that doesn't ask again is gone.
        var answeredAt = Date()
    }

    /// Events for an extension that no context listens to now (its worker
    /// sleeps): kept a little, for the one that starts.
    private struct Kept {
        let event: Event
        let at: Date
    }

    /// Starts the extension's background (its worker listens again).
    var wake: (String) -> Void = { _ in }
    /// How long an event waits for a context that starts, and a context
    /// that doesn't ask again is kept.
    var keptFor: TimeInterval = 60
    private static let maxKept = 50

    private var clients: [String: [String: Client]] = [:]
    private var kept: [String: [Kept]] = [:]
    /// Extensions that listened since they started: only theirs are kept
    /// (and their worker woken).
    private var listened: Set<String> = []

    /// The next events for this context of the extension, at once if some
    /// wait, else when one comes.
    func next(extensionID: String, client: String) async -> [Event] {
        guard !client.isEmpty, client.count <= 64 else { return [] }
        let item = clients[extensionID]?[client] ?? Client()
        clients[extensionID, default: [:]][client] = item
        listened.insert(extensionID)
        // One call waits per context: an older one gets nothing.
        item.waiter?.resume(returning: Batch(events: []))
        item.waiter = nil
        let cutoff = Date().addingTimeInterval(-keptFor)
        if let waiting = kept.removeValue(forKey: extensionID) {
            item.queue += waiting.filter { $0.at > cutoff }.map(\.event)
        }
        if !item.queue.isEmpty {
            defer { item.queue = []
                item.answeredAt = Date()
            }
            return item.queue
        }
        return await withCheckedContinuation { item.waiter = $0 }.events
    }

    /// An event for every context of the extension that listens.
    func dispatch(_ name: String, _ args: [Any], to extensionID: String) {
        let event: Event = ["name": name, "args": args]
        let cutoff = Date().addingTimeInterval(-keptFor)
        // Gone: answered long ago and never came back.
        clients[extensionID] = clients[extensionID]?.filter { $0.value.waiter != nil || $0.value.answeredAt > cutoff }
        guard let listening = clients[extensionID], !listening.isEmpty else {
            guard listened.contains(extensionID) else { return }
            var list = (kept[extensionID] ?? []).filter { $0.at > cutoff }
            list.append(Kept(event: event, at: Date()))
            kept[extensionID] = Array(list.suffix(Self.maxKept))
            wake(extensionID)
            return
        }
        for client in listening.values {
            if let waiter = client.waiter {
                client.waiter = nil
                client.answeredAt = Date()
                waiter.resume(returning: Batch(events: client.queue + [event]))
                client.queue = []
            } else {
                client.queue = Array((client.queue + [event]).suffix(Self.maxKept))
            }
        }
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
