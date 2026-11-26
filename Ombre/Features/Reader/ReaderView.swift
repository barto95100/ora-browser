import AppKit
import SwiftUI
import WebKit

/// Where a page's reader mode is: its space's notes, unless private.
struct ReaderContext {
    let isPrivate: Bool
    let spaceID: UUID?
    let spaceName: String?
    /// Shows a note just made, in the window's notes; nil: no "Open" button.
    var openNote: ((URL) -> Void)?

    /// The space's notes, never a private window's (they have none).
    var canSendToNote: Bool {
        !isPrivate && spaceID != nil && spaceName != nil
    }
}

/// Over the page while reader mode is on: the article, and its controls.
struct ReaderOverlay: View {
    let page: BrowserPage
    let context: ReaderContext

    var body: some View {
        if let article = page.reader.article {
            ReaderView(page: page, article: article, context: context)
                .transition(.opacity)
        }
    }
}

struct ReaderView: View {
    let page: BrowserPage
    let article: ReaderArticle
    let context: ReaderContext
    @ObservedObject private var settings = ReaderSettings.shared
    @StateObject private var coordinator = ReaderWebViewCoordinator()
    @State private var showsStyle = false
    @State private var showsContents = false
    @State private var status: Status?
    @State private var isSaving = false
    /// How far the window's title bar reaches over the article (hidden, but
    /// over the content): the buttons go below it.
    @State private var titleBarOverlap: CGFloat = 0
    @Environment(\.window) private var window

    private struct Status: Equatable {
        let text: String
        /// "Open": the note just made.
        var note: URL?
    }

    var body: some View {
        ReaderWebView(
            coordinator: coordinator,
            page: page,
            article: article,
            style: settings.style,
            onOpen: { url in
                page.reader.close(page)
                page.load(URLRequest(url: url))
            },
            onClose: { page.reader.close(page) }
        )
        .overlay(alignment: .topTrailing) {
            controls
                .padding(.top, 12 + titleBarOverlap)
                .padding(.trailing, 16)
        }
        .overlay(alignment: .bottom) {
            if let status { statusView(status) }
        }
        .animation(.easeOut(duration: 0.2), value: status)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measure(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in measure(frame) }
            }
        }
    }

    /// The window's title bar is hidden but stays over the top of the content
    /// (where the traffic lights are): how much of the article it covers.
    private func measure(_ frame: CGRect) {
        guard let window else { return }
        let titleBar = max(0, window.frame.height - window.contentLayoutRect.height)
        let overlap = max(0, titleBar - frame.minY)
        if overlap != titleBarOverlap { titleBarOverlap = overlap }
    }

    private func statusView(_ status: Status) -> some View {
        HStack(spacing: 10) {
            Text(status.text)
            if let note = status.note, let openNote = context.openNote {
                Button(String(localized: "reader.note.open", defaultValue: "Open")) {
                    self.status = nil
                    openNote(note)
                }
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 16)
        .transition(.opacity)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            if article.hasContents {
                controlButton("list.bullet", help: String(localized: "reader.contents", defaultValue: "Contents")) {
                    showsContents.toggle()
                }
                .popover(isPresented: $showsContents, arrowEdge: .bottom) {
                    ReaderContentsView(headings: article.headings) { heading in
                        showsContents = false
                        coordinator.scroll(to: heading.id, margin: 56 + titleBarOverlap)
                    }
                }
            }
            controlButton("textformat.size", help: String(localized: "Appearance")) { showsStyle.toggle() }
                .popover(isPresented: $showsStyle, arrowEdge: .bottom) {
                    ReaderStyleView(settings: settings)
                }
            if context.canSendToNote {
                controlButton("note.text.badge.plus", help: String(localized: "Send to a Note")) { sendToNote() }
                    .disabled(isSaving)
            }
            controlButton("xmark", help: String(localized: "Close Reader")) { page.reader.close(page) }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private func sendToNote() {
        guard let spaceID = context.spaceID, let spaceName = context.spaceName, let webView = coordinator.webView
        else { return }
        isSaving = true
        show(Status(text: String(localized: "Saving the article…")), for: nil)
        ReaderNote.save(article, in: spaceID, named: spaceName, downloadingWith: webView) { note in
            isSaving = false
            if let note {
                // Longer with its button: time to reach it.
                let opens = context.openNote != nil
                show(
                    Status(text: String(localized: "Saved to the notes of \(spaceName)"), note: note.url),
                    for: opens ? 6 : 2.5
                )
            } else {
                show(Status(text: String(localized: "The article couldn’t be saved")), for: 3)
            }
        }
    }

    private func show(_ shown: Status, for seconds: Double?) {
        status = shown
        guard let seconds else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if status == shown { status = nil }
        }
    }
}

// MARK: - The article's web view

