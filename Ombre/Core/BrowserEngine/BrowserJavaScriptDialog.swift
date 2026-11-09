import Foundation

/// A dialog a page asks for with `alert`, `confirm` or `prompt`.
struct BrowserJavaScriptDialog: Equatable {
    enum Kind: Equatable {
        case alert
        case confirm
        case prompt(defaultText: String)
    }

    let kind: Kind
    let message: String
    /// The site of the frame that asks: the dialog says where it comes from.
    let host: String

    /// "The page at example.com says:", or "This page says:" for a page with
    /// no site (a `data:` page, a sandboxed frame).
    var title: String {
        host.isEmpty ? String(localized: "This page says:") : String(localized: "The page at \(host) says:")
    }
}

/// What the page gets back: OK or Cancel, and the text typed for a prompt.
struct BrowserJavaScriptDialogReply: Equatable {
    let isConfirmed: Bool
    let text: String?

    /// Not shown (or closed): `confirm` gets false, `prompt` gets null.
    static let refused = BrowserJavaScriptDialogReply(isConfirmed: false, text: nil)
}

/// When a page may show a dialog. Like Safari: only while the page is shown
/// (a background tab can't put a dialog over the one in front), and from the
/// second dialog the user can stop the page from showing more, until it loads
/// a new document. A page calling `alert` in a loop can't lock the window.
struct JavaScriptDialogPolicy {
    enum Decision: Equatable {
        /// Answer right away, without showing anything.
        case refuse
        /// Show it; offer to stop the page's dialogs.
        case show(offersToStopDialogs: Bool)
    }

    private(set) var shownCount = 0
    private(set) var isStopped = false

    mutating func decide(isPageShown: Bool) -> Decision {
        guard isPageShown, !isStopped else { return .refuse }
        shownCount += 1
        return .show(offersToStopDialogs: shownCount >= 2)
    }

    /// The user chose to stop the page's dialogs.
    mutating func stopDialogs() {
        isStopped = true
    }

    /// The page loaded a new document: it starts afresh.
    mutating func pageDidCommitNewDocument() {
        self = JavaScriptDialogPolicy()
    }
}
