import AppKit
@preconcurrency import WebKit

/// The page's web view: lets the page adjust WebKit's context menu, and
/// hides the mouse from the page under a floating panel (`MouseShield`).
final class OmbreWebView: WKWebView {
    weak var contextMenuOwner: BrowserPage?

    private var shieldTracker = MouseShieldTracker()

    var mouseShield: MouseShield? {
        get { shieldTracker.shield }
        set {
            guard newValue != shieldTracker.shield else { return }
            let wasShown = shieldTracker.shield != nil
            shieldTracker.shield = newValue
            // Only when the panel shows, not while a button is held (a drag
            // in the page, such as a video's progress bar, goes on).
            guard newValue != nil, !wasShown, NSEvent.pressedMouseButtons == 0, let window else { return }
            let mouse = window.mouseLocationOutsideOfEventStream
            if shieldTracker.shieldShown(mouseAtX: mouse.x, windowWidth: windowWidth) == .leavePage {
                leavePage(at: mouse.y, modifierFlags: NSEvent.modifierFlags, windowNumber: window.windowNumber)
            }
        }
    }

    /// Under the panel, the page gets no click, right click or scroll
    /// either: they go to the panel, or nowhere (its margins).
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let superview, shieldTracker.shield != nil {
            let windowX = superview.convert(point, to: nil).x
            if shieldTracker.isCovered(windowX: windowX, windowWidth: windowWidth) { return nil }
        }
        return super.hitTest(point)
    }

    private var windowWidth: CGFloat? {
        window?.contentView?.bounds.width
    }

    override func mouseMoved(with event: NSEvent) {
        switch shieldTracker.mouseMoved(toX: event.locationInWindow.x, windowWidth: windowWidth) {
        case .forward:
            super.mouseMoved(with: event)
        case .ignore:
            break
        case .leavePage:
            leavePage(
                at: event.locationInWindow.y,
                modifierFlags: event.modifierFlags,
                windowNumber: event.windowNumber
            )
        }
    }

    /// As if the mouse left the page, at a point just outside it (the page
    /// reads where it went): its hover effects and tooltip end.
    private func leavePage(at windowY: CGFloat, modifierFlags: NSEvent.ModifierFlags, windowNumber: Int) {
        let outside = NSPoint(x: convert(bounds, to: nil).minX - 1, y: windowY)
        if let exit = NSEvent.enterExitEvent(
            with: .mouseExited, location: outside, modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil
        ) {
            super.mouseExited(with: exit)
        }
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard !shieldTracker.isCovered(windowX: event.locationInWindow.x, windowWidth: windowWidth) else { return }
        super.mouseEntered(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        contextMenuOwner?.adjustContextMenu(menu)
    }
}

/// Context menu of links and images, like Arc: "… in New Tab" (WebKit says
/// "New Window", but Ombre opens tabs), plus a background tab and Split View.
/// The added items run WebKit's own "open link" action with another way to
/// open it, so the link is the one WebKit found under the mouse.
extension BrowserPage {
    /// WebKit's identifiers of its items (exported constants of a private
    /// header, read here as strings): `ContextMenuIdentifierTests` fails if
    /// WebKit changes them, else the added items would vanish silently.
    static let openLinkIdentifier = "WKMenuItemIdentifierOpenLinkInNewWindow"
    static let openImageIdentifier = "WKMenuItemIdentifierOpenImageInNewWindow"

    func adjustContextMenu(_ menu: NSMenu) {
        if let openLink = menu.items.first(where: { $0.identifier?.rawValue == Self.openLinkIdentifier }) {
            openLink.title = String(localized: "Open Link in New Tab")
            let index = menu.index(of: openLink)
            menu.insertItem(
                openingItem(
                    String(localized: "Open Link in Background Tab"),
                    running: openLink,
                    disposition: .background
                ),
                at: index + 1
            )
            menu.insertItem(
                openingItem(String(localized: "Open Link in Split View"), running: openLink, disposition: .splitView),
                at: index + 2
            )
        }
        if let openImage = menu.items.first(where: { $0.identifier?.rawValue == Self.openImageIdentifier }) {
            openImage.title = String(localized: "Open Image in New Tab")
        }
        if let items = delegate?.browserPageContextMenuItems(self), !items.isEmpty {
            menu.addItem(.separator())
            items.forEach(menu.addItem)
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

    /// An item of the context menu just asked for a new tab.
    var hasPendingNewTabDisposition: Bool {
        guard let pending = pendingNewTabDisposition else { return false }
        return Date().timeIntervalSince(pending.date) < 2
    }

    /// How the new tab WebKit asks for opens: as chosen in the context menu
    /// just before (WebKit asks a moment later), or in front.
    func takeNewTabDisposition() -> BrowserNewTabDisposition {
        defer { pendingNewTabDisposition = nil }
        guard hasPendingNewTabDisposition, let pending = pendingNewTabDisposition else { return .foreground }
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
