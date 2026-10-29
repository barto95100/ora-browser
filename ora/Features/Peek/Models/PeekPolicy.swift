import AppKit

/// What a click on a link from a pinned or favorite tab to another site does
/// (General settings).
enum PinnedLinkBehavior: String, CaseIterable, Identifiable {
    /// A preview over the page, like Arc.
    case peek
    case newTab
    case sameTab

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .peek: "Peek"
        case .newTab: "New Tab"
        case .sameTab: "Same Tab"
        }
    }
}

/// When a link opens in Peek, like Arc: a plain click, in a pinned or favorite
/// tab, on a link to another web site. The pinned page stays where it is.
enum PeekPolicy {
    static func opensInPeek(
        tabType: TabType,
        isLinkClick: Bool,
        modifierFlags: NSEvent.ModifierFlags,
        from pageURL: URL?,
        to destination: URL,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled, isLinkClick, tabType != .normal else { return false }
        // ⌘-click and the like keep their own meaning (new tab...).
        guard modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return false }
        guard let scheme = destination.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let pageURL else { return true }
        return !WebSite.isSameSite(pageURL, destination)
    }
}
