@testable import Ombre
import Testing

struct SettingsBackdropTests {
    /// macOS's text colors over the backdrop: black in light mode, white in
    /// dark mode; secondary text is them, half transparent.
    private let lightText = BackdropRGB(hex: "#000000")
    private let darkText = BackdropRGB(hex: "#FFFFFF")

    private func secondary(on background: BackdropRGB, isDark: Bool) -> BackdropRGB {
        background.mixed(with: isDark ? darkText : lightText, by: isDark ? 0.55 : 0.5)
    }

    /// Secondary text's contrast on macOS's own light window background.
    private var systemLightSecondaryContrast: Double {
        let window = BackdropRGB(hex: "#ECECEC")
        return secondary(on: window, isDark: false).contrast(with: window)
    }

    private var allPalettes: [(isDark: Bool, stops: [BackdropRGB])] {
        let spaces: [String?] = [nil] + SpaceColor.allCases.map(\.hex)
        return [true, false].flatMap { isDark in
            spaces.map { (isDark, SettingsBackdropPalette.stops(isDark: isDark, spaceHex: $0)) }
        }
    }

    @Test("the gradient is never pure white nor pure black") func gradientAvoidsPureWhiteAndBlack() {
        for palette in allPalettes {
            for stop in palette.stops {
                #expect(stop.luminance > 0.01)
                #expect(stop.luminance < 0.95)
            }
        }
    }

    @Test("text stays legible on every stop, for every space color (WCAG)") func textStaysLegible() {
        for palette in allPalettes {
            let text = palette.isDark ? darkText : lightText
            // AA in dark mode; in light mode, as on the system's window.
            let minimum = palette.isDark ? 4.5 : systemLightSecondaryContrast - 0.05
            for stop in palette.stops {
                #expect(text.contrast(with: stop) >= 7, "AAA for text, \(stop)")
                let gray = secondary(on: stop, isDark: palette.isDark)
                #expect(gray.contrast(with: stop) >= minimum, "secondary text, \(stop)")
            }
        }
    }

    @Test("a space's color leans the gradient's top, its bottom stays the evening's") func spaceColorLeansTop() {
        let plain = SettingsBackdropPalette.stops(isDark: true)
        let blue = SettingsBackdropPalette.stops(isDark: true, spaceHex: SpaceColor.blue.hex)
        #expect(blue[0] != plain[0])
        #expect(blue.last == plain.last)
    }

    @Test("contrast follows WCAG") func contrastFollowsWCAG() {
        #expect(abs(lightText.contrast(with: darkText) - 21) < 0.001)
        #expect(abs(darkText.contrast(with: darkText) - 1) < 0.001)
    }

    @Test("glass only exists on macOS 26: before, the window stays plain") func plainBeforeMacOS26() {
        for backdrop in SettingsBackdrop.allCases {
            if #available(macOS 26, *) {
                #expect(backdrop.effective == backdrop)
            } else {
                #expect(backdrop.effective == .plain)
            }
        }
    }

    @Test("the arrow keys move the selection inside the list") func arrowKeysMoveSelection() {
        let ids = [1, 2, 3]
        #expect(GlassSelection.next(after: nil, in: ids, by: 1) == 1)
        #expect(GlassSelection.next(after: 1, in: ids, by: 1) == 2)
        #expect(GlassSelection.next(after: 3, in: ids, by: 1) == 3)
        #expect(GlassSelection.next(after: 1, in: ids, by: -1) == 1)
        #expect(GlassSelection.next(after: 9, in: ids, by: -1) == 1)
        #expect(GlassSelection.next(after: 1, in: [Int](), by: 1) == nil)
    }
}
