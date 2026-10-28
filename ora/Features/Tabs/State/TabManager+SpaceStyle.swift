import Foundation

/// Name, icon and color of a space (see `SpaceEditorView`).
extension TabManager {
    func updateSpace(
        _ container: TabContainer,
        name: String,
        emoji: String,
        iconSymbol: String?,
        color: SpaceColor?,
        theme: SpaceTheme?
    ) {
        container.name = name
        container.emoji = emoji
        container.iconSymbol = iconSymbol
        container.colorName = color?.rawValue
        container.themeName = theme?.rawValue
        try? modelContext.save()
    }

    @discardableResult
    func createSpace(
        name: String,
        emoji: String,
        iconSymbol: String?,
        color: SpaceColor?,
        theme: SpaceTheme?
    ) -> TabContainer {
        let container = createContainer(name: name, emoji: emoji)
        updateSpace(container, name: name, emoji: emoji, iconSymbol: iconSymbol, color: color, theme: theme)
        return container
    }
}
