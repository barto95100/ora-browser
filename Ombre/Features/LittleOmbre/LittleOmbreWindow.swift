import AppKit
import Combine
import SwiftData
import SwiftUI
@preconcurrency import WebKit

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
    /// Set through `attach(to:)`.
    weak var browserWindow: NSWindow?
    /// What becomes of the browser window it hid (made only to hand over
    /// its link) when it closes; see `LittleOmbreWindow+BrowserWindow.swift`.
    var hiddenBrowserWindow: HiddenBrowserWindow?
    /// The page went to a tab: not torn down with the window.
    private var isMovedToTab = false
    private var isClosed = false
    private var observations: Set<AnyCancellable> = []

    static func isLittleOmbreWindow(_ window: NSWindow) -> Bool {
        openWindows.contains { $0.window === window }
    }

    /// Closes the Little Ombres opened from `tabManager`'s window (it closes:
    /// they use its spaces or its private session).
    static func closeAll(from tabManager: TabManager) {
        for little in openWindows where little.tabManager === tabManager || little.tabManager == nil {
            // Its browser window is going anyway: not closed or shown again.
            little.hiddenBrowserWindow = nil
            little.window.close()
        }
    }

    /// Closes the Little Ombres of a space being deleted (they use its data).
    static func closeAll(inSpace spaceID: UUID) {
        for little in openWindows where little.model.spaceID == spaceID {
            little.window.close()
        }
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
        popup.enablePasswords()
        let little = LittleOmbreWindow(popup: popup, tabManager: tabManager, space: space)
        little.attach(to: browserWindow)
        little.show()
        if let url {
            page.load(URLRequest(url: url))
        } else {
            // Once the bar is on screen (the page took the focus on show).
            DispatchQueue.main.async { little.model.focusAddress() }
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

        // The bar, then the page with its password suggestions and its
        // permission prompt over it, like a tab.
        let content = NSHostingView(rootView: LittleOmbreContent(popup: popup, model: model))
        content.sizingOptions = []
        window.contentView = content
        window.initialFirstResponder = popup.page.webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 420, height: 300)
        window.setAccessibilityLabel(String(localized: "Little Ombre"))
        popup.pageDidChange = { [weak self] in self?.updateTitle() }
        popup.opensLinkTab = { [weak self] url, configuration, disposition in
            self?.openLinkTab(url, configuration: configuration, disposition: disposition)
        }
        popup.closeWindow = { [weak self] in self?.window.close() }
        observeNavigationCommands()
    }

    /// Reload, Back and Forward from the menu, with their keys as the menu
    /// matches them (customized, and on any keyboard layout).
    private func observeNavigationCommands() {
        let commands: [(Notification.Name, @MainActor (LittleOmbreWindow) -> Void)] = [
            (.reloadPage, { $0.reload() }),
            (.goBack, { $0.goBack() }),
            (.goForward, { $0.goForward() })
        ]
        for (name, command) in commands {
            NotificationCenter.default.publisher(for: name, object: window)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        if let self { command(self) }
                    }
                }
                .store(in: &observations)
        }
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
        // The page joins the window on SwiftUI's first layout: the keyboard
        // goes to it then.
        DispatchQueue.main.async { [weak self] in
            guard let self, !model.isPageGone, window.firstResponder === window else { return }
            window.makeFirstResponder(popup.page.webView)
        }
    }

    /// The site as the title (never the page's own title alone).
    private func updateTitle() {
        let site = PopupTitle.title(for: popup.page.currentURL)
        window.title = site.isEmpty ? String(localized: "Little Ombre") : site
        window.subtitle = site.isEmpty ? "" : (popup.page.title ?? "")
    }

    // MARK: - Open in Ombre

    /// Whether the browser window it came from is still there.
    var canOpenInOmbre: Bool {
        tabManager != nil
    }

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
        // Once: the page is already on its way to a tab.
        guard !model.isPageGone, let tabManager, let url = popup.page.currentURL ?? popup.address,
              let target = space ?? spaces.first(where: { $0.id == model.spaceID }) ?? tabManager.activeContainer
        else { return }
        popup.sheets.dismiss()
        popup.cancelPermissionRequest()
        // The tab offers the passwords from now on.
        popup.disablePasswords()
        // Little Ombre lets go of the page first; the tab takes it on the
        // next pass (at once, Little Ombre's view could take it back).
        model.isPageGone = true
        DispatchQueue.main.async { [weak self, weak tabManager] in
            // Closed meanwhile (its page torn down): nothing to move.
            guard let self, !isClosed else { return }
            guard let tabManager else {
                model.isPageGone = false
                return
            }
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
            // The page's popups ("Sign in with…") go on with it, in the tab's window.
            if adopted { BrowserPopupWindow.movePopups(openedFrom: window, to: browserWindow) }
            // Before closing: a browser window it hid stays, shown.
            showBrowserWindow()
            window.close()
            if !TestHost.isActive { browserWindow?.makeKeyAndOrderFront(nil) }
        }
    }

    /// A link of its page opening a new window: a tab of its space in the
    /// browser window it came from, shown in front (unless in the
    /// background: then just behind), like Little Arc; Little Ombre stays. None (a popup
    /// window then) once that window or its space is gone.
    func openLinkTab(
        _ url: URL?,
        configuration: WKWebViewConfiguration?,
        disposition: BrowserNewTabDisposition
    ) -> WKWebView? {
        guard let tab = tabManager?.openLittleOmbreLink(
            url, from: popup, configuration: configuration, disposition: disposition
        ) else { return nil }
        if disposition == .background {
            // Behind Little Ombre: the tab is there, the page stays in front.
            showBrowserWindowBehind()
        } else {
            showBrowserWindow()
        }
        return tab.browserPage?.webView
    }

    /// Back, forward and reload, from the bar and the keys.
    func goBack() {
        popup.page.goBack()
    }

    func goForward() {
        popup.page.goForward()
    }

    func reload() {
        popup.page.reload()
    }

    /// The keyboard goes back to the page (Escape in the address field).
    func focusPage() {
        window.makeFirstResponder(popup.page.webView)
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

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        observations.removeAll()
        popup.pageDidChange = nil
        popup.closeWindow = nil
        popup.opensLinkTab = nil
        if !isMovedToTab {
            WebExtensionsHub.pageClosed(popup.page)
            popup.close()
        }
        Self.openWindows.remove(self)
        BrowserPopupWindow.closePopups(openedFrom: window)
        releaseHiddenBrowserWindow()
    }
}

