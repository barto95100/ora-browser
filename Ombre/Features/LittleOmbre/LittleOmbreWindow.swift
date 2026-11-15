import AppKit
import Combine
import SwiftData
import SwiftUI

/// Little Ombre, like Little Arc: a small window with one page and a minimal
/// bar (the address, its lock, "Open in Ombre"), for links from other apps and
/// ⌥⌘N. Its page is a page of the space links go to (its data, protections,
/// permissions, extensions), in the window it came from, private included
/// (then nothing recorded). "Open in Ombre" (⌘O) makes it a tab; closing it
/// (⌘W) leaves nothing.
@MainActor
final class LittleOmbreWindow: NSObject, NSWindowDelegate {
    /// Open Little Ombres, kept alive until their window closes.
    private(set) static var openWindows: Set<LittleOmbreWindow> = []

    let window: NSWindow
    let popup: PopupPage
    let model: LittleOmbreModel
    /// The browser window it came from: its spaces, downloads and history.
    private weak var tabManager: TabManager?
    private weak var browserWindow: NSWindow?
    /// The page went to a tab: not torn down with the window.
    private var isMovedToTab = false
    private var promptView: NSView?
    private var observations: Set<AnyCancellable> = []

    static func isLittleOmbreWindow(_ window: NSWindow) -> Bool {
        openWindows.contains { $0.window === window }
    }

    /// The Little Ombre showing `window`, if it is one.
    static func showing(_ window: NSWindow?) -> LittleOmbreWindow? {
        guard let window else { return nil }
        return openWindows.first { $0.window === window }
    }

    /// Opens a Little Ombre for `url` (none: an empty one, its address to
    /// type), in the active space of `tabManager`'s window.
    @discardableResult
    static func open(_ url: URL?, from tabManager: TabManager, window browserWindow: NSWindow?) -> LittleOmbreWindow? {
        guard let space = tabManager.activeContainer else { return nil }
        let isPrivate = tabManager.isPrivateWindow
        let page = Tab.makeSpacePage(
            spaceID: space.id,
            isPrivate: isPrivate,
            privateSession: isPrivate ? tabManager.privateSessionID : nil
        )
        let popup = PopupPage(page: page, context: PopupContext(
            spaceID: space.id,
            isPrivate: isPrivate,
            privateSession: isPrivate ? tabManager.privateSessionID : nil,
            downloadManager: tabManager.downloadManager
        ))
        if !isPrivate { popup.history = (tabManager.historyManager, space) }
        let little = LittleOmbreWindow(popup: popup, tabManager: tabManager, space: space)
        little.browserWindow = browserWindow
        little.show()
        if let url {
            page.load(URLRequest(url: url))
        } else {
            little.model.focusAddress()
        }
        page.log("made for Little Ombre")
        return little
    }

