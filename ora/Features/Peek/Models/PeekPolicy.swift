import AppKit

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
