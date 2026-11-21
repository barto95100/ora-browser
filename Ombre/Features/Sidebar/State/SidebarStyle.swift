import SwiftUI

/// The sidebar's look: as before, or Liquid Glass (macOS 26). The Debug
/// menu switches between them live, until one is chosen.
enum SidebarStyle: String, CaseIterable, Identifiable {
    case classic
    case glass

    static let defaultsKey = "debug.sidebarStyle"
    static let defaultValue = SidebarStyle.glass

    var id: String {
        rawValue
    }

    /// Its name in the Debug menu (outside `#if DEBUG`, so that the
    /// localization check, which reads the Release build, sees it).
    var title: String {
        switch self {
        case .classic: String(localized: "Before")
        case .glass: String(localized: "After (Liquid Glass)")
        }
    }

    static var debugMenuTitle: String {
        String(localized: "Sidebar Style")
    }

    /// Glass only exists from macOS 26.
    var usesGlass: Bool {
        guard self == .glass else { return false }
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension EnvironmentValues {
    /// The sidebar is drawn in Liquid Glass (see `SidebarStyle`).
    @Entry var usesSidebarGlass = false
    /// The fixed sidebar's glass panel is 6 pt in from the window: its
    /// header moves up as much, to stay level with the address bar.
    @Entry var isInSidebarGlassPanel = false
}

/// The colors of the glass sidebar, as `#RRGGBB` so that tests can check
/// their contrast (WCAG).
enum SidebarGlassPalette {
    /// The active tab's pill: a tint, and how much of it.
    struct Pill: Equatable {
        let tintHex: String
        let opacity: Double
    }

    /// The space's color or its theme's accent, faint; without either, a
    /// white pill (light, like Arc) or a light gray one (dark). In dark mode
    /// the tint is as strong as white text allows (AA, where the glass is
    /// brightest): a light color like yellow gets less.
    static func pill(isDark: Bool, spaceHex: String?, theme: SpaceTheme?) -> Pill {
        guard let tintHex = spaceHex ?? theme?.accentHex else {
            return Pill(tintHex: "#FFFFFF", opacity: isDark ? 0.14 : 0.7)
        }
        guard isDark else { return Pill(tintHex: tintHex, opacity: 0.32) }
        let backdrop = backdrop(isDark: true, spaceHex: spaceHex, theme: theme)
        let white = BackdropRGB(hex: "#FFFFFF")
        var opacity = maximumDarkOpacity
        while opacity > minimumDarkOpacity {
            let candidate = Pill(tintHex: tintHex, opacity: opacity)
            if white.contrast(with: pillColor(candidate, on: backdrop, lightened: true)) >= 4.6 { break }
            opacity -= 0.02
        }
        return Pill(tintHex: tintHex, opacity: opacity)
    }

    static let maximumDarkOpacity = 0.26
    static let minimumDarkOpacity = 0.1

    /// About what is under the pill: the top of the window's background (the
    /// space's color, see `Theme.windowBackground`) on macOS's window. The
    /// glass of the panel lightens it a little more.
    static func backdrop(isDark: Bool, spaceHex: String?, theme: SpaceTheme?) -> BackdropRGB {
        if let theme { return BackdropRGB(hex: theme.backgroundHex) }
        let window = BackdropRGB(hex: isDark ? "#1E1E1E" : "#ECECEC")
        guard let spaceHex else {
            return window.mixed(with: BackdropRGB(hex: isDark ? "#141414" : "#F3E5D6"), by: 0.3)
        }
        let base = BackdropRGB(hex: isDark ? "#000000" : "#FFFFFF")
        let top = BackdropRGB(hex: spaceHex).mixed(with: base, by: isDark ? 0.45 : 0.4)
        return window.mixed(with: top, by: 0.7)
    }

    /// What the panel's glass and the pill's highlight add at most: white.
    static let glassLightening = 0.1

    /// The pill as it shows over `backdrop`; `lightened`: where the panel's
    /// glass and the pill's highlight (`GlassPill`) are brightest.
    static func pillColor(_ pill: Pill, on backdrop: BackdropRGB, lightened: Bool = false) -> BackdropRGB {
        let color = backdrop.mixed(with: BackdropRGB(hex: pill.tintHex), by: pill.opacity)
        return lightened ? color.mixed(with: BackdropRGB(hex: "#FFFFFF"), by: glassLightening) : color
    }

    /// The neutral pill (no space color) in light mode: white on a light
    /// panel, it needs a shadow to show.
    static func needsShadow(isDark: Bool, spaceHex: String?, theme: SpaceTheme?) -> Bool {
        !isDark && spaceHex == nil && theme == nil
    }
}

extension Theme {
    /// The glass sidebar's active tab pill.
    var sidebarPill: SidebarGlassPalette.Pill {
        SidebarGlassPalette.pill(
            isDark: colorScheme == .dark || spaceTheme != nil,
            spaceHex: spaceColor?.hex,
            theme: spaceTheme
        )
    }

    var sidebarPillNeedsShadow: Bool {
        SidebarGlassPalette.needsShadow(
            isDark: colorScheme == .dark || spaceTheme != nil,
            spaceHex: spaceColor?.hex,
            theme: spaceTheme
        )
    }

    /// The tint of the floating sidebar's glass: the space's, faint.
    var sidebarGlassTint: Color? {
        if let spaceTheme { return spaceTheme.background.opacity(0.55) }
        return spaceColor?.color.opacity(0.18)
    }
}
