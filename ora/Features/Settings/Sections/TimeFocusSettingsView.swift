import SwiftUI

/// Settings › Time & Focus: the browsing time.
struct TimeFocusSettingsView: View {
    @ObservedObject private var settings = TimeTrackingSettings.shared
    @State private var isConfirmingClear = false

    var body: some View {
        SettingsSection {
            SettingsCard(
                header: "Browsing Time",
                description: "Time on each site, counted while its tab is in front and you are using the Mac "
                    + "(or it plays media). Private windows are never counted. Stays on this Mac."
            ) {
                Toggle("Count browsing time", isOn: $settings.isEnabled)
                HStack {
                    Text("Keep browsing time for:")
                    Spacer()
                    Picker("", selection: $settings.retentionDays) {
                        ForEach(TimeTrackingSettings.retentionChoices, id: \.self) { days in
                            Text(days == 365 ? "1 year" : "\(days) days").tag(days)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                HStack {
                    Text("See it with View › Show Browsing Time (⌥⌘Y).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear Browsing Time…", role: .destructive) { isConfirmingClear = true }
                }
            }
        }
        .confirmationDialog("Clear all browsing time?", isPresented: $isConfirmingClear) {
            Button("Clear Browsing Time", role: .destructive) { BrowsingTimeStore.shared.deleteAll() }
        } message: {
            Text("The time counted on every site, in every space, is removed.")
        }
    }
}