/// Keeps the reader's web view across updates.
@MainActor
final class ReaderWebViewCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    private(set) var webView: ReaderPageWebView?
    private weak var reader: PageReader?
    var article: ReaderArticle?
    /// The style asked for, and the one the shown document has.
    var style: ReaderDocument.Style?
    private var shownStyle: ReaderDocument.Style?
    private var isLoaded = false
    var onOpen: ((URL) -> Void)?

    /// The reader's settings: JavaScript off; the page's data (a private
    /// window's stays in memory) and protections.
    static func configuration(
        dataStore: WKWebsiteDataStore,
        applicationName: String?,
        ruleLists: [WKContentRuleList]
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = applicationName
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.isElementFullscreenEnabled = false
        ruleLists.forEach(configuration.userContentController.add)
        return configuration
    }

    func makeWebView(for page: BrowserPage) -> ReaderPageWebView {
        if let webView { return webView }
        let configuration = Self.configuration(
            dataStore: page.webView.configuration.websiteDataStore,
            applicationName: page.webView.configuration.applicationNameForUserAgent,
            ruleLists: page.activeContentRuleLists
        )
        let webView = ReaderPageWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = page.webView.customUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.isHidden = true
        self.webView = webView
        reader = page.reader
        return webView
    }

    func show(_ article: ReaderArticle, style: ReaderDocument.Style) {
        guard let webView else { return }
        self.style = style
        if article != self.article {
            self.article = article
            isLoaded = false
            shownStyle = style
            webView.isHidden = true
            webView.loadHTMLString(ReaderDocument.html(for: article, style: style), baseURL: article.pageURL)
        } else {
            applyStyle()
        }
    }

    /// Once the document is there (a change asked while it loads waits for it).
    private func applyStyle() {
        guard isLoaded, let webView, let style, style != shownStyle else { return }
        shownStyle = style
        webView.evaluateJavaScript(ReaderDocument.applyScript(for: style), completionHandler: nil)
    }

    /// To one of the article's headings, in the reader (the page isn't asked).
    /// `margin`: room left above it (the buttons are there).
    func scroll(to anchor: String, margin: CGFloat) {
        guard let webView, anchor.hasPrefix("ombre-heading-"),
              anchor.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { return }
        // Not shown: the reader's own script.
        let script = """
        (() => { const heading = document.getElementById('\(anchor)'); if (!heading) return 0;
        const top = heading.getBoundingClientRect().top + window.scrollY - \(Int(margin));
        window.scrollTo({ top: Math.max(0, top), behavior: 'smooth' }); return 0; })()
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    enum Decision: Equatable {
        case allow, cancel, open(URL)
    }

    /// The reader shows its article only: a link opens in the page, a link
    /// to a part of the article goes there; nothing else loads.
    static func decision(
        for url: URL?,
        type: WKNavigationType,
        isMainFrame: Bool,
        pageURL: URL?
    ) -> Decision {
        guard isMainFrame else { return .cancel }
        if type == .other, url == pageURL || url?.absoluteString == "about:blank" { return .allow }
        if let url, let pageURL, url.fragment != nil, withoutFragment(url) == withoutFragment(pageURL) {
            return .allow
        }
        if type == .linkActivated, let url { return .open(url) }
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let decision = Self.decision(
            for: navigationAction.request.url,
            type: navigationAction.navigationType,
            isMainFrame: navigationAction.targetFrame?.isMainFrame != false,
            pageURL: article?.pageURL
        )
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case let .open(url):
            decisionHandler(.cancel)
            onOpen?(url)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.isHidden else { return }
        isLoaded = true
        applyStyle()
        webView.isHidden = false
        webView.window?.makeFirstResponder(webView)
        // Find looks in it from now on (its article loaded).
        reader?.webView = webView
    }

    static func withoutFragment(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url
    }
}

/// Esc closes reader mode, whatever has the keyboard in the article.
final class ReaderPageWebView: WKWebView {
    var onClose: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The view behind the article: its theme's color, so loading never
/// flashes; "Automatic" follows the Mac turning light or dark.
final class ReaderHostView: NSView {
    var theme: ReaderSettings.Theme = .automatic {
        didSet { updateColor() }
    }

    weak var webView: WKWebView?

    override var isFlipped: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private var color: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ReaderDocument.background(for: theme, isDark: isDark)
    }

    private func updateColor() {
        webView?.underPageBackgroundColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}

struct ReaderWebView: NSViewRepresentable {
    let coordinator: ReaderWebViewCoordinator
    let page: BrowserPage
    let article: ReaderArticle
    let style: ReaderDocument.Style
    let onOpen: (URL) -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> ReaderHostView {
        let host = ReaderHostView(frame: .zero)
        let webView = coordinator.makeWebView(for: page)
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        host.webView = webView
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        updateNSView(host, context: context)
        return host
    }

    func updateNSView(_ host: ReaderHostView, context: Context) {
        host.theme = style.theme
        coordinator.webView?.onClose = onClose
        coordinator.onOpen = onOpen
        coordinator.show(article, style: style)
    }
}
