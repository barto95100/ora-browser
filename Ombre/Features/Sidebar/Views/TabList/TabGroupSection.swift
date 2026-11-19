import SwiftUI

/// A group of tabs in the sidebar: its row (the site's icon, its name and
/// number of tabs; a click folds or unfolds it), then its tabs, indented.
/// Folded, only its tab shown in the window stays, like a folder.
struct TabGroupSection<Row: View>: View {
    let group: TabGroup
    let tabs: [Tab]
    @ViewBuilder let row: (Tab) -> Row
    @EnvironmentObject var tabManager: TabManager

    private var shownTabs: [Tab] {
        group.isCollapsed ? tabs.filter { tabManager.isShown($0) } : tabs
    }

    var body: some View {
        VStack(spacing: 8) {
            TabGroupRow(group: group, tabs: tabs)
                .activeTabMarkerRow([group.id])
            if !shownTabs.isEmpty {
                VStack(spacing: 8) {
                    ForEach(shownTabs) { tab in
                        row(tab)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

/// A group's own row.
struct TabGroupRow: View {
    let group: TabGroup
    let tabs: [Tab]
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool {
        tabManager.renamingGroupID == group.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(theme.mutedForeground)
                .frame(width: 10)
            LocalFavIcon(
                faviconLocalFile: tabs.first?.faviconLocalFile,
                textColor: theme.foreground,
                isGrayscale: false
            )
            if isRenaming {
                TextField("Group Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isNameFocused)
                    .onSubmit(endRenaming)
                    .onExitCommand { tabManager.renamingGroupID = nil }
                    .onAppear {
                        name = group.name
                        DispatchQueue.main.async { isNameFocused = true }
                    }
                    .onChange(of: isNameFocused) { _, isFocused in
                        if !isFocused { endRenaming() }
                    }
            } else {
                Text(group.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.foreground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(tabs.count)")
                .font(.system(size: 11))
                .foregroundColor(theme.mutedForeground)
        }
        .padding(8)
        .background(
            isHovering ? theme.activeTabBackground.opacity(colorScheme == .dark ? 0.3 : 0.1) : .clear,
            in: .rect(cornerRadius: 10)
        )
        .contentShape(ConditionallyConcentricRectangle(cornerRadius: 10))
        .onTapGesture {
            guard !isRenaming else { return }
            withAnimation(.easeOut(duration: 0.18)) { tabManager.toggleTabGroup(group) }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(Text(group.name))
        .accessibilityValue(Text(TabGroupAccessibility.value(count: tabs.count, isCollapsed: group.isCollapsed)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tabManager.toggleTabGroup(group) }
        .accessibilityAction(named: Text("Rename Group")) { tabManager.renamingGroupID = group.id }
        .accessibilityAction(named: Text("Ungroup")) { tabManager.ungroup(group) }
        .accessibilityAction(named: Text("Close Group")) { tabManager.closeTabGroup(group, in: group.space(in: tabs)) }
        .contextMenu {
            Button {
                tabManager.renamingGroupID = group.id
            } label: {
                Label("Rename Group", systemImage: "pencil")
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tabManager.ungroup(group) }
            } label: {
                Label("Ungroup", systemImage: "rectangle.stack.badge.minus")
            }
            Divider()
            Button(role: .destructive) {
                tabManager.closeTabGroup(group, in: group.space(in: tabs))
            } label: {
                Label("Close \(tabs.count) Tabs", systemImage: "xmark")
            }
        }
    }

    private func endRenaming() {
        guard isRenaming else { return }
        tabManager.renamingGroupID = nil
        tabManager.renameTabGroup(group, to: name)
    }
}

private extension TabGroup {
    /// Its space, through its tabs (which are all in it).
    func space(in tabs: [Tab]) -> TabContainer? {
        tabs.first?.container
    }
}

/// What VoiceOver says of a group.
enum TabGroupAccessibility {
    static func value(count: Int, isCollapsed: Bool) -> String {
        let state = isCollapsed ? String(localized: "Collapsed") : String(localized: "Expanded")
        return "\(String(localized: "\(count) tabs")), \(state)"
    }
}

extension EnvironmentValues {
    /// Whether the tab row is in a group (its menu offers Remove from Group).
    @Entry var isInTabGroup = false
}
