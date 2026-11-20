import SwiftUI

enum LauncherSuggestionType {
    case openedTab, suggestedQuery, suggestedLink, aiChat
    /// « Search on YouTube »: what is typed begins a keyword of the engine;
    /// Tab (or ↩ on it) picks the engine, like its keyword then Tab.
    case keywordEngine
}

struct LauncherSuggestion: Identifiable {
    let id = UUID()
    let type: LauncherSuggestionType
    let title: String
    let name: String?
    let url: URL?
    let icon: String?
    let color: Color?
    let engineForegroundColor: Color?
    let faviconURL: URL?
    let faviconLocalFile: URL?
    /// The active space's AI: its shortcut is shown (⌘↩ by default).
    let isSpaceAI: Bool
    /// Done, it closes the launcher or the address being typed (not a
    /// keyword suggestion: the search is still to type).
    let dismisses: Bool
    let action: () -> Void

    init(
        type: LauncherSuggestionType,
        title: String,
        name: String? = nil,
        url: URL? = nil,
        icon: String? = nil,
        color: Color? = nil,
        engineForegroundColor: Color? = nil,
        faviconURL: URL? = nil,
        faviconLocalFile: URL? = nil,
        isSpaceAI: Bool = false,
        dismisses: Bool = true,
        action: @escaping () -> Void
    ) {
        self.type = type
        self.title = title
        self.name = name
        self.url = url
        self.icon = icon
        self.color = color
        self.engineForegroundColor = engineForegroundColor
        self.faviconURL = faviconURL
        self.faviconLocalFile = faviconLocalFile
        self.isSpaceAI = isSpaceAI
        self.dismisses = dismisses
        self.action = action
    }
}
