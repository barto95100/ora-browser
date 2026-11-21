import Foundation
import SwiftData

/// Settings › Address Rules: links from other apps, and the new tabs a page
/// opens, go to the space a rule gives (`AddressRule`). Never a private
/// window, never a navigation in the same tab nor an address typed.
extension TabManager {
    /// The space a link to `url` goes to by the rules, if it's not `current`
    /// (nil: it stays where it would open). Logged with the domain only.
    func addressRuleSpace(for url: URL?, from current: TabContainer?) -> TabContainer? {
        guard !isPrivateWindow, let url else { return nil }
        let rules = SettingsStore.shared.addressRules
        guard !rules.isEmpty else { return nil }
        let spaces = (try? modelContext.fetch(FetchDescriptor<TabContainer>())) ?? []
        let spaceIDs = Set(spaces.map(\.id))
        guard case let .space(id) = AddressRouting.decide(
            url: url, currentSpaceID: current?.id, isPrivate: isPrivateWindow, rules: rules, spaceIDs: spaceIDs
        ), let space = spaces.first(where: { $0.id == id }),
              let rule = AddressRule.rule(for: url, in: rules, spaceIDs: spaceIDs)
        else { return nil }
        LinkLog.notice("address rule \(rule.kind.rawValue) \(rule.domain) applied: space \(space.name)") // not shown
        return space
    }
}
