import Foundation
@preconcurrency import WebKit

@MainActor
final class BrowserEngineProfile {
    let identifier: UUID
    let isPrivate: Bool
    let dataStore: WKWebsiteDataStore

    /// `privateDataStore`: the private window's session, shared by its tabs.
    init(identifier: UUID, isPrivate: Bool, privateDataStore: WKWebsiteDataStore? = nil) {
        self.identifier = identifier
        self.isPrivate = isPrivate
        if isPrivate {
            dataStore = privateDataStore ?? WKWebsiteDataStore.nonPersistent()
        } else {
            dataStore = WKWebsiteDataStore(forIdentifier: identifier)
        }
    }

    func clearData(
        ofTypes types: Set<BrowserWebsiteDataType>,
        forHost host: String? = nil,
        completion: (@MainActor () -> Void)? = nil
    ) {
        Self.clearData(in: dataStore, ofTypes: types, forHost: host, completion: completion)
    }

    /// Clears a store's data, or only a website's: `host` (e.g.
    /// "mail.google.com") and its records' domain ("google.com").
    static func clearData(
        in dataStore: WKWebsiteDataStore,
        ofTypes types: Set<BrowserWebsiteDataType>,
        forHost host: String? = nil,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let mappedTypes = mapWebsiteDataTypes(types)
        guard let host, !host.isEmpty else {
            dataStore.removeData(ofTypes: mappedTypes, modifiedSince: .distantPast) {
                completion?()
            }
            return
        }

        dataStore.fetchDataRecords(ofTypes: mappedTypes) { records in
            let targetRecords = records.filter { isRecord(named: $0.displayName, of: host) }
            guard !targetRecords.isEmpty else {
                completion?()
                return
            }

            dataStore.removeData(ofTypes: mappedTypes, for: targetRecords) {
                completion?()
            }
        }
    }

    /// Whether a data record (named after its domain, "google.com") is the
    /// website's: the same host or one of its subdomains, never a mere
    /// substring ("x.com" isn't "box.com").
    nonisolated static func isRecord(named name: String, of host: String) -> Bool {
        let name = name.lowercased()
        let host = host.lowercased()
        return host == name || host.hasSuffix("." + name)
    }

    private static func mapWebsiteDataTypes(_ types: Set<BrowserWebsiteDataType>) -> Set<String> {
        if types.contains(.all) {
            return WKWebsiteDataStore.allWebsiteDataTypes()
        }

        var mapped: Set<String> = []
        if types.contains(.cookies) {
            mapped.insert(WKWebsiteDataTypeCookies)
        }
        if types.contains(.cache) {
            mapped.formUnion([
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeFetchCache
            ])
        }
        return mapped
    }
}
