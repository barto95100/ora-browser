import AppKit
import SwiftUI

/// Text and icons over a page's header color (the address bar takes it):
/// white or black, whichever stands out more (WCAG's choice: black on a
/// bright orange), and never fainter than WCAG AA allows (4.5:1 for text,
/// 3:1 for icons in a quieter state).
struct ReadableForeground {
    /// The address, and the bar's icons.
    let primary: Color
    /// The page's title beside the address.
    let secondary: Color
    /// Icons in a quieter state (protections off, capture paused): 3:1.
    let muted: Color
    /// The address field's fill, a tint of the text color.
    let fieldFill: Color
    /// White over a dark color, black over a light one.
    let isLight: Bool
    private let base: RGB
    private let field: RGB
    private let primaryAlpha: Double

    /// An sRGB color, components from 0 to 1.
    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// How much of the text color tints the address field, at most.
    static let fieldTint = 0.08
    static let textContrast = 4.5
    static let iconContrast = 3.0

    init(on background: Color) {
        self.init(on: NSColor(background))
    }

    init(on background: NSColor) {
        let header = Self.rgb(of: background) ?? RGB(red: 0, green: 0, blue: 0)
        let headerLuminance = Self.luminance(header)
        isLight = Self.contrast(1, headerLuminance) >= Self.contrast(0, headerLuminance)
        let base = isLight ? RGB(red: 1, green: 1, blue: 1) : RGB(red: 0, green: 0, blue: 0)
        // Text and icons sit on the field (header tinted toward them): the
        // harder of the two backgrounds.
        // Lighter where full text color would stand out too little (mid greys).
        var tint = Self.fieldTint
        while tint > 0,
              Self.contrast(Self.luminance(base), Self.luminance(Self.blend(base, over: header, alpha: tint)))
              < Self.textContrast
        {
            tint = max(0, tint - 0.01)
        }
        let field = Self.blend(base, over: header, alpha: tint)
        self.base = base
        self.field = field
        let color: Color = isLight ? .white : .black
        primaryAlpha = Self.alpha(of: base, over: field, preferred: 0.6, contrast: Self.textContrast)
        primary = color.opacity(primaryAlpha)
        secondary = color.opacity(Self.alpha(of: base, over: field, preferred: 0.45, contrast: Self.textContrast))
        muted = color.opacity(Self.alpha(of: base, over: field, preferred: 0.35, contrast: Self.iconContrast))
        fieldFill = color.opacity(tint)
    }

    /// For a button that shows its color at `dimming` of it when idle (0.7:
    /// the toolbar's buttons): still 3:1 once dimmed, never fainter than
    /// `primary`.
    func icon(dimmedBy dimming: Double) -> Color {
        var alpha = primaryAlpha
        while alpha < 1 {
            let drawn = Self.blend(base, over: field, alpha: alpha * dimming)
            if Self.contrast(Self.luminance(drawn), Self.luminance(field)) >= Self.iconContrast { break }
            alpha = min(1, alpha + 0.05)
        }
        return (isLight ? Color.white : Color.black).opacity(alpha)
    }

    // MARK: - WCAG

    /// The faintest opacity, from `preferred` up, at which `base` drawn over
    /// `background` reaches `contrast` (fully opaque if it never does).
    static func alpha(
        of base: RGB,
        over background: RGB,
        preferred: Double,
        contrast wanted: Double
    ) -> Double {
        let backgroundLuminance = luminance(background)
        var alpha = preferred
        while alpha < 1 {
            let drawn = blend(base, over: background, alpha: alpha)
            if contrast(luminance(drawn), backgroundLuminance) >= wanted { return alpha }
            alpha = min(1, alpha + 0.05)
        }
        return 1
    }

    /// What the screen shows: `color` at `alpha` over `background` (sRGB).
    static func blend(
        _ color: RGB,
        over background: RGB,
        alpha: Double
    ) -> RGB {
        RGB(
            red: color.red * alpha + background.red * (1 - alpha),
            green: color.green * alpha + background.green * (1 - alpha),
            blue: color.blue * alpha + background.blue * (1 - alpha)
        )
    }

    /// WCAG relative luminance of an sRGB color.
    static func luminance(_ rgb: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    /// WCAG contrast ratio between two luminances.
    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    static func rgb(of color: NSColor) -> RGB? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return RGB(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent)
        )
    }
}
