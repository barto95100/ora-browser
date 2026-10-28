import SwiftUI

/// Color of a space, like Arc: tints its icon, its active tab and the window
/// background (see `Theme.spaceColor`). Stored by name, so the shades can be
/// tuned without touching saved spaces.
enum SpaceColor: String, CaseIterable, Identifiable {
    case gray
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal

    var id: String {
        rawValue
    }

    var color: Color {
        switch self {
        case .gray: Color(hex: "#9A9CA3")
        case .blue: Color(hex: "#5BAEEF")
        case .indigo: Color(hex: "#8B8FEA")
        case .purple: Color(hex: "#B585DE")
        case .pink: Color(hex: "#EE87B2")
        case .red: Color(hex: "#EC6F6A")
        case .orange: Color(hex: "#F5A05A")
        case .yellow: Color(hex: "#E3BC57")
        case .green: Color(hex: "#6FC17E")
        case .teal: Color(hex: "#5ABFC6")
        }
    }

    var title: String {
        rawValue.capitalized
    }
}

/// Symbols a space can use as its icon, instead of an emoji.
enum SpaceIcon {
    static let symbols = [
        "globe", "briefcase", "house", "chevron.left.forwardslash.chevron.right", "paintpalette",
        "book.closed", "graduationcap", "music.note", "camera", "gamecontroller",
        "cup.and.saucer", "leaf", "heart", "star", "sparkles",
        "airplane", "bag", "dumbbell", "lightbulb", "moon"
    ]
}

/// A dark theme for a space, like Arc's: the window background and an
/// accent. A space with a theme is always shown dark.
enum SpaceTheme: String, CaseIterable, Identifiable {
    case graphite
    case midnight
    case mocha
    case slate
    case plum
    case lavender
    case ember
    case rose
    case solarized
    case indigo
    case sage
    case ocean

    var id: String {
        rawValue
    }

    var title: String {
        self == .rose ? "Rosé" : rawValue.capitalized
    }

    var background: Color {
        switch self {
        case .graphite: Color(hex: "#1E1F22")
        case .midnight: Color(hex: "#15182B")
        case .mocha: Color(hex: "#2A211C")
        case .slate: Color(hex: "#262B33")
        case .plum: Color(hex: "#251C2E")
        case .lavender: Color(hex: "#2A2836")
        case .ember: Color(hex: "#2B1D19")
        case .rose: Color(hex: "#2B1E25")
        case .solarized: Color(hex: "#12313A")
        case .indigo: Color(hex: "#1C1D33")
        case .sage: Color(hex: "#222823")
        case .ocean: Color(hex: "#0F1C2B")
        }
    }

    var accent: Color {
        switch self {
        case .graphite: Color(hex: "#E8E8E8")
        case .midnight: Color(hex: "#7C8CF8")
        case .mocha: Color(hex: "#E0975F")
        case .slate: Color(hex: "#7FC4D8")
        case .plum: Color(hex: "#C58BE8")
        case .lavender: Color(hex: "#B9A6F2")
        case .ember: Color(hex: "#F07A3C")
        case .rose: Color(hex: "#F2A1B6")
        case .solarized: Color(hex: "#268BD2")
        case .indigo: Color(hex: "#8C9EFF")
        case .sage: Color(hex: "#A9C48A")
        case .ocean: Color(hex: "#4D9BF0")
        }
    }
}

extension TabContainer {
    var spaceColor: SpaceColor? {
        colorName.flatMap(SpaceColor.init(rawValue:))
    }

    var spaceTheme: SpaceTheme? {
        themeName.flatMap(SpaceTheme.init(rawValue:))
    }
}
