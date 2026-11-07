import AppKit
@testable import Ombre
import Testing

/// The address bar's text and icons stay readable over any header color.
struct ReadableForegroundTests {
    /// Header colors of real sites and the hard cases in between.
    static let headers: [(String, UInt32)] = [
        ("spiegel.de orange-red", 0xE64415),
        ("bright orange", 0xFF9500),
        ("yellow", 0xFFCC00),
        ("red", 0xD0021B),
        ("green", 0x34C759),
        ("light blue", 0x5AC8FA),
        ("navy", 0x0A2540),
        ("mid grey", 0x767676),
        ("white", 0xFFFFFF),
        ("black", 0x000000)
    ]

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// What the screen shows for `foreground` over `background`, as a contrast ratio.
    private static func contrast(of foreground: NSColor, over background: NSColor) throws -> Double {
        let drawnColor = try #require(foreground.usingColorSpace(.sRGB))
        let under = try #require(ReadableForeground.rgb(of: background))
        let drawn = try ReadableForeground.blend(
            #require(ReadableForeground.rgb(of: drawnColor)),
            over: under,
            alpha: Double(drawnColor.alphaComponent)
        )
        return ReadableForeground.contrast(
            ReadableForeground.luminance(drawn),
            ReadableForeground.luminance(under)
        )
    }

    /// The address field: the header tinted toward the text color.
    private static func field(of background: NSColor, colors: ReadableForeground) throws -> NSColor {
        let fill = try #require(NSColor(colors.fieldFill).usingColorSpace(.sRGB))
        let under = try #require(ReadableForeground.rgb(of: background))
        let tint = try #require(ReadableForeground.rgb(of: fill))
        let drawn = ReadableForeground.blend(tint, over: under, alpha: Double(fill.alphaComponent))
        return NSColor(srgbRed: drawn.red, green: drawn.green, blue: drawn.blue, alpha: 1)
    }

    @Test(arguments: headers)
    func textReachesAAOnTheField(name: String, hex: UInt32) throws {
        let header = Self.color(hex)
        let colors = ReadableForeground(on: header)
        let field = try Self.field(of: header, colors: colors)
        for (what, color) in [("address", colors.primary), ("title", colors.secondary)] {
            let contrast = try Self.contrast(of: NSColor(color), over: field)
            #expect(contrast >= ReadableForeground.textContrast - 0.01, "\(what) over \(name): \(contrast)")
        }
    }

    /// Icons in a quieter state, and buttons dimmed when idle, keep 3:1.
    @Test(arguments: headers)
    func dimmedIconsReachThreeToOne(name: String, hex: UInt32) throws {
        let header = Self.color(hex)
        let colors = ReadableForeground(on: header)
        let field = try Self.field(of: header, colors: colors)
        let muted = try Self.contrast(of: NSColor(colors.muted), over: field)
        #expect(muted >= ReadableForeground.iconContrast - 0.01, "muted over \(name): \(muted)")
        for dimming in [0.7] {
            let icon = try #require(NSColor(colors.icon(dimmedBy: dimming)).usingColorSpace(.sRGB))
            let dimmed = icon.withAlphaComponent(icon.alphaComponent * dimming)
            let contrast = try Self.contrast(of: dimmed, over: field)
            #expect(contrast >= ReadableForeground.iconContrast - 0.01, "×\(dimming) over \(name): \(contrast)")
        }
    }

    @Test
    func darkHeadersGetLightText() {
        #expect(ReadableForeground(on: Self.color(0x0A2540)).isLight)
        #expect(ReadableForeground(on: Self.color(0x000000)).isLight)
        #expect(!ReadableForeground(on: Self.color(0xFFFFFF)).isLight)
        #expect(!ReadableForeground(on: Self.color(0xFFCC00)).isLight)
    }

    /// The old rule (white or black at half opacity) failed on spiegel.de.
    @Test
    func theOldRuleWasUnreadableOnSpiegel() throws {
        let background = Self.color(0xE64415)
        let old = NSColor.white.withAlphaComponent(0.5)
        #expect(try Self.contrast(of: old, over: background) < ReadableForeground.iconContrast)
    }

    /// The well-known WCAG values.
    @Test
    func contrastMatchesWCAG() {
        #expect(abs(ReadableForeground.contrast(1, 0) - 21) < 0.001)
        let grey = ReadableForeground.luminance(.init(red: 0x76 / 255.0, green: 0x76 / 255.0, blue: 0x76 / 255.0))
        #expect(abs(ReadableForeground.contrast(1, grey) - 4.54) < 0.01)
    }
}
