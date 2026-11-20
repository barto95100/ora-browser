import SwiftUI
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
            spaces.map { (isDark, SettingsBackdropPalette.strongest(isDark: isDark, spaceHex: $0)) }
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
            // AA in dark mode; in light mode, nearly as on the system's window
            // (which is below AA itself).
            let minimum = palette.isDark ? 4.5 : systemLightSecondaryContrast * 0.95
            for stop in palette.stops {
                #expect(text.contrast(with: stop) >= 7, "AAA for text, \(stop)")
                let gray = secondary(on: stop, isDark: palette.isDark)
                #expect(gray.contrast(with: stop) >= minimum, "secondary text, \(stop)")
            }
        }
    }

    @Test("the tint stays faint: 8 to 12 %, never a flat violet") func tintStaysFaint() {
        for opacity in [SettingsBackdropPalette.tintOpacity, SettingsBackdropPalette.spaceTintOpacity] {
            #expect((0.08 ... 0.12).contains(opacity))
        }
        for palette in allPalettes {
            let window = palette.isDark ? SettingsBackdropPalette.darkWindow : SettingsBackdropPalette.lightWindow
            for stop in palette.stops {
                let shift = max(
                    abs(stop.red - window.red),
                    abs(stop.green - window.green),
                    abs(stop.blue - window.blue)
                )
                #expect(shift <= SettingsBackdropPalette.spaceTintOpacity + 0.001, "\(stop)")
            }
        }
    }

    @Test("a space's color tints the top instead of the evening's") func spaceColorTints() {
        let ombre = SettingsBackdropPalette.tint()
        let blue = SettingsBackdropPalette.tint(spaceHex: SpaceColor.blue.hex)
        #expect(blue[0] == BackdropRGB(hex: SpaceColor.blue.hex))
        #expect(blue != ombre)
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

/// The selected row's pill is behind its icon and name, never over them.
@MainActor
struct SelectionPillRowTests {
    /// The color at the middle of `view`, drawn offscreen.
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

    @Test(arguments: [false, true])
    func theSelectedRowsLabelStaysInFront(isSelected: Bool) throws {
        // A green label on a red pill: only green shows where the label is.
        let row = SelectionPillRow(isSelected: isSelected, tint: .red) {
            Color(.sRGB, red: 0, green: 1, blue: 0).frame(width: 20, height: 20)
        }
        let color = try centerColor(of: row, size: 44)
        #expect(color.green > 0.95, "\(color)")
        #expect(color.red < 0.05, "\(color)")
    }

    @Test(arguments: [false, true])
    func onlyTheSelectedRowShowsItsPill(isSelected: Bool) throws {
        let row = SelectionPillRow(isSelected: isSelected, tint: .red) { Color.clear.frame(width: 20, height: 20) }
        let color = try centerColor(of: row, size: 44)
        #expect((color.red > 0.1) == isSelected, "\(color)")
    }
}
