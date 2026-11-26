import CryptoKit
import Foundation
import os.log
import WebKit

/// The hidden elements of a space as a WebKit content rule list
/// (`css-display-none`): WebKit hides them before the page shows, without
/// a script or a style the page could see. One list per space, compiled
/// again when its elements change.
@MainActor
final class HiddenElementRuleLists {
    static let shared = HiddenElementRuleLists()

    /// Posted with the space (`spaceID`) once its new list is ready.
    static let didChange = Notification.Name("HiddenElementRuleLists.didChange")

    private let store: HiddenElementsStore
    private var ruleLists: [UUID: WKContentRuleList] = [:]
    /// Spaces whose list is known (compiled, looked up, or none).
    private var loaded: Set<UUID> = []
    private var waiting: [UUID: [(WKContentRuleList?) -> Void]] = [:]
    /// Only the latest compilation of a space counts.
    private var generations: [UUID: Int] = [:]
    private static let logger = Logger(category: "HiddenElements")

    init(store: HiddenElementsStore = .shared) {
        self.store = store
    }

    /// The space's list (nil: nothing hidden), compiled once per launch at most.
    func ruleList(for spaceID: UUID, completion: @escaping (WKContentRuleList?) -> Void) {
        if loaded.contains(spaceID) { return completion(ruleLists[spaceID]) }
        if waiting[spaceID] != nil {
            waiting[spaceID]?.append(completion)
            return
        }
        waiting[spaceID] = [completion]
        compile(spaceID)
    }

    /// The space's elements changed: its list is compiled again, then
    /// `didChange` tells the windows.
    func update(_ spaceID: UUID, completion: ((WKContentRuleList?) -> Void)? = nil) {
        loaded.remove(spaceID)
        waiting[spaceID, default: []].append(completion ?? { _ in })
        // Again even if a compilation is under way: it predates the change.
        compile(spaceID)
    }

    /// The list already compiled for these very elements (a launch), else
    /// compiled now; older versions of the space's list are removed.
    private func compile(_ spaceID: UUID) {
        generations[spaceID, default: 0] += 1
        let generation = generations[spaceID]
        guard let ruleListStore = WKContentRuleListStore.default() else { return finish(spaceID, nil) }
        let encoded = Self.encodedRules(store.elements(in: spaceID))
        let identifier = encoded.map { Self.identifier(for: spaceID, rules: $0) }
        let done: (WKContentRuleList?) -> Void = { list in
            guard self.generations[spaceID] == generation else { return }
            self.removeOtherVersions(of: spaceID, keeping: identifier, in: ruleListStore)
            self.finish(spaceID, list)
        }
        guard let encoded, let identifier else { return done(nil) }
        ruleListStore.lookUpContentRuleList(forIdentifier: identifier) { found, _ in
            MainActor.assumeIsolated {
                if let found { return done(found) }
                ruleListStore.compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: encoded
                ) { list, error in
                    MainActor.assumeIsolated {
                        guard let list else {
                            // The previous list stays, in the store and on the pages.
                            Self.logger.error("""
                            Hidden elements not compiled: \(error?.localizedDescription ?? "?", privacy: .public)
                            """)
                            guard self.generations[spaceID] == generation else { return }
                            return self.finish(spaceID, self.ruleLists[spaceID])
                        }
                        done(list)
                    }
                }
            }
        }
    }

    private func removeOtherVersions(of spaceID: UUID, keeping identifier: String?, in store: WKContentRuleListStore) {
        let prefix = Self.identifierPrefix(for: spaceID)
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for other in identifiers ?? [] where other.hasPrefix(prefix) && other != identifier {
                store.removeContentRuleList(forIdentifier: other) { _ in }
            }
        }
    }

    /// Whether WebKit accepts this element's rule (its content rules are
    /// stricter than the page's `querySelectorAll`): a rule it refuses
    /// would void the whole list of the space. Compiled apart, then removed.
    func accepts(_ element: HiddenElement, onSite site: String, completion: @escaping (Bool) -> Void) {
        guard let ruleListStore = WKContentRuleListStore.default(),
              let encoded = Self.encodedRules([site: [element]])
        else { return completion(false) }
        let identifier = AppIdentity.identifier("hiddenElementsCheck.\(UUID().uuidString)")
        ruleListStore.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) { list, _ in
            MainActor.assumeIsolated {
                ruleListStore.removeContentRuleList(forIdentifier: identifier) { _ in }
                completion(list != nil)
            }
        }
    }

    private func finish(_ spaceID: UUID, _ list: WKContentRuleList?) {
        ruleLists[spaceID] = list
        loaded.insert(spaceID)
        let callbacks = waiting.removeValue(forKey: spaceID) ?? []
        callbacks.forEach { $0(list) }
        NotificationCenter.default.post(name: Self.didChange, object: nil, userInfo: ["spaceID": spaceID])
    }

    nonisolated static func identifierPrefix(for spaceID: UUID) -> String {
        AppIdentity.identifier("hiddenElements.\(spaceID.uuidString).")
    }

    /// A version per content: a list compiled at a previous launch is used
    /// again only if the elements are the same.
    nonisolated static func identifier(for spaceID: UUID, rules: String) -> String {
        let digest = SHA256.hash(data: Data(rules.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return identifierPrefix(for: spaceID) + digest
    }

    /// Sites as WebKit's `if-domain` wants them: ASCII (an international
    /// name in its `xn--` form) and lowercase. Nil if it can't be.
    nonisolated static func ruleDomain(_ site: String) -> String? {
        let lowered = site.lowercased()
        let host = lowered.allSatisfy(\.isASCII) ? lowered : URL(string: "https://\(lowered)/")?.host
        guard let host, !host.isEmpty,
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
                      .contains($0) })
        else { return nil }
        return host
    }

    /// One rule per element: an invalid selector would void a whole group.
    /// `*site`: the site and its subdomains.
    nonisolated static func rules(_ elements: HiddenElementsStore.SpaceElements) -> [[String: Any]] {
        elements.keys.sorted().flatMap { site -> [[String: Any]] in
            guard let domain = ruleDomain(site) else { return [] }
            return (elements[site] ?? []).map { element -> [String: Any] in
                [
                    "trigger": ["url-filter": ".*", "if-domain": ["*" + domain]],
                    "action": ["type": "css-display-none", "selector": element.selector]
                ]
            }
        }
    }

    /// Nil when nothing is hidden: no list at all.
    nonisolated static func encodedRules(_ elements: HiddenElementsStore.SpaceElements) -> String? {
        let rules = rules(elements)
        guard !rules.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
