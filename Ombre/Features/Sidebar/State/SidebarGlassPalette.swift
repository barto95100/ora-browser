import SwiftUI

extension EnvironmentValues {
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
        while opacity > minimumDarkOpacity + 0.001 {
            let candidate = Pill(tintHex: tintHex, opacity: opacity)
            if white.contrast(with: pillColor(candidate, on: backdrop, lightened: true)) >= 4.6 { break }
            opacity -= 0.02
        }
        return Pill(tintHex: tintHex, opacity: opacity)
    }

    static let maximumDarkOpacity = 0.26
    /// The faintest tint: the pill's highlight and edge still show it.
    static let minimumDarkOpacity = 0.08

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

    /// The reflection at the top of the pill (`GlassPill`).
    static let pillHighlight = 0.28

    /// What the panel's glass and the pill's highlight add at most where
    /// the title's letters are (a third down the pill), plus the end of the
    /// panel's reflection (`GlassRim.reflection`, which stops above the
    /// tabs): white.
    static let glassLightening = 0.15

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
