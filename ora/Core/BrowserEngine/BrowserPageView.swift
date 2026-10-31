import AppKit
import SwiftUI

final class BrowserPageHostView: NSView {
    private(set) weak var hostedContentView: NSView?

    /// Views WebKit adds next to a page, in its superview: the docked Web
    /// Inspector. They must follow their page when it moves to another host
    /// (switching tabs), or the inspector's space stays blank.
    private static let companionViews = NSMapTable<NSView, NSMutableArray>.weakToStrongObjects()

    /// Called when Escape reaches the host without being handled by the page.
    var cancelOperationHandler: (() -> Void)?

    /// Lays the page out beside the host, outside the window, at its normal
    /// size (pages parked during Picture in Picture).
    var keepsContentOutsideWindow = false {
        didSet { hostedContentView?.frame = contentFrame }
    }

    private var contentFrame: NSRect {
        guard keepsContentOutsideWindow else { return bounds }
        // Far enough to the left that no screen arrangement brings it under the mouse.
        return bounds.offsetBy(dx: -(bounds.width + 100_000), dy: 0)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizesSubviews = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func host(contentView newContentView: NSView?) {
        let previousContentView = hostedContentView
        let isSameContentView = previousContentView === newContentView

        if isSameContentView, newContentView?.superview === self {
            return
        }

        let shouldRestoreFirstResponder = shouldTransferFirstResponder(from: previousContentView)

        // A view becoming the hosted page is no longer a companion of the previous one.
        if let previousContentView, let newContentView {
            Self.companionViews.object(forKey: previousContentView)?.remove(newContentView)
        }

        if isSameContentView {
            hostedContentView = nil
        } else {
            detachHostedContentView()
        }

        guard let newContentView else {
            refreshHostingLayout()
            return
        }

        configure(contentView: newContentView)

        if let previousHost = newContentView.superview as? BrowserPageHostView,
           previousHost !== self
        {
            previousHost.releaseHostedContentView(newContentView)
        }

        if newContentView.superview !== self {
            if newContentView.superview != nil {
                newContentView.removeFromSuperview()
            }
            addSubview(newContentView)
        }

        newContentView.frame = contentFrame
        hostedContentView = newContentView
        restoreCompanionViews(of: newContentView)

        needsLayout = true
        layoutSubtreeIfNeeded()
        newContentView.needsLayout = true
        newContentView.layoutSubtreeIfNeeded()
        newContentView.needsDisplay = true
        displayIfNeeded()

        if shouldRestoreFirstResponder {
            window?.makeFirstResponder(newContentView)
        }
    }

    override func layout() {
        super.layout()
        hostedContentView?.frame = contentFrame
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let page = hostedContentView, subview !== page else { return }
        let companions = Self.companions(of: page)
        if !companions.contains(subview) {
            companions.add(subview)
        }
    }

    override func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
        // Removed while on screen: closed or undocked by the user. Off screen,
        // WebKit only takes it away because its page left the window (tab
        // switch): keep it to put it back with the page.
        guard window != nil, let page = hostedContentView, subview !== page else { return }
        Self.companions(of: page).remove(subview)
    }

    private static func companions(of page: NSView) -> NSMutableArray {
        if let companions = companionViews.object(forKey: page) {
            return companions
        }
        let companions = NSMutableArray()
        companionViews.setObject(companions, forKey: page)
        return companions
    }

    /// Puts back the views WebKit had placed next to this page in its previous host.
    private func restoreCompanionViews(of page: NSView) {
        guard let companions = Self.companionViews.object(forKey: page) else { return }
        for case let companion as NSView in companions.copy() as? [Any] ?? [] where companion.superview !== self {
            addSubview(companion, positioned: .below, relativeTo: page)
        }
    }

    /// Escape that the page does not handle travels up the responder chain as
    /// `cancelOperation(_:)`. Left alone it reaches the window, which exits full
    /// screen (the-ora/browser#179), so it stops here. Pages still receive the
    /// key first (closing their own dialogs, leaving video full screen...).
    override func cancelOperation(_ sender: Any?) {
        cancelOperationHandler?()
    }

    private func configure(contentView: NSView) {
        contentView.wantsLayer = true
        contentView.autoresizingMask = [.width, .height]
        contentView.layer?.isOpaque = true
        contentView.layer?.drawsAsynchronously = true
    }

    private func detachHostedContentView() {
        guard let hostedContentView else {
            return
        }

        // Cleared first: the companions removed below stay recorded for their page.
        self.hostedContentView = nil

        if hostedContentView.superview === self {
            hostedContentView.removeFromSuperview()
        }
        for case let companion as NSView in Self.companions(of: hostedContentView) where companion.superview === self {
            companion.removeFromSuperview()
        }
    }

    private func releaseHostedContentView(_ contentView: NSView) {
        guard hostedContentView === contentView else {
            return
        }

        detachHostedContentView()
        refreshHostingLayout()
    }

