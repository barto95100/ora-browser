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
        case .general: return String(localized: "General")
        case .spaces: return String(localized: "Spaces")
        case .passwords: return String(localized: "Passwords")
        case .extensions: return String(localized: "Extensions")
        case .timeFocus: return String(localized: "Time & Focus")
        case .shortcuts: return String(localized: "Shortcuts")
        case .searchEngines: return String(localized: "Search")
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
            return String(localized: "Browser defaults, app behavior, and software updates.")
        case .spaces:
            return String(localized: "Space-specific defaults and per-space data controls.")
        case .passwords:
            return String(localized: "Password manager integration, vault access, and autofill behavior.")
        case .extensions:
            return String(localized: "Safari extensions from your apps, and what they can access.")
        case .timeFocus:
            return String(localized: "Browsing time per site, and focus sessions.")
        case .shortcuts:
            return String(localized: "Keyboard shortcuts and command mappings.")
        case .searchEngines:
            return String(localized: "Default search providers, AI engines, and custom shortcuts.")
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
