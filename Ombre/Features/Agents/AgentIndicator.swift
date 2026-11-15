import SwiftUI

/// In the address bar for 30 s after an agent's last command: which app
/// drives Ombre, and Stop Agent Control.
struct AgentIndicator: View {
    @ObservedObject private var control = AgentControl.shared
    let foregroundColor: Color

    var body: some View {
        if let app = control.drivingApp {
            Menu {
                Text("Controlled by \(app)")
                Button("Stop Agent Control") { control.stop() }
            } label: {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
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
