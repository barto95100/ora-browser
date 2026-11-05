import Foundation

/// Websites an extension was allowed or refused on from a private window:
/// kept in memory only (never in `extensions.json`), forgotten when the last
/// private window closes.
struct PrivateSiteDecisions {
    struct Entry: Equatable {
        let host: String
        let decision: SiteDecision
        /// "Allow for One Day".
        let expiresAt: Date?
    }

    /// "All websites", asked from a private window.
    static let allSites = "*"

    private var entries: [String: [String: Entry]] = [:]

    var extensionIDs: [String] {
        Array(entries.keys)
    }

    func decision(for host: String, extensionID: String, at date: Date = Date()) -> SiteDecision? {
        let isLive: (Entry) -> Bool = { $0.expiresAt.map { $0 > date } ?? true }
        let hostEntry = entries[extensionID]?[host].flatMap { isLive($0) ? $0 : nil }
        let allSitesEntry = entries[extensionID]?[Self.allSites].flatMap { isLive($0) ? $0 : nil }
        return (hostEntry ?? allSitesEntry)?.decision
    }

    /// The decisions still in force for an extension.
    func entries(for extensionID: String, at date: Date = Date()) -> [Entry] {
        (entries[extensionID]?.values ?? [:].values)
            .filter { $0.expiresAt.map { $0 > date } ?? true }
            .sorted { $0.host < $1.host }
    }

    /// `.ask` forgets it.
    mutating func set(_ decision: SiteDecision, for host: String, until expiresAt: Date? = nil, extensionID: String) {
        if decision == .ask {
            entries[extensionID]?[host] = nil
            if entries[extensionID]?.isEmpty == true { entries[extensionID] = nil }
        } else {
            entries[extensionID, default: [:]][host] = Entry(host: host, decision: decision, expiresAt: expiresAt)
        }
    }

    mutating func removeAll() {
        entries = [:]
    }
}
