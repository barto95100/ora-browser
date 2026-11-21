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

extension EnvironmentValues {
    /// Liquid Glass is drawn (see `GlassEffects`). Set by each window's root.
    @Entry var usesGlassEffects = false
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
        content.environment(
            \.usesGlassEffects,
            GlassEffects.isActive(isEnabled: settings.glassEffectsEnabled, reducesTransparency: reducesTransparency)
        )
    }
}
