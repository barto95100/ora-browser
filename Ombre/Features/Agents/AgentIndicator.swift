import SwiftUI

/// While agents drive Ombre (a session allowed): which app, its actions
/// (`AgentActionsPanel`), and Stop Agent Control. At the top of the sidebar, in the address bar while the sidebar
/// is hidden.
struct AgentIndicator: View {
    @ObservedObject private var control = AgentControl.shared
    let foregroundColor: Color
    /// Pushed to the end of its row (the sidebar's header).
    var leadingSpace = false

    var body: some View {
        if let app = control.drivingApp {
            if leadingSpace { Spacer(minLength: 4) }
            Menu {
                Text("Controlled by \(app)")
                Button("Show Actions…") { AgentActionsPanel.show() }
                Button("Stop Agent Control") { control.stop() }
            } label: {
                Image(systemName: AgentTabBadge.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Controlled by \(app)"))
            .accessibilityLabel(Text("Controlled by \(app)"))
            .transition(.opacity)
        }
    }
}

/// On a tab of the sidebar an agent opened, showed, read or closed during
/// its session; gone when it ends. Never in a private window: only a normal
/// window's tabs are touched.
struct AgentTabBadge: View {
    static let symbolName = "point.3.filled.connected.trianglepath.dotted"

    @ObservedObject private var control = AgentControl.shared
    let tabID: UUID

    var body: some View {
        if control.touchedTabIDs.contains(tabID) {
            Image(systemName: Self.symbolName)
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 11, height: 11)
                .background(Circle().fill(Color.accentColor))
                // Clicks go to the tab (VoiceOver reads it in the tab's value).
                .allowsHitTesting(false)
        }
    }
}