    private init(popup: PopupPage, tabManager: TabManager, space: TabContainer) {
        self.popup = popup
        self.tabManager = tabManager
        model = LittleOmbreModel(popup: popup, spaceID: space.id)
        let frame = Self.frame(near: NSApp.keyWindow)
        window = LittleOmbreNSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        (window as? LittleOmbreNSWindow)?.owner = self
        model.owner = self

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let barHeight = LittleOmbreBar.height
        let pageView = popup.page.contentView
        pageView.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: content.bounds.height - barHeight)
        pageView.autoresizingMask = [.width, .height]
        content.addSubview(pageView)
        let bar = NSHostingView(rootView: LittleOmbreBar(popup: popup, model: model))
        bar.frame = NSRect(x: 0, y: content.bounds.height - barHeight, width: content.bounds.width, height: barHeight)
        bar.autoresizingMask = [.width, .minYMargin]
        bar.sizingOptions = []
        content.addSubview(bar)
        window.contentView = content
        window.initialFirstResponder = popup.page.webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 420, height: 300)
        window.setAccessibilityLabel(String(localized: "Little Ombre"))
        popup.pageDidChange = { [weak self] in self?.updateTitle() }
        popup.closeWindow = { [weak self] in self?.window.close() }
        popup.$permissionRequest.sink { [weak self] request in self?.showPrompt(request) }
            .store(in: &observations)
    }

    /// Smaller than a browser window, centered on the screen in front.
    static func frame(near reference: NSWindow?) -> NSRect {
        let visible = (reference?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1000, visible.width * 0.7), height: min(720, visible.height * 0.8))
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func show() {
        updateTitle()
        Self.openWindows.insert(self)
        // A window with one tab for the extensions, before its scripts run.
        WebExtensionsHub.popupOpened(popup.page, window: window, isPrivate: popup.context.isPrivate) { [weak self] in
            self?.window.close()
        }
        // Under the tests: behind the other windows, never in front.
        if TestHost.isActive {
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        window.makeFirstResponder(popup.page.webView)
    }

    /// The site as the title (never the page's own title alone).
    private func updateTitle() {
        let site = PopupTitle.title(for: popup.page.currentURL)
        window.title = site.isEmpty ? String(localized: "Little Ombre") : site
        window.subtitle = site.isEmpty ? "" : (popup.page.title ?? "")
    }

    // MARK: - Open in Ombre

    /// The spaces "Open in Ombre" offers: the window's, in their order.
    var spaces: [TabContainer] {
        guard let tabManager else { return [] }
        let descriptor = FetchDescriptor<TabContainer>(sortBy: TabContainer.displayOrder)
        return (try? tabManager.modelContext.fetch(descriptor)) ?? []
    }

    /// The page becomes a tab of the window Little Ombre came from, in
    /// `space` (none: Little Ombre's own, the page then kept as it is), and
    /// Little Ombre closes.
    func openInOmbre(space: TabContainer? = nil) {
        guard let tabManager, let url = popup.page.currentURL ?? popup.address,
              let target = space ?? spaces.first(where: { $0.id == model.spaceID }) ?? tabManager.activeContainer
        else { return }
        popup.sheets.dismiss()
        popup.cancelPermissionRequest()
        // Lets go of the page first: the tab's view takes it.
        popup.page.contentView.removeFromSuperview()
        let adopted = tabManager.openLittleOmbrePage(
            popup.page,
            url: url,
            title: popup.page.title ?? "",
            pageSpaceID: model.spaceID,
            isPrivate: popup.context.isPrivate,
            in: target
        )
        isMovedToTab = adopted
        popup.page.log(adopted ? "moved from Little Ombre to a tab" : "Little Ombre opened again in a tab")
        window.close()
        browserWindow?.makeKeyAndOrderFront(nil)
    }

    /// Goes to what was typed in the bar: an address, or a search with the
    /// space's engine.
    func navigate(to text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let url = constructURL(from: input).flatMap { $0.isFileURL ? nil : $0 }
            ?? SearchEngineService().searchURL(for: input, containerId: model.spaceID)
        guard let url else { return }
        popup.page.load(URLRequest(url: url))
        window.makeFirstResponder(popup.page.webView)
    }

    // MARK: - Window

    /// The page's permission prompt, at the top of the page.
    private func showPrompt(_ request: SitePermissionRequest?) {
        promptView?.removeFromSuperview()
        promptView = nil
        guard let request, let content = window.contentView else { return }
        let prompt = NSHostingView(rootView: SitePermissionPromptView(
            request: request,
            isPrivate: popup.context.isPrivate
        ) { [weak popup] granted, remember in
            popup?.answerPermissionRequest(granted: granted, remember: remember)
        })
        prompt.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(prompt)
        NSLayoutConstraint.activate([
            prompt.topAnchor.constraint(equalTo: content.topAnchor, constant: LittleOmbreBar.height + 12),
            prompt.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        ])
        promptView = prompt
    }

    func windowWillClose(_ notification: Notification) {
        observations.removeAll()
        popup.pageDidChange = nil
        popup.closeWindow = nil
        if !isMovedToTab {
            WebExtensionsHub.pageClosed(popup.page)
            popup.close()
        }
        Self.openWindows.remove(self)
        BrowserPopupWindow.closePopups(openedFrom: window)
    }
}

/// Little Ombre's window: ⌘O opens its page in Ombre, ⌘L goes to its address.
final class LittleOmbreNSWindow: NSWindow {
    weak var owner: LittleOmbreWindow?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "o":
                owner?.openInOmbre()
                return true
            case "l":
                owner?.model.focusAddress()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// What Little Ombre's bar shows and asks for.
@MainActor
final class LittleOmbreModel: ObservableObject {
    let popup: PopupPage
    /// The space whose data the page uses.
    let spaceID: UUID
    weak var owner: LittleOmbreWindow?
    /// Changes when the address field is to take the focus (⌘L, an empty
    /// Little Ombre).
    @Published private(set) var addressFocusRequest = 0

    init(popup: PopupPage, spaceID: UUID) {
        self.popup = popup
        self.spaceID = spaceID
    }

    func focusAddress() {
        addressFocusRequest += 1
    }
}
