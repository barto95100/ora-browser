import Foundation

/// A tab's name, like Arc's Rename: the one the user gave it, or else its
/// page's title. A given name stays whatever the page shows (another title,
/// another page, a reload, a relaunch).
enum TabName {
    /// The name shown wherever the tab is named.
    static func displayed(customName: String?, pageTitle: String) -> String {
        customName ?? pageTitle
    }

    /// The name kept for what was typed: nil (back to the page's title) when
    /// it is empty or only spaces.
    static func stored(fromTyped typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// A search finds the tab by its name and by its page's real title.
    static func matches(_ query: String, customName: String?, pageTitle: String) -> Bool {
        pageTitle.localizedStandardContains(query)
            || (customName?.localizedStandardContains(query) ?? false)
    }
}

extension Tab {
    /// The tab's name (see `TabName`).
    var displayName: String {
        TabName.displayed(customName: customName, pageTitle: title)
    }

    /// Renames the tab to what was typed; an empty name goes back to the
    /// page's title. Private tabs keep it in memory only, like the rest.
    func rename(to typed: String) {
        let name = TabName.stored(fromTyped: typed)
        guard name != customName else { return }
        customName = name
    }
}
