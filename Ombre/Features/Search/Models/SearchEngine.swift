import SwiftUI

struct SearchEngine: Sendable {
    let name: String
    let color: Color
    let icon: String
    let aliases: [String]
    let searchURL: String
    let isAIChat: Bool
    /// False when the site ignores the search in its address (Gemini):
    /// Ombre opens the page and puts the question on the clipboard.
    let acceptsQueryInAddress: Bool
    let foregroundColor: Color?
    let autoSuggestions: (@Sendable (String) async -> [String])?

    init(
        name: String,
        color: Color,
        icon: String,
        aliases: [String],
        searchURL: String,
        isAIChat: Bool,
        acceptsQueryInAddress: Bool = true,
        foregroundColor: Color? = nil,
        autoSuggestions: (@Sendable (String) async -> [String])? = nil
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.aliases = aliases
        self.searchURL = searchURL
        self.isAIChat = isAIChat
        self.acceptsQueryInAddress = acceptsQueryInAddress
        self.foregroundColor = foregroundColor
        self.autoSuggestions = autoSuggestions
    }
}

extension SearchEngine {
    /// The same engine with other keywords (chosen in the settings).
    func with(aliases: [String]) -> SearchEngine {
        SearchEngine(
            name: name,
            color: color,
            icon: icon,
            aliases: aliases,
            searchURL: searchURL,
            isAIChat: isAIChat,
            acceptsQueryInAddress: acceptsQueryInAddress,
            foregroundColor: foregroundColor,
            autoSuggestions: autoSuggestions
        )
    }

    func toLauncherMatch(
        originalAlias: String,
        customEngine: CustomSearchEngine? = nil
    ) -> LauncherMatch {
        return LauncherMatch(
            text: name,
            color: color,
            foregroundColor: foregroundColor ?? .white,
            icon: icon,
            originalAlias: originalAlias,
            searchURL: searchURL,
            acceptsQueryInAddress: acceptsQueryInAddress
        )
    }
}
