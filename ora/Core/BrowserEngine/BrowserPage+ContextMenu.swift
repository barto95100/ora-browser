import AppKit
@preconcurrency import WebKit

/// The page's web view: lets the page adjust WebKit's context menu.
final class OraWebView: WKWebView {
    weak var contextMenuOwner: BrowserPage?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        contextMenuOwner?.adjustContextMenu(menu)
    }
}

/// Context menu of links and images, like Arc: "… in New Tab" (WebKit says
/// "New Window", but Ora opens tabs), plus a background tab and Split View.
/// The added items run WebKit's own "open link" action with another way to
/// open it, so the link is the one WebKit found under the mouse.
extension BrowserPage {
    private static let openLinkIdentifier = "WKMenuItemIdentifierOpenLinkInNewWindow"
    private static let openImageIdentifier = "WKMenuItemIdentifierOpenImageInNewWindow"

    func adjustContextMenu(_ menu: NSMenu) {
        if let openLink = menu.items.first(where: { $0.identifier?.rawValue == Self.openLinkIdentifier }) {
            openLink.title = "Open Link in New Tab"
            let index = menu.index(of: openLink)
            menu.insertItem(
                openingItem("Open Link in Background Tab", running: openLink, disposition: .background),
                at: index + 1
            )
            menu.insertItem(
                openingItem("Open Link in Split View", running: openLink, disposition: .splitView),
                at: index + 2
            )
        }
        if let openImage = menu.items.first(where: { $0.identifier?.rawValue == Self.openImageIdentifier }) {
            openImage.title = "Open Image in New Tab"
        }
    }

    private func openingItem(
        _ title: String,
        running original: NSMenuItem,
        disposition: BrowserNewTabDisposition
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runOpeningItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = OpeningItem(original: original, disposition: disposition)
        return item
    }

    @objc private func runOpeningItem(_ item: NSMenuItem) {
        guard let opening = item.representedObject as? OpeningItem, let action = opening.original.action else { return }
        pendingNewTabDisposition = (opening.disposition, Date())
        NSApp.sendAction(action, to: opening.original.target, from: opening.original)
    }

    /// How the new tab WebKit asks for opens: as chosen in the context menu
    /// just before (WebKit asks a moment later), or in front.
    func takeNewTabDisposition() -> BrowserNewTabDisposition {
        defer { pendingNewTabDisposition = nil }
        guard let pending = pendingNewTabDisposition, Date().timeIntervalSince(pending.date) < 2 else {
            return .foreground
        }
        return pending.disposition
    }
}

private final class OpeningItem {
    let original: NSMenuItem
    let disposition: BrowserNewTabDisposition

    init(original: NSMenuItem, disposition: BrowserNewTabDisposition) {
        self.original = original
        self.disposition = disposition
    }
}
