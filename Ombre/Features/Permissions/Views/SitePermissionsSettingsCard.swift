import SwiftUI

/// Settings card listing the sites with saved permissions in one space, one
/// line each: the site, its six permissions as small icons, Edit (or a click
/// on the line) for their menus, and the trash to forget it.
struct SitePermissionsSettingsCard: View {
    let container: TabContainer
    @ObservedObject private var store = SitePermissionStore.shared
    @State private var search = ""
    /// The site whose menus are open.
    @State private var editing: SiteOrigin?
    @State private var isConfirmingForgetAll = false

    /// From this many sites, a search field shows above them.
    static let searchThreshold = 6

    private var entries: [(origin: SiteOrigin, permissions: SitePermissions)] {
        (store.permissionsBySpace[container.id] ?? [:])
            .map { (origin: $0.key, permissions: $0.value) }
            .sorted { lhs, rhs in
                lhs.origin.host == rhs.origin.host
                    ? lhs.origin.description < rhs.origin.description
                    : lhs.origin.host < rhs.origin.host
            }
    }

    private var shownEntries: [(origin: SiteOrigin, permissions: SitePermissions)] {
        let query = search.trimmingCharacters(in: .whitespaces)
        // The field gone (few sites left), its search goes too.
        guard !query.isEmpty, entries.count > Self.searchThreshold else { return entries }
        return entries.filter { $0.origin.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        SettingsCard(
            header: String(localized: "Site Permissions"),
            description: String(
                // swiftlint:disable:next line_length
                localized: "Sites that asked for a permission in \(container.name). Changes apply to the next request; reload a page to stop a camera already in use."
            )
        ) {
            if entries.isEmpty {
                Text("No site has asked for permissions in this space yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                toolbar
                let shown = shownEntries
                if shown.isEmpty {
                    Text("No site matches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(shown.enumerated()), id: \.element.origin) { index, entry in
                    if index > 0 { Divider() }
                    row(for: entry.origin, permissions: entry.permissions)
                }
            }
        }
        .confirmationDialog(
            "Forget all sites in \(container.name)?",
            isPresented: $isConfirmingForgetAll
        ) {
            Button("Forget All", role: .destructive) { store.removeAll(in: container.id) }
        } message: {
            Text("Each site asks again the next time it needs a permission.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if entries.count > Self.searchThreshold {
                TextField("", text: $search, prompt: Text("Search Sites"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            Spacer()
            Button("Forget All…") { isConfirmingForgetAll = true }
        }
    }

    private func row(for origin: SiteOrigin, permissions: SitePermissions) -> some View {
        HStack(spacing: 10) {
            Text(origin.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                ForEach(SitePermissionType.allCases) { type in
                    SitePermissionIcon(type: type, state: SitePermissionBadge.state(of: type, in: permissions))
                }
            }
            Button("Edit…") { editing = origin }
                .controlSize(.small)
                .popover(isPresented: Binding(
                    get: { editing == origin },
                    set: { if !$0, editing == origin { editing = nil } }
                ), arrowEdge: .trailing) {
                    SitePermissionsEditor(origin: origin, spaceID: container.id)
                }
            Button {
                store.removePermissions(for: origin, in: container.id, isPrivate: false)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Forget this site")
            .accessibilityLabel(String(localized: "Forget this site"))
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = origin }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(origin.displayName))
        .accessibilityValue(Text(SitePermissionBadge.summary(of: permissions)))
    }
}

/// How a permission shows on a site's line: its symbol, struck through when
/// refused, and its color (green: allowed, red: refused, gray: ask, faint:
/// the general choice).
enum SitePermissionBadge {
    enum Tone: Equatable {
        case allowed
        case refused
        case asks
        /// No choice of its own (downloads): the general one applies.
        case general
    }

    /// The site's state; nil for downloads without a choice of their own.
    static func state(of type: SitePermissionType, in permissions: SitePermissions) -> SitePermissionState? {
        type == .downloads ? permissions.downloadsChoice : permissions[type]
    }

    static func tone(_ state: SitePermissionState?) -> Tone {
        switch state {
        case .allow: return .allowed
        case .deny: return .refused
        case .ask: return .asks
        case nil: return .general
        }
    }

    static func symbol(_ type: SitePermissionType, refused: Bool) -> String {
        switch type {
        case .camera: return refused ? "video.slash.fill" : "video.fill"
        case .microphone: return refused ? "mic.slash.fill" : "mic.fill"
        case .notifications: return refused ? "bell.slash.fill" : "bell.fill"
        case .location: return refused ? "location.slash.fill" : "location.fill"
        case .screen: return refused ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle"
        case .downloads: return refused ? "xmark.circle.fill" : "arrow.down.circle.fill"
        }
    }

    /// « Camera: Allow », « Downloads: Default ».
    static func help(_ type: SitePermissionType, _ state: SitePermissionState?) -> String {
        String(localized: "\(type.title): \(state?.title ?? String(localized: "Default"))")
    }

    /// All six, for VoiceOver.
    static func summary(of permissions: SitePermissions) -> String {
        SitePermissionType.allCases
            .map { help($0, state(of: $0, in: permissions)) }
            .joined(separator: ", ")
    }
}

private struct SitePermissionIcon: View {
    let type: SitePermissionType
    let state: SitePermissionState?

    private var color: Color {
        switch SitePermissionBadge.tone(state) {
        case .allowed: return .green
        case .refused: return .red
        case .asks: return .secondary
        case .general: return Color.secondary.opacity(0.45)
        }
    }

    var body: some View {
        Image(systemName: SitePermissionBadge.symbol(type, refused: state == .deny))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .help(SitePermissionBadge.help(type, state))
            .accessibilityHidden(true)
    }
}

/// A site's six menus, in a popover from its line.
private struct SitePermissionsEditor: View {
    let origin: SiteOrigin
    let spaceID: UUID
    @ObservedObject private var store = SitePermissionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(origin.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(SitePermissionType.allCases.filter { $0 != .downloads }) { type in
                    GridRow {
                        Label(type.title, systemImage: SitePermissionBadge.symbol(type, refused: false))
                        Picker(type.title, selection: binding(for: type)) {
                            ForEach(SitePermissionState.allCases, id: \.self) { state in
                                Text(state.title).tag(state)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                GridRow {
                    Label(
                        SitePermissionType.downloads.title,
                        systemImage: SitePermissionBadge.symbol(.downloads, refused: false)
                    )
                    // No choice of its own: the general one of Settings › General.
                    Picker(SitePermissionType.downloads.title, selection: downloadsBinding) {
                        Text("Default").tag(SitePermissionState?.none)
                        ForEach(SitePermissionState.allCases, id: \.self) { state in
                            Text(state.title).tag(SitePermissionState?.some(state))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .padding(16)
    }

    private var downloadsBinding: Binding<SitePermissionState?> {
        Binding(
            get: { store.permissions(for: origin, in: spaceID, isPrivate: false).downloadsChoice },
            set: { choice in
                var permissions = store.permissions(for: origin, in: spaceID, isPrivate: false)
                permissions.downloadsChoice = choice
                store.setPermissions(permissions, for: origin, in: spaceID, isPrivate: false)
            }
        )
    }

    private func binding(for type: SitePermissionType) -> Binding<SitePermissionState> {
        Binding(
            get: { store.permissions(for: origin, in: spaceID, isPrivate: false)[type] },
            set: { store.setState($0, for: [type], origin: origin, in: spaceID, isPrivate: false) }
        )
    }
}
