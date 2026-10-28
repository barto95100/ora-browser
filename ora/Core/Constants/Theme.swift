import AppKit
import SwiftUI

// swiftlint:disable identifier_name
struct Theme: Equatable {
    let colorScheme: ColorScheme
    /// The color of the space shown, if it has one: it tints the window
    /// background and the active tab, like Arc.
    var spaceColor: SpaceColor?

    var primary: Color {
        Color(hex: "#f3e5d6")
    }

    var primaryDark: Color {
        Color(hex: "#141414")
    }

    var accent: Color {
        colorScheme == .dark ? Color(hex: "#FF9B51") : Color(hex: "#F16D34")
    }

    var background: Color {
        colorScheme == .dark ? Color(hex: "#0F0E0E") : .white
    }

    var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    var subtleWindowBackgroundColor: Color {
        if let tint = spaceColor?.color {
            return colorScheme == .dark
                ? tint.mix(with: .black, by: 0.55).opacity(0.6)
                : tint.mix(with: .white, by: 0.55).opacity(0.6)
        }
        return colorScheme == .dark ? self.primaryDark.opacity(0.3) : self.primary.opacity(0.3)
    }

    /// The window background: the space's color as a soft vertical gradient,
    /// like Arc, or the usual background.
    var windowBackground: AnyShapeStyle {
        guard let tint = spaceColor?.color else { return AnyShapeStyle(subtleWindowBackgroundColor) }
        let base: Color = colorScheme == .dark ? .black : .white
        let top = tint.mix(with: base, by: colorScheme == .dark ? 0.45 : 0.4)
        let bottom = tint.mix(with: base, by: colorScheme == .dark ? 0.7 : 0.7)
        return AnyShapeStyle(
            LinearGradient(colors: [top.opacity(0.7), bottom.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        )
    }

    var solidWindowBackgroundColor: Color {
        colorScheme == .dark ? self.primaryDark : self.primary
    }

    var invertedSolidWindowBackgroundColor: Color {
        colorScheme == .dark ? self.primary : self.primaryDark
    }

    var activeTabBackground: Color {
        if let tint = spaceColor?.color {
            // Light: dark enough for the white title of the active tab.
            return colorScheme == .dark ? tint.opacity(0.32) : tint.mix(with: .black, by: 0.45)
        }
        return colorScheme == .dark ? .white.opacity(0.15) : self.primaryDark.opacity(0.8)
    }

    var mutedBackground: Color {
        colorScheme == .dark ? .white.opacity(0.17) : self.primaryDark.opacity(0.1)
    }

    var popoverBackground: Color {
        colorScheme == .dark ? Color(hex: "#242424") : .white
    }

    var popoverMutedBackground: Color {
        colorScheme == .dark ? Color(hex: "#1d1d1d") : self.primaryDark.opacity(0.1)
    }

    var mutedForeground: Color {
        .secondary
    }

    var disabledBackground: Color {
        colorScheme == .dark ? .black.opacity(0.3) : .white.opacity(0.3)
    }

    var disabledForeground: Color {
        colorScheme == .dark ? .white.opacity(0.3) : Color(.disabledControlTextColor)
    }

    var launcherMainBackground: Color {
        colorScheme == .dark ? self.popoverBackground.opacity(0.75) : .white.opacity(0.8)
    }

    var placeholder: Color {
        Color(.placeholderTextColor)
    }

    var border: Color {
        Color(.separatorColor)
    }

    var destructive: Color {
        Color(hex: "#FF6969")
    }

    var success: Color {
        Color(hex: "#93DA97")
    }

    var warning: Color {
        Color(hex: "#FFBF78")
    }

    var info: Color {
        Color(hex: "#799EFF")
    }

    /// Search engine colors
    var grok: Color {
        colorScheme == .dark ? .white : .black
    }

    var claude: Color {
        Color(hex: "#d97757")
    }

    var openai: Color {
        colorScheme == .dark ? .white : .black
    }

    var t3chat: Color {
        Color(hex: "#960971")
    }

    var perplexity: Color {
        Color(hex: "#20808D")
    }

    var reddit: Color {
        Color(hex: "#FF4500")
    }

    var x: Color {
        colorScheme == .dark ? .white : .black
    }

    var google: Color {
        .blue
    }

    var youtube: Color {
        Color(hex: "#FC0D1B")
    }

    var github: Color {
        colorScheme == .dark ? .white : Color(hex: "#181717")
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(colorScheme: .light)  // fallback
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

struct ThemeProvider: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.theme, Theme(colorScheme: colorScheme))
    }
}