    private func refreshHostingLayout() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        displayIfNeeded()
    }

    private func shouldTransferFirstResponder(from previousContentView: NSView?) -> Bool {
        guard let previousContentView,
              let firstResponder = window?.firstResponder as? NSView
        else {
            return false
        }

        return firstResponder === previousContentView || firstResponder.isDescendant(of: previousContentView)
    }
}

struct BrowserPageView: NSViewRepresentable {
    let page: BrowserPage
    /// Escape not handled by the page; replaces stopping a loading page
    /// (Peek closes with it, even while its page loads).
    var onEscape: (() -> Void)?
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var privacyMode: PrivacyMode

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tabManager: tabManager,
            historyManager: historyManager,
            privacyMode: privacyMode
        )
    }

    func makeNSView(context: Context) -> BrowserPageHostView {
        let hostView = BrowserPageHostView(frame: .zero)
        let contentView = page.contentView
        context.coordinator.update(page: page, contentView: contentView)
        hostView.host(contentView: contentView)
        hostView.cancelOperationHandler = onEscape ?? Self.cancelOperationHandler(for: page)
        return hostView
    }

    func updateNSView(_ nsView: BrowserPageHostView, context: Context) {
        let contentView = page.contentView
        context.coordinator.update(page: page, contentView: contentView)
        nsView.host(contentView: contentView)
        nsView.cancelOperationHandler = onEscape ?? Self.cancelOperationHandler(for: page)
    }

    /// Like Safari, Escape stops a page that is still loading, and leaves a
    /// loaded page alone.
    static func cancelOperationHandler(for page: some LoadingStoppable) -> () -> Void {
        { [weak page] in
            guard let page, page.isLoading else { return }
            page.stopLoading()
        }
    }

    final class Coordinator: NSObject {
        weak var tabManager: TabManager?
        weak var historyManager: HistoryManager?
        weak var privacyMode: PrivacyMode?
        private weak var page: BrowserPage?
        private var mouseEventMonitor: Any?
        private weak var contentView: NSView?

        init(
            tabManager: TabManager?,
            historyManager: HistoryManager?,
            privacyMode: PrivacyMode
        ) {
            self.tabManager = tabManager
            self.historyManager = historyManager
            self.privacyMode = privacyMode
            super.init()
            startMouseEventMonitoring()
        }

        deinit {
            if let monitor = mouseEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func update(page: BrowserPage, contentView: NSView) {
            self.page = page
            self.contentView = contentView
        }

        private func startMouseEventMonitoring() {
            mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
                guard let self,
                      let page = self.page,
                      let contentView = self.contentView,
                      // Each page view installs this app-wide monitor: only
                      // the page of the window that was clicked may react.
                      EventWindowScope.concerns(eventWindow: event.window, window: contentView.window),
                      self.isEventInContentView(event, contentView: contentView)
                else {
                    return event
                }

                switch event.buttonNumber {
                case 2:
                    self.handleMiddleClick(at: event.locationInWindow, contentView: contentView, page: page)
                    return nil
                case 3:
                    if page.canGoBack {
                        DispatchQueue.main.async {
                            page.goBack()
                        }
                    }
                    return nil
                case 4:
                    if page.canGoForward {
                        DispatchQueue.main.async {
                            page.goForward()
                        }
                    }
                    return nil
                default:
                    return event
                }
            }
        }

        private func handleMiddleClick(at location: NSPoint, contentView: NSView, page: BrowserPage) {
            let locationInContentView = contentView.convert(location, from: nil)
            guard locationInContentView.x.isFinite,
                  locationInContentView.y.isFinite,
                  locationInContentView.x >= 0,
                  locationInContentView.y >= 0
            else {
                return
            }

            let script = """
            (function() {
                var element = document.elementFromPoint(\(locationInContentView.x), \(locationInContentView.y));
                while (element && element.tagName !== 'A') {
                    element = element.parentElement;
                }
                return element ? element.href : null;
            })();
            """

            page.evaluateJavaScript(script) { [weak self, weak page] result, error in
                guard error == nil,
                      page != nil,
                      let urlString = result as? String,
                      let url = URL(string: urlString),
                      let tabManager = self?.tabManager,
                      let historyManager = self?.historyManager,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                else {
                    return
                }

                DispatchQueue.main.async {
                    _ = tabManager.openTab(
                        url: url,
                        historyManager: historyManager,
                        focusAfterOpening: false,
                        isPrivate: self?.privacyMode?.isPrivate ?? false
                    )
                }
            }
        }

        private func isEventInContentView(_ event: NSEvent, contentView: NSView) -> Bool {
            let locationInWindow = event.locationInWindow
            let locationInContentView = contentView.convert(locationInWindow, from: nil)
            return contentView.bounds.contains(locationInContentView)
        }
    }
}

/// A page that Escape can stop while it loads (see
/// `BrowserPageView.cancelOperationHandler(for:)`).
protocol LoadingStoppable: AnyObject {
    var isLoading: Bool { get }
    func stopLoading()
}

extension BrowserPage: LoadingStoppable {}
