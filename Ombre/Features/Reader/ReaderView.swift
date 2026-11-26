import AppKit
import SwiftUI
import WebKit

/// Where a page's reader mode is: its space's notes, unless private.
struct ReaderContext {
    let isPrivate: Bool
    let spaceID: UUID?
    let spaceName: String?

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
    @State private var status: String?
    @State private var isSaving = false

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
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .overlay(alignment: .bottom) {
            if let status {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: status)
    }

    private var controls: some View {
        HStack(spacing: 2) {
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
        show(String(localized: "Saving the article…"), for: nil)
        ReaderNote.save(article, in: spaceID, named: spaceName, downloadingWith: webView) { note in
            isSaving = false
            if note != nil {
                show(String(localized: "Saved to the notes of \(spaceName)"), for: 2.5)
            } else {
                show(String(localized: "The article couldn’t be saved"), for: 3)
            }
        }
    }

    private func show(_ text: String, for seconds: Double?) {
        status = text
        guard let seconds else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if status == text { status = nil }
        }
    }
}

/// Theme, text size, column width and font of reader mode.
struct ReaderStyleView: View {
    @ObservedObject var settings: ReaderSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(ReaderSettings.Theme.allCases) { theme in
                    themeButton(theme)
                }
            }
            HStack(spacing: 8) {
                Button { settings.makeTextSmaller() } label: {
                    Image(systemName: "textformat.size.smaller").frame(width: 40)
                }
                .disabled(!settings.canMakeTextSmaller)
                .help("Smaller Text")
                .accessibilityLabel(String(localized: "Smaller Text"))
                Button { settings.resetTextSize() } label: {
                    Text(verbatim: "\(settings.size)").monospacedDigit().frame(minWidth: 28)
                }
                .help("Default Size")
                Button { settings.makeTextBigger() } label: {
                    Image(systemName: "textformat.size.larger").frame(width: 40)
                }
                .disabled(!settings.canMakeTextBigger)
                .help("Bigger Text")
                .accessibilityLabel(String(localized: "Bigger Text"))
            }
            Picker("Width", selection: $settings.width) {
                ForEach(ReaderSettings.Width.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Font", selection: $settings.font) {
                ForEach(ReaderSettings.Font.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func themeButton(_ theme: ReaderSettings.Theme) -> some View {
        let selected = settings.theme == theme
        return Button { settings.theme = theme } label: {
            VStack(spacing: 4) {
                ZStack {
                    if theme == .automatic {
                        Circle().fill(LinearGradient(
                            colors: [
                                Color(nsColor: ReaderDocument.background(for: .light, isDark: false)),
                                Color(nsColor: ReaderDocument.background(for: .dark, isDark: true))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    } else {
                        Circle().fill(Color(nsColor: ReaderDocument.background(for: theme, isDark: false)))
                    }
                    Circle().strokeBorder(
                        selected ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: selected ? 2.5 : 1
                    )
                }
                .frame(width: 34, height: 34)
                Text(theme.title).font(.system(size: 10))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - The article's web view

/// Keeps the reader's web view across updates.
@MainActor
final class ReaderWebViewCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    private(set) var webView: ReaderPageWebView?
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
