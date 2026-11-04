import Foundation

/// Name, emoji, symbol, color and theme of a space: what the space editor
/// and the first-launch assistant change.
struct SpaceLook: Equatable {
    var name: String
    var emoji: String
    var iconSymbol: String?
    var color: SpaceColor?
    var theme: SpaceTheme?

    init(
        name: String,
        emoji: String = ContainerConstants.defaultEmoji,
        iconSymbol: String? = nil,
        color: SpaceColor? = nil,
        theme: SpaceTheme? = nil
    ) {
        self.name = name
        self.emoji = emoji
        self.iconSymbol = iconSymbol
        self.color = color
        self.theme = theme
    }

    init(of container: TabContainer) {
        self.init(
            name: container.name,
            emoji: container.emoji,
            iconSymbol: container.iconSymbol,
            color: container.spaceColor,
            theme: container.spaceTheme
        )
    }

    /// The same look under another name.
    init(_ look: SpaceLook, name: String) {
        self = look
        self.name = name
    }

    /// The name without surrounding spaces.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
