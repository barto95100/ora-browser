import SwiftData
import SwiftUI

/// Settings › Time & Focus: the browsing time, focus, and the sites each
/// space blocks during focus.
struct TimeFocusSettingsView: View {
    @ObservedObject private var settings = TimeTrackingSettings.shared
    @ObservedObject private var focus = FocusSettings.shared
    @Query(sort: \TabContainer.createdAt) private var spaces: [TabContainer]
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

            SettingsCard(
                header: "Focus",
                description: "Start focus from the browsing time (⌛ in the sidebar or ⌥⌘Y). "
                    + "During focus, the sites blocked in a space are covered; breaks open them again."
            ) {
                minutesPicker("Focus duration:", selection: $focus.focusMinutes, choices: FocusSettings.durationChoices)
                Toggle("Repeat focus with breaks", isOn: $focus.repeats)
                if focus.repeats {
                    minutesPicker("Break:", selection: $focus.breakMinutes, choices: [3, 5, 10, 15])
                    minutesPicker("Long break:", selection: $focus.longBreakMinutes, choices: [10, 15, 20, 30])
                    HStack {
                        Text("Long break after:")
                        Spacer()
                        Picker("", selection: $focus.cyclesBeforeLongBreak) {
                            ForEach([2, 3, 4, 5, 6], id: \.self) { Text("\($0) cycles").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
                HStack {
                    Text("Daily focus goal:")
                    Spacer()
                    Picker("", selection: $focus.dailyGoalMinutes) {
                        ForEach(FocusSettings.goalChoices, id: \.self) { minutes in
                            Text(Self.goalLabel(minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            ForEach(spaces) { space in
                SettingsCard(header: "Blocked During Focus · \(space.name)") {
                    FocusBlockedSitesView(spaceID: space.id)
                }
            }
        }
        .confirmationDialog("Clear all browsing time?", isPresented: $isConfirmingClear) {
            Button("Clear Browsing Time", role: .destructive) { BrowsingTimeStore.shared.deleteAll() }
        } message: {
            Text("The time counted on every site, in every space, is removed.")
        }
    }

    private static func goalLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "None" }
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }

    private func minutesPicker(_ title: String, selection: Binding<Int>, choices: [Int]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(choices, id: \.self) { Text("\($0) min").tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }
}
