import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case spaces
    case searchEngines
    case passwords
    case extensions
    case timeFocus
    case shortcuts

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .spaces: return String(localized: "Spaces")
        case .passwords: return String(localized: "Passwords")
        case .extensions: return String(localized: "Extensions")
        case .timeFocus: return String(localized: "Time & Focus")
        case .shortcuts: return String(localized: "Shortcuts")
        case .searchEngines: return String(localized: "settings.search", defaultValue: "Search")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .spaces: return "rectangle.3.group.fill"
        case .passwords: return "key.fill"
        case .extensions: return "puzzlepiece.extension.fill"
        case .timeFocus: return "hourglass"
        case .shortcuts: return "command"
        case .searchEngines: return "magnifyingglass"
        }
    }

    /// The color of its icon, like the sections of System Settings.
    var color: Color {
        switch self {
        case .general: return .gray
        case .spaces: return .indigo
        case .passwords: return Color(hex: "#5E9C76")
        case .extensions: return .blue
        case .timeFocus: return .purple
        case .shortcuts: return Color(hex: "#6E6E73")
        case .searchEngines: return Color(hex: "#F16D34")
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

/// The settings window's content (see `SettingsWindow`). Only singletons and
/// the database: nothing of a browser window, which may all be closed.
struct SettingsWindowRoot: View {
    var body: some View {
        SettingsContentView()
            .environmentObject(ToastManager.shared)
            .modifier(ThemeProvider())
            .background(SettingsWindowAdopter())
            .frame(minWidth: SettingsWindow.minimumSize.width, minHeight: SettingsWindow.minimumSize.height)
    }
}

struct SettingsContentView: View {
    @AppStorage(SettingsWindow.selectionKey) private var selectionRawValue: String = SettingsTab.general.rawValue
    @Environment(\.theme) private var theme

    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { SettingsTab(rawValue: selectionRawValue) ?? .general },
            set: { if let tab = $0 { selectionRawValue = tab.rawValue } }
        )
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectionRawValue) ?? .general
    }

    /// The list of sections, then the page, side by side: not a split
    /// view, which could fold the list (and keep it folded, with no way back).
    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases, id: \.self, selection: selection) { tab in
                SettingsSidebarRow(tab: tab)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: SettingsWindow.sidebarWidth)
            Divider()
            SettingsDetailView(tab: selectedTab)
                .frame(
                    minWidth: SettingsWindow.minimumDetailWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .background(Color(nsColor: .windowBackgroundColor))
                // A section shows from its top, not where the last one was.
                .id(selectedTab)
        }
        .navigationTitle(selectedTab.title)
        .navigationSubtitle(selectedTab.subtitle)
        .tint(theme.accent)
    }
}

/// A section in the sidebar: its colored icon, then its name.
private struct SettingsSidebarRow: View {
    let tab: SettingsTab

    var body: some View {
        Label {
            Text(tab.title)
                .font(.system(size: 13))
        } icon: {
            SettingsIconTile(symbol: tab.symbol, color: tab.color)
        }
        .padding(.vertical, 2)
    }
}

/// A white symbol on a colored rounded square, like System Settings.
struct SettingsIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(color.gradient)
            )
            .accessibilityHidden(true)
    }
}

/// The page of a settings section.
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
