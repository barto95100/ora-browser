import SwiftData

extension TabManager {
    /// Name, emoji, symbol, color and theme of a space.
    func updateSpace(_ container: TabContainer, look: SpaceLook) {
        container.name = look.name
        container.emoji = look.emoji
        container.iconSymbol = look.iconSymbol
        container.colorName = look.color?.rawValue
        container.themeName = look.theme?.rawValue
        modelContext.saveOrLog("update space style")
    }

    /// A new space, which becomes the active one.
    @discardableResult
    func createSpace(look: SpaceLook) -> TabContainer {
        let container = createContainer(name: look.name, emoji: look.emoji)
        updateSpace(container, look: look)
        return container
    }

    /// A new space after the others, without leaving the active one.
    @discardableResult
    func addSpace(look: SpaceLook) -> TabContainer {
        let container = TabContainer(name: look.name, emoji: look.emoji)
        container.order = nextContainerOrder()
        // Not the space to open at the next launch.
        container.lastAccessedAt = .distantPast
        modelContext.insert(container)
        updateSpace(container, look: look)
        PrivacyDefaults.applyToNewSpace(container.id)
        return container
    }
}
