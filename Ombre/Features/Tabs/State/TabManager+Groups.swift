import Foundation
import SwiftData

/// Groups of a space's tabs, by site: what makes them and what the sidebar
/// shows (see `TabGroup`).
enum TabGrouping {
    /// Tabs of one site that make a group.
    static let threshold = 3

    /// The site a tab is grouped by: its registrable domain, for web pages.
    static func site(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return WebSite.registrableDomain(of: url)
    }

    /// The groups to make or to grow, by site, among `tabs` (in the
    /// sidebar's order). A site already grouped gets its tabs not grouped
    /// yet; another site needs `threshold` of them. `excluded`: tabs never
    /// grouped (taken out of a group by the user), `declined`: sites never
    /// grouped (ungrouped by the user); Tidy Tabs Now passes neither.
    static func siteGroups(
        _ tabs: [(id: UUID, site: String?)],
        grouped: Set<UUID>,
        groupedSites: Set<String>,
        excluded: Set<UUID> = [],
        declined: Set<String> = []
    ) -> [(site: String, ids: [UUID])] {
        var bySite: [String: [UUID]] = [:]
        var sites: [String] = []
        for tab in tabs where !grouped.contains(tab.id) && !excluded.contains(tab.id) {
            guard let site = tab.site, !declined.contains(site) else { continue }
            if bySite[site] == nil { sites.append(site) }
            bySite[site, default: []].append(tab.id)
        }
        return sites.compactMap { site in
            let ids = bySite[site] ?? []
            return groupedSites.contains(site) || ids.count >= threshold ? (site, ids) : nil
        }
    }

    /// A row of the normal tabs: a tab, or a group with its tabs.
    enum Row: Equatable {
        case tab(UUID)
        case group(UUID, tabs: [UUID])
    }

    /// The rows for `tabs` (in the sidebar's order): a group shows where
    /// its first tab is, its tabs under it, in their order. A group with
    /// fewer than two of these tabs doesn't show.
    static func rows(tabs: [UUID], groups: [(id: UUID, tabs: [UUID])]) -> [Row] {
        let shown = Set(tabs)
        var groupOf: [UUID: UUID] = [:]
        var members: [UUID: [UUID]] = [:]
        for group in groups {
            let live = tabs.filter { group.tabs.contains($0) }
            guard live.count >= 2 else { continue }
            members[group.id] = live
            for id in live where groupOf[id] == nil {
                groupOf[id] = group.id
            }
        }
        var rows: [Row] = []
        var placed = Set<UUID>()
        for id in tabs where shown.contains(id) {
            if let group = groupOf[id] {
                guard !placed.contains(group) else { continue }
                placed.insert(group)
                rows.append(.group(group, tabs: (members[group] ?? []).filter { groupOf[$0] == group }))
            } else {
                rows.append(.tab(id))
            }
        }
        return rows
    }
}

extension TabManager {
    /// The space's groups, ungrouped ones aside.
    func tabGroups(in container: TabContainer) -> [TabGroup] {
        allTabGroups(in: container).filter { !$0.isDissolved }
    }

