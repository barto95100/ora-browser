import SwiftUI

/// Settings card listing the sites with saved permissions in one space, so the
/// user can review, change or forget them.
struct SitePermissionsSettingsCard: View {
    let container: TabContainer
    @ObservedObject private var store = SitePermissionStore.shared

    private var entries: [(origin: SiteOrigin, permissions: SitePermissions)] {
        (store.permissionsBySpace[container.id] ?? [:])
            .map { (origin: $0.key, permissions: $0.value) }
            .sorted { lhs, rhs in
                lhs.origin.host == rhs.origin.host
                    ? lhs.origin.description < rhs.origin.description
                    : lhs.origin.host < rhs.origin.host
            }
    }

    var body: some View {
        SettingsCard(
            header: "Site Permissions",
            description: "Sites that asked to use your camera or microphone in \(container.name). "
                + "Changes apply to the next request; reload a page to stop a camera already in use."
        ) {
            if entries.isEmpty {
                Text("No site has asked for permissions in this space yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.origin) { index, entry in
                    if index > 0 {
                        Divider()
                    }
                    row(for: entry.origin)
                }
            }
        }
    }

    private func row(for origin: SiteOrigin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(origin.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    store.removePermissions(for: origin, in: container.id, isPrivate: false)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Forget this site")
            }

            ForEach(SitePermissionType.allCases) { type in
                Picker(type.title, selection: binding(for: type, origin: origin)) {
                    ForEach(SitePermissionState.allCases, id: \.self) { state in
                        Text(state.title).tag(state)
                    }
                }
            }
        }
    }

    private func binding(for type: SitePermissionType, origin: SiteOrigin) -> Binding<SitePermissionState> {
        Binding(
            get: { store.permissions(for: origin, in: container.id, isPrivate: false)[type] },
            set: { store.setState($0, for: [type], origin: origin, in: container.id, isPrivate: false) }
        )
    }
}
