import AppKit
import SwiftUI

/// Whether Ombre draws Liquid Glass: Settings › General › Appearance ›
/// Glass Effects, on by default. Only on macOS 26, and never while macOS's
/// Reduce Transparency is on (Accessibility): then everything looks as
/// before the glass.
enum GlassEffects {
    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    static func isActive(isEnabled: Bool, reducesTransparency: Bool, isSupported: Bool = isSupported) -> Bool {
        isSupported && isEnabled && !reducesTransparency
    }

    /// For what lives outside the windows' views (the quit hint's panel).
    @MainActor
    static var isActiveNow: Bool {
        isActive(
            isEnabled: SettingsStore.shared.glassEffectsEnabled,
            reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    /// The setting's explanation, or why it can't be used.
    static func detail(reducesTransparency: Bool, isSupported: Bool = isSupported) -> String {
        if !isSupported {
            return String(localized: "Needs macOS 26 or later.")
        }
        if reducesTransparency {
            return String(
                localized: "Off while Reduce Transparency is on in System Settings › Accessibility › Display."
            )
        }
        return String(localized: "The sidebar and the settings in Liquid Glass. Off, Ombre looks as before.")
    }
}

/// How much of the desktop shows through the glass (Settings › General ›
/// Appearance › Transparency): light keeps a thicker scrim, safer to read;
/// strong lets the wallpaper show the most.
enum GlassTransparency: String, CaseIterable, Identifiable {
    case light
    case medium
    case strong

    static let defaultValue = GlassTransparency.medium

    /// The setting's name and explanation.
    static var settingTitle: String {
        String(localized: "Transparency")
    }

    static var settingDetail: String {
        String(localized: "How much of the wallpaper shows through the sidebar. Light is easier to read.")
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .light: String(localized: "glass.transparency.light", defaultValue: "Light")
        case .medium: String(localized: "glass.transparency.medium", defaultValue: "Medium")
        case .strong: String(localized: "glass.transparency.strong", defaultValue: "Strong")
        }
    }

    /// How much of the scheme's base covers the desktop under the sidebar.
    func scrim(isDark: Bool) -> Double {
        switch self {
        case .light: isDark ? 0.6 : 0.4
        case .medium: isDark ? 0.38 : 0.26
        case .strong: isDark ? 0.28 : 0.18
        }
    }
}

extension EnvironmentValues {
    /// Liquid Glass is drawn (see `GlassEffects`). Set by each window's root.
    @Entry var usesGlassEffects = false
    @Entry var glassTransparency = GlassTransparency.defaultValue
}

extension View {
    /// Gives the window's views `usesGlassEffects`, following the setting
    /// and Reduce Transparency live.
    func glassEffectsEnvironment() -> some View {
        modifier(GlassEffectsEnvironment())
    }
}

private struct GlassEffectsEnvironment: ViewModifier {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    func body(content: Content) -> some View {
        content
            .environment(
                \.usesGlassEffects,
                GlassEffects.isActive(isEnabled: settings.glassEffectsEnabled, reducesTransparency: reducesTransparency)
            )
            .environment(\.glassTransparency, settings.glassTransparency)
    }
}
