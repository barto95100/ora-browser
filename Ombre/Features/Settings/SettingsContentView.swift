import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case spaces
    case passwords
    case extensions
    case timeFocus
    case shortcuts
    case searchEngines

    var title: String {
        switch self {
        case .general: return "General"
        case .spaces: return "Spaces"
        case .passwords: return "Passwords"
        case .extensions: return "Extensions"
        case .timeFocus: return "Time & Focus"
        case .shortcuts: return "Shortcuts"
        case .searchEngines: return "Search"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .spaces: return "rectangle.3.group"
        case .passwords: return "key.horizontal"
        case .extensions: return "puzzlepiece.extension"
        case .timeFocus: return "hourglass"
        case .shortcuts: return "command"
        case .searchEngines: return "magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Browser defaults, app behavior, and software updates."
        case .spaces:
            return "Space-specific defaults and per-space data controls."
        case .passwords:
            return "Password manager integration, vault access, and autofill behavior."
        case .extensions:
            return "Safari extensions from your apps, and what they can access."
        case .timeFocus:
            return "Browsing time per site, and focus sessions."
        case .shortcuts:
            return "Keyboard shortcuts and command mappings."
        case .searchEngines:
            return "Default search providers, AI engines, and custom shortcuts."
        }
    }
}

struct SettingsWindowRoot: View {
    var body: some View {
        SettingsContentView()
            .environmentObject(ToastManager.shared)
    }
}

struct SettingsContentView: View {
    static let selectedTabDefaultsKey = "settings.selectedTab"

    @AppStorage(Self.selectedTabDefaultsKey) private var selectionRawValue: String = SettingsTab.general.rawValue

    private var selection: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectionRawValue) ?? .general },
            set: { selectionRawValue = $0.rawValue }
        )
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectionRawValue) ?? .general
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: selection) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(200)
            .padding(.top, 8)
        } detail: {
            SettingsDetailView(tab: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selectedTab.title)
                .navigationSubtitle(selectedTab.subtitle)
        }
    }
}

/// The page of a settings section, in the settings window or in the browser
/// window (`InWindowSettingsView`).
struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        switch tab {
        case .general:
            GeneralSettingsView()
        case .spaces:
            SpacesSettingsView()
        case .passwords:
            PasswordsSettingsView()
        case .extensions:
            ExtensionsSettingsView()
        case .timeFocus:
            TimeFocusSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .searchEngines:
            SearchEngineSettingsView()
        }
    }
}
