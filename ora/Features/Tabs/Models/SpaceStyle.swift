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

extension TabContainer {
    var spaceColor: SpaceColor? {
        colorName.flatMap(SpaceColor.init(rawValue:))
    }
}
