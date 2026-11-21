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
    /// white pill (light, like Arc) or a light gray one (dark). The tint is
    /// as strong as the title allows (AA, where the glass is brightest): a
    /// light color like yellow gets less in dark mode. `translucent`: over
    /// the desktop (`SidebarBackground.translucentWindow`), whatever it shows.
    static func pill(isDark: Bool, spaceHex: String?, theme: SpaceTheme?, translucent: Bool = false) -> Pill {
        let tintHex = spaceHex ?? theme?.accentHex
        let strongest = switch (tintHex == nil, isDark) {
        case (true, true): 0.14
        case (true, false): 0.7
        case (false, true): maximumDarkOpacity
        case (false, false): 0.32
        }
        let under = translucent
            ? translucentBackdrop(
                wallpaper: worstWallpaper(isDark: isDark),
                isDark: isDark,
                spaceHex: spaceHex,
                theme: theme
            )
            : backdrop(isDark: isDark, spaceHex: spaceHex, theme: theme)
        let text = BackdropRGB(hex: isDark ? "#FFFFFF" : "#000000")
        var opacity = strongest
        while opacity > minimumDarkOpacity + 0.001 {
            let candidate = Pill(tintHex: tintHex ?? "#FFFFFF", opacity: opacity)
            if text.contrast(with: pillColor(candidate, on: under, lightened: isDark)) >= 4.6 { break }
            opacity -= 0.02
        }
        return Pill(tintHex: tintHex ?? "#FFFFFF", opacity: opacity)
    }

    static let maximumDarkOpacity = 0.26
    /// The faintest tint: the pill's highlight and edge still show it.
    static let minimumDarkOpacity = 0.08

    // MARK: - Over the desktop

    /// How much of the scheme's base (or the theme's background) covers the
    /// desktop under the sidebar: enough for the titles on any wallpaper,
    /// even pure white (dark mode) or pure black (light mode).
    static func translucentScrim(isDark: Bool) -> Double {
        isDark ? 0.8 : 0.5
    }

    /// The space's color over it, faint: still recognizable.
    static let translucentSpaceTint = 0.2

    /// The wallpaper that leaves the least contrast to the titles.
    static func worstWallpaper(isDark: Bool) -> BackdropRGB {
        BackdropRGB(hex: isDark ? "#FFFFFF" : "#000000")
    }

    /// What shows under the sidebar over `wallpaper`: the scrim, then the
    /// space's color (with a theme, its background is the scrim and the
    /// color only tints the pill, as without the translucent window). The
    /// system's blur and material only soften it more.
    static func translucentBackdrop(
        wallpaper: BackdropRGB, isDark: Bool, spaceHex: String?, theme: SpaceTheme?
    ) -> BackdropRGB {
        let base = BackdropRGB(hex: theme?.backgroundHex ?? (isDark ? "#000000" : "#FFFFFF"))
        let scrimmed = wallpaper.mixed(with: base, by: translucentScrim(isDark: isDark))
        guard let spaceHex, theme == nil else { return scrimmed }
        return scrimmed.mixed(with: BackdropRGB(hex: spaceHex), by: translucentSpaceTint)
    }

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
    func sidebarPill(translucent: Bool) -> SidebarGlassPalette.Pill {
        SidebarGlassPalette.pill(
            isDark: colorScheme == .dark || spaceTheme != nil,
            spaceHex: spaceColor?.hex,
            theme: spaceTheme,
            translucent: translucent
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