/// What Little Ombre's own keys do. Reload, Back and Forward come from the
/// menu (see `observeNavigationCommands`).
enum LittleOmbreKey: Equatable {
    case openInOmbre
    case focusAddress

    /// The browser window's shortcuts for the same things, as customized
    /// (Settings › Shortcuts): "Open Peek in New Tab" (⌘O) opens the page in
    /// Ombre, as it does for Peek. Their menu items do nothing here (no
    /// Peek, no address bar of a browser window): matched by Little Ombre.
    static let shortcuts: [(key: LittleOmbreKey, shortcut: KeyboardShortcutDefinition)] = [
        (.openInOmbre, KeyboardShortcuts.Navigation.openPeekInNewTab),
        (.focusAddress, KeyboardShortcuts.Address.focus)
    ]

    /// The key `chord` is, with the shortcuts as they are now.
    @MainActor
    static func key(
        for chord: KeyChord,
        chord current: @MainActor (KeyboardShortcutDefinition) -> KeyChord = { $0.currentChord }
    ) -> LittleOmbreKey? {
        shortcuts.first { current($0.shortcut).isSameKeys(as: chord) }?.key
    }
}

/// Little Ombre's window: "Open Peek in New Tab" (⌘O) opens its page in
/// Ombre and "Focus Address Bar" (⌘L) goes to its address, with the browser
/// window's shortcuts as customized.
final class LittleOmbreNSWindow: NSWindow {
    weak var owner: LittleOmbreWindow?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let owner, let chord = KeyChord(fromEvent: event), let key = LittleOmbreKey.key(for: chord) {
            switch key {
            case .openInOmbre: owner.openInOmbre()
            case .focusAddress: owner.model.focusAddress()
            }
            return true
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
    /// The page is going to a tab: Little Ombre no longer shows it.
    @Published var isPageGone = false

    init(popup: PopupPage, spaceID: UUID) {
        self.popup = popup
        self.spaceID = spaceID
    }

    func focusAddress() {
        addressFocusRequest += 1
    }
}

/// Little Ombre's window: its bar, then its page, with the page's password
/// suggestions and permission prompt over it.
struct LittleOmbreContent: View {
    @ObservedObject var popup: PopupPage
    @ObservedObject var model: LittleOmbreModel

    var body: some View {
        VStack(spacing: 0) {
            LittleOmbreBar(popup: popup, model: model)
            ZStack(alignment: .top) {
                if model.isPageGone {
                    Color.clear
                } else {
                    LittlePageView(page: popup.page)
                        .overlay(alignment: .topLeading) {
                            if let trigger = popup.passwordTriggerOverlayState {
                                PasswordAutofillTriggerView(overlay: trigger, coordinator: popup.passwordCoordinator)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let overlay = popup.passwordOverlayState {
                                PasswordAutofillOverlayView(overlay: overlay, coordinator: popup.passwordCoordinator)
                            }
                        }
                }
                if let request = popup.permissionRequest {
                    SitePermissionPromptView(
                        request: request,
                        isPrivate: popup.context.isPrivate
                    ) { granted, remember in
                        popup.answerPermissionRequest(granted: granted, remember: remember)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}

/// The page itself, in the window (as a tab's, without the tab's managers).
private struct LittlePageView: NSViewRepresentable {
    let page: BrowserPage

    func makeNSView(context: Context) -> BrowserPageHostView {
        let host = BrowserPageHostView(frame: .zero)
        host.host(contentView: page.contentView)
        host.cancelOperationHandler = BrowserPageView.cancelOperationHandler(for: page)
        return host
    }

    func updateNSView(_ host: BrowserPageHostView, context: Context) {
        host.host(contentView: page.contentView)
    }
}
