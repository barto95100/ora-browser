import SwiftUI

/// The settings in the browser window, in place of the page: chosen from the
/// sidebar's ⚙︎ or ⌘,; closed by ✕, ⌘, again, or picking a tab.
struct InWindowSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @AppStorage(SettingsContentView.selectedTabDefaultsKey) private var selectionRawValue = SettingsTab.general.rawValue

    private var selected: SettingsTab {
        SettingsTab(rawValue: selectionRawValue) ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            sections
                .frame(width: 210)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.5)
                SettingsDetailView(tab: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(theme.background)
        .environmentObject(AppearanceManager.shared)
        .environmentObject(UpdateService.shared)
        .environmentObject(DefaultBrowserManager.shared)
        .environmentObject(ToastManager.shared)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 10)
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectionRawValue = tab.rawValue
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(tab == selected ? theme.foreground : theme.foreground.opacity(0.75))
                        .background(
                            tab == selected ? theme.accent.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(selected.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedForeground)
            }
            Spacer()
            Button {
                appState.showSettings = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(theme.foreground.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close Settings (⌘,)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