    private func allTabGroups(in container: TabContainer) -> [TabGroup] {
        let spaceID = container.id
        let descriptor = FetchDescriptor<TabGroup>(
            predicate: #Predicate { $0.spaceID == spaceID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// The tabs that can be grouped, in the sidebar's order: the other tabs
    /// (not pinned nor favorites), outside a split.
    func groupableTabs(in container: TabContainer) -> [Tab] {
        let splits = splitPairs(in: container)
        let inSplit = Set(splits.keys).union(splits.values)
        // Their own order (not `sidebarOrder`, which shows the groups).
        return container.tabs
            .filter { $0.type == .normal && !inSplit.contains($0.id) }
            .sorted { $0.order > $1.order }
    }

    /// The groups as the sidebar shows them: their tabs that can be grouped
    /// (a tab gone into a split leaves them), for `TabGrouping.rows`.
    func shownGroups(_ groups: [TabGroup], in container: TabContainer) -> [(id: UUID, tabs: [UUID])] {
        let groupable = Set(groupableTabs(in: container).map(\.id))
        return groups.map { (id: $0.id, tabs: $0.tabIDs.filter { groupable.contains($0) }) }
    }

    /// The group `tab` is in, if any.
    func tabGroup(of tab: Tab) -> TabGroup? {
        tabGroups(in: tab.container).first { $0.tabIDs.contains(tab.id) }
    }

    /// The tabs of `group` still in its space (closed or moved ones aside).
    func tabs(of group: TabGroup, in container: TabContainer) -> [Tab] {
        groupableTabs(in: container).filter { group.tabIDs.contains($0.id) }
    }

    /// Tidy Tabs Now: groups the space's tabs by site, from three tabs of a
    /// site, also those taken out or ungrouped before.
    func tidyTabs(in container: TabContainer) {
        let all = allTabGroups(in: container)
        for group in all {
            group.releasedTabIDs = []
            if group.isDissolved { modelContext.delete(group) }
        }
        let groups = all.filter { !$0.isDissolved }
        let tabs = groupableTabs(in: container)
        // Tabs closed, moved or pinned since: no longer listed.
        let groupable = Set(tabs.map(\.id))
        for group in groups {
            group.tabIDs = group.tabIDs.filter { groupable.contains($0) }
        }
        let groupedIDs = Set(groups.flatMap(\.tabIDs))
        let made = TabGrouping.siteGroups(
            tabs.map { (id: $0.id, site: TabGrouping.site(of: $0.url)) },
            grouped: groupedIDs,
            groupedSites: Set(groups.compactMap { $0.kind == .site ? $0.siteKey : nil })
        )
        for (site, ids) in made {
            if let group = groups.first(where: { $0.kind == .site && $0.siteKey == site }) {
                group.tabIDs += ids
            } else {
                modelContext.insert(TabGroup(
                    spaceID: container.id,
                    name: site,
                    kind: .site,
                    siteKey: site,
                    tabIDs: ids
                ))
            }
        }
        modelContext.saveOrLog("tidy tabs")
    }

    /// A tab of a space grouping its tabs automatically loaded a page: it
    /// joins its site's group, or makes it once its site has three tabs.
    /// Never a tab the user took out of a group, nor a site they ungrouped.
    func autoGroup(_ tab: Tab) {
        guard tab.type == .normal, let container = tab.parentContainer,
              SettingsStore.shared.autoGroupsTabs(for: container.id),
              let site = TabGrouping.site(of: tab.url)
        else { return }
        let all = allTabGroups(in: container)
        let groups = all.filter { !$0.isDissolved }
        guard !groups.contains(where: { $0.tabIDs.contains(tab.id) }) else { return }
        let tabs = groupableTabs(in: container)
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        let made = TabGrouping.siteGroups(
            tabs.map { (id: $0.id, site: TabGrouping.site(of: $0.url)) },
            grouped: Set(groups.flatMap(\.tabIDs)),
            groupedSites: Set(groups.compactMap { $0.kind == .site ? $0.siteKey : nil }),
            excluded: Set(all.flatMap(\.releasedTabIDs)),
            declined: Set(all.compactMap { $0.isDissolved ? $0.siteKey : nil })
        )
        // Only this tab's site: the others wait for their own tabs.
        guard let ids = made.first(where: { $0.site == site })?.ids, ids.contains(tab.id) else { return }
        if let group = groups.first(where: { $0.kind == .site && $0.siteKey == site }) {
            group.tabIDs += ids
        } else {
            modelContext.insert(TabGroup(spaceID: container.id, name: site, kind: .site, siteKey: site, tabIDs: ids))
        }
        modelContext.saveOrLog("group tabs automatically")
    }

    func renameTabGroup(_ group: TabGroup, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != group.name else { return }
        group.name = name
        modelContext.saveOrLog("rename tab group")
    }

    func toggleTabGroup(_ group: TabGroup) {
        group.isCollapsed.toggle()
        modelContext.saveOrLog("toggle tab group")
    }

    /// Ungroup: its tabs stay where they are; its site isn't grouped again
    /// automatically.
    func ungroup(_ group: TabGroup) {
        group.tabIDs = []
        group.isDissolved = true
        modelContext.saveOrLog("ungroup tabs")
    }

    /// Takes `tab` out of its group, for good (not put back automatically).
    /// A group left with one tab goes (its site may be grouped again later:
    /// the user only took tabs out).
    func removeFromGroup(_ tab: Tab) {
        guard let group = tabGroup(of: tab) else { return }
        group.tabIDs.removeAll { $0 == tab.id }
        group.releasedTabIDs.append(tab.id)
        if tabs(of: group, in: tab.container).count < 2 {
            modelContext.delete(group)
        }
        modelContext.saveOrLog("remove tab from group")
    }

    /// Puts `tab` in `group` (dropped among its tabs), out of its own.
    func addToGroup(_ tab: Tab, _ group: TabGroup) {
        guard !group.tabIDs.contains(tab.id) else { return }
        if tabGroup(of: tab) != nil { removeFromGroup(tab) }
        group.releasedTabIDs.removeAll { $0 == tab.id }
        group.tabIDs.append(tab.id)
        modelContext.saveOrLog("add tab to group")
    }

    /// Closes the group's tabs, and the group.
    func closeTabGroup(_ group: TabGroup, in container: TabContainer?) {
        let tabs = container.map { tabs(of: group, in: $0) } ?? []
        modelContext.delete(group)
        closeTabs(tabs)
        modelContext.saveOrLog("close tab group")
    }

    /// A deleted space's groups go with it.
    func deleteTabGroups(ofSpace spaceID: UUID) {
        let descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.spaceID == spaceID })
        for group in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(group)
        }
    }
}
