import SwiftUI
@testable import Ombre
import Testing

/// The glass sidebar keeps the spaces' colors and themes, and the active
/// tab's title legible on its pill (WCAG).
struct SidebarGlassPaletteTests {
    private struct Case: CustomStringConvertible {
        let isDark: Bool
        let spaceHex: String?
        let theme: SpaceTheme?

        var description: String {
            "\(isDark ? "dark" : "light") \(spaceHex ?? "-") \(theme?.rawValue ?? "-")"
        }

        var pill: SidebarGlassPalette.Pill {
            SidebarGlassPalette.pill(isDark: isDark, spaceHex: spaceHex, theme: theme)
        }

        var backdrop: BackdropRGB {
            SidebarGlassPalette.backdrop(isDark: isDark, spaceHex: spaceHex, theme: theme)
        }

        /// macOS's text: white in dark mode (a theme is always dark), black
        /// in light mode.
        var text: BackdropRGB {
            BackdropRGB(hex: isDark ? "#FFFFFF" : "#000000")
        }
    }

    private static var cases: [Case] {
        let spaces: [String?] = [nil] + SpaceColor.allCases.map(\.hex)
        let colored = [true, false].flatMap { isDark in
            spaces.map { Case(isDark: isDark, spaceHex: $0, theme: nil) }
        }
        let themed = SpaceTheme.allCases.flatMap { theme in
            spaces.map { Case(isDark: true, spaceHex: $0, theme: theme) }
        }
        return colored + themed
    }

    @Test("the active tab's title is legible on its pill, for every space (AA)")
    func titleIsLegibleOnThePill() {
        for item in Self.cases {
            // Also where the glass and the pill's highlight lighten it most.
            for lightened in [false, true] {
                let pill = SidebarGlassPalette.pillColor(item.pill, on: item.backdrop, lightened: lightened)
                #expect(item.text.contrast(with: pill) >= 4.5, "\(item) lightened: \(lightened)")
            }
        }
    }

    /// Faint, but it shows: the pill stands out from the panel.
    @Test("the pill shows on the sidebar, and stays faint")
    func pillShowsAndStaysFaint() {
        for item in Self.cases {
            let pill = SidebarGlassPalette.pillColor(item.pill, on: item.backdrop)
            let shift = max(
                abs(pill.red - item.backdrop.red),
                abs(pill.green - item.backdrop.green),
                abs(pill.blue - item.backdrop.blue)
            )
            #expect(shift > 0.04, "\(item)")
            if item.spaceHex != nil || item.theme != nil {
                #expect(item.pill.opacity <= 0.35, "\(item)")
                // Never so faint that the space's color is lost.
                #expect(item.pill.opacity >= SidebarGlassPalette.minimumDarkOpacity - 0.001, "\(item)")
            }
        }
    }

    /// The pill takes the space's color, or its theme's accent.
    @Test func pillFollowsTheSpace() {
        let hex = SpaceColor.green.hex
        #expect(SidebarGlassPalette.pill(isDark: true, spaceHex: hex, theme: nil).tintHex == hex)
        #expect(SidebarGlassPalette.pill(isDark: true, spaceHex: nil, theme: .ocean).tintHex == SpaceTheme.ocean
            .accentHex)
        #expect(SidebarGlassPalette.pill(isDark: true, spaceHex: hex, theme: .ocean).tintHex == hex)
    }

    /// White on a light panel: only the neutral light pill gets a shadow.
    @Test func onlyTheWhitePillHasAShadow() {
        #expect(SidebarGlassPalette.needsShadow(isDark: false, spaceHex: nil, theme: nil))
        #expect(!SidebarGlassPalette.needsShadow(isDark: true, spaceHex: nil, theme: nil))
        #expect(!SidebarGlassPalette.needsShadow(isDark: false, spaceHex: SpaceColor.blue.hex, theme: nil))
    }

    @Test func themesKeepTheirColors() {
        for theme in SpaceTheme.allCases {
            #expect(BackdropRGB(hex: theme.backgroundHex).luminance < 0.05, "\(theme)")
            #expect(theme.accentHex.count == 7, "\(theme)")
        }
    }
}

/// Settings › General › Glass Effects: on by default on macOS 26, never
/// with Reduce Transparency, never before macOS 26.
struct GlassEffectsTests {
    @Test func onlyWhenSupportedEnabledAndTransparent() {
        #expect(GlassEffects.isActive(isEnabled: true, reducesTransparency: false, isSupported: true))
        #expect(!GlassEffects.isActive(isEnabled: false, reducesTransparency: false, isSupported: true))
        #expect(!GlassEffects.isActive(isEnabled: true, reducesTransparency: true, isSupported: true))
        #expect(!GlassEffects.isActive(isEnabled: true, reducesTransparency: false, isSupported: false))
    }

    @Test func supportedFromMacOS26() {
        if #available(macOS 26, *) {
            #expect(GlassEffects.isSupported)
        } else {
            #expect(!GlassEffects.isSupported)
        }
    }

    /// Under the setting: why it is off, when it is.
    @Test func theSettingSaysWhyItIsOff() {
        let usual = GlassEffects.detail(reducesTransparency: false, isSupported: true)
        let reduced = GlassEffects.detail(reducesTransparency: true, isSupported: true)
        let old = GlassEffects.detail(reducesTransparency: false, isSupported: false)
        #expect(Set([usual, reduced, old]).count == 3)
        #expect(reduced
            .contains(
                String(localized: "Off while Reduce Transparency is on in System Settings › Accessibility › Display.")
            ))
    }

    @Test func onUntilTurnedOff() throws {
        let suite = "GlassEffectsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SettingsStore.glassEffectsEnabled(in: defaults))
        defaults.set(false, forKey: SettingsStore.glassEffectsKey)
        #expect(!SettingsStore.glassEffectsEnabled(in: defaults))
        defaults.set(true, forKey: SettingsStore.glassEffectsKey)
        #expect(SettingsStore.glassEffectsEnabled(in: defaults))
    }
}

/// The active tab's pill is behind its icon and title, never over them.
@MainActor
struct SidebarRowBackgroundTests {
    private func centerColor(of view: some View, size: CGFloat) throws -> BackdropRGB {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let middle = CGFloat(image.width) / 2
        context.draw(
            image,
            in: CGRect(x: -middle + 0.5, y: -middle + 0.5, width: CGFloat(image.width), height: CGFloat(image.height))
        )
        return BackdropRGB(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    private func row(isActive: Bool, label: Color) -> some View {
        label.frame(width: 20, height: 20)
            .padding(12)
            .sidebarRowBackground(isActive: isActive, color: .clear, cornerRadius: 10)
            .environment(\.usesGlassEffects, true)
            .environment(\.theme, Theme(colorScheme: .dark, spaceColor: .red))
    }

    @Test(arguments: [false, true])
    func theActiveTabsTitleStaysInFront(isActive: Bool) throws {
        // A green label on a red pill: only green shows where the label is.
        let color = try centerColor(
            of: row(isActive: isActive, label: Color(.sRGB, red: 0, green: 1, blue: 0)),
            size: 44
        )
        #expect(color.green > 0.95, "\(color)")
        #expect(color.red < 0.05, "\(color)")
    }

    @Test(arguments: [false, true])
    func onlyTheActiveTabShowsThePill(isActive: Bool) throws {
        let color = try centerColor(of: row(isActive: isActive, label: .clear), size: 44)
        #expect((color.red > 0.1) == isActive, "\(color)")
    }
}
