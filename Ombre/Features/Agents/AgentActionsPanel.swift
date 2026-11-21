import AppKit
import SwiftUI

/// "Show Actions…" of the agent indicator: the session's commands
/// (`AgentControl.actions`), a click on one shows its tab, and Stop Agent
/// Control. One panel for every window; nothing of a browser window in it.
@MainActor
enum AgentActionsPanel {
    private static var panel: NSPanel?

    static func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 380),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = String(localized: "Agent Actions")
        panel.isReleasedWhenClosed = false
        // An inspector of Ombre's: not over other apps.
        panel.hidesOnDeactivate = true
        panel.setFrameAutosaveName("OmbreAgentActions") // not shown
        panel.contentView = NSHostingView(rootView: AgentActionsView())
        if panel.frame.origin == .zero { panel.center() }
        return panel
    }

    /// Shows the tab of an action: in the normal window in front (where
    /// agents work; the windows share their tabs), else another normal one.
    static func reveal(_ tabID: UUID) {
        let others = BrowserWindows.tabManagers.keyEnumerator().allObjects as? [NSWindow] ?? []
        let windows = (BrowserWindows.front.map { [$0] } ?? []) + others.filter { $0 !== BrowserWindows.front }
        for window in windows {
            guard let tabManager = BrowserWindows.tabManagers.object(forKey: window),
                  tabManager.fetchContainers().contains(where: { $0.tabs.contains { $0.id == tabID } })
            else { continue }
            tabManager.activateTab(id: tabID)
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

private struct AgentActionsView: View {
    @ObservedObject private var control = AgentControl.shared
    @State private var selection: AgentActionRecord.ID?

    /// Newest first.
    private var actions: [AgentActionRecord] {
        control.actions.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if actions.isEmpty {
                Text("No actions in this session.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .frame(minWidth: 560, minHeight: 240)
    }

    private var header: some View {
        HStack {
            if let app = control.drivingApp {
                Label(String(localized: "Controlled by \(app)"), systemImage: AgentTabBadge.symbolName)
            } else {
                Text("No agent controls Ombre.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop Agent Control") { control.stop() }
                .disabled(control.drivingApp == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var table: some View {
        Table(actions, selection: $selection) {
            TableColumn(String(localized: "agent.actions.time", defaultValue: "Time")) { action in
                Text(action.date, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
            }
            .width(min: 64, ideal: 72, max: 90)
            TableColumn(String(localized: "agent.actions.app", defaultValue: "App")) { action in
                Text(action.app)
            }
            .width(min: 60, ideal: 90)
            TableColumn(String(localized: "agent.actions.command", defaultValue: "Command")) { action in
                Text(action.command)
            }
            .width(min: 70, ideal: 90)
            TableColumn(String(localized: "agent.actions.site", defaultValue: "Site")) { action in
                Text(action.host ?? "—")
            }
            .width(min: 80, ideal: 130)
            TableColumn(String(localized: "agent.actions.tab", defaultValue: "Tab")) { action in
                Text(action.tabTitle ?? "—")
                    .help(action.tabTitle ?? "")
            }
            TableColumn(String(localized: "agent.actions.result", defaultValue: "Result")) { action in
                AgentActionResult(action: action)
            }
            .width(min: 80, ideal: 160)
        }
        .onChange(of: selection) { _, id in
            guard let id else { return }
            if let tabID = actions.first(where: { $0.id == id })?.tabID { AgentActionsPanel.reveal(tabID) }
            // A click on the same row again shows its tab again.
            selection = nil
        }
    }
}

/// Done, or failed with why (as the agent was told, in English).
private struct AgentActionResult: View {
    let action: AgentActionRecord

    var body: some View {
        if action.succeeded {
            Label(String(localized: "agent.actions.done", defaultValue: "Done"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        } else {
            Label(
                action.failure ?? String(localized: "agent.actions.failed", defaultValue: "Failed"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .help(action.failure ?? "")
        }
    }
}
