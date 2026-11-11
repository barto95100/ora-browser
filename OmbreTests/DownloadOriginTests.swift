import AppKit
import Foundation
@testable import Ombre
import Testing
@preconcurrency import WebKit

extension TabManagerTests {
    /// A tab, Peek or popup only opened for a file asks for the site the link
    /// was clicked on, not the file's server (often a file host).
    @MainActor
    struct DownloadOrigin {
        private let page = URL(string: "https://news.example/article")
        private let opener = URL(string: "https://blog.example/post")
        private let file = URL(string: "https://cdn.files.example/report.pdf")

        @Test func siteIsThePageShownElseTheOpenerElseTheFile() {
            #expect(DownloadPermission.site(shown: page, opener: opener, file: file) == page)
            #expect(DownloadPermission.site(shown: nil, opener: opener, file: file) == opener)
            #expect(DownloadPermission.site(shown: nil, opener: nil, file: file) == file)
            // A blank or local page names no site: the file's site is asked,
            // never nothing (which would let it through unasked).
            let blank = URL(string: "about:blank")
            let local = URL(string: "file:///Users/me/page.html")
            #expect(DownloadPermission.site(shown: blank, opener: local, file: file) == file)
            #expect(DownloadPermission.site(shown: blank, opener: opener, file: file) == opener)
        }

        /// ⌘-click and `target="_blank"` links: the new tab knows the page
        /// its link was on.
        @Test func linkTabsRememberTheOpenerPage() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("opener")
                let shown = tab.shownURL
                let file = try #require(file)

                let background = try #require(window.tabManager.openLinkTab(file, from: tab, disposition: .background))
                #expect(background.openerURL == shown)
                // Going elsewhere from the address bar: no longer the link's doing.
                background.loadURL(shown.absoluteString)
                #expect(background.openerURL == nil)

                let configuration = try #require(
                    tab.browserPage?.webView.configuration.copy() as? WKWebViewConfiguration
                )
                let shownNow = tab.shownURL
                let webView = try #require(window.tabManager.openLinkedTab(
                    url: file, from: tab, configuration: configuration, disposition: .foreground
                ))
                let linked = window.tabManager.activeTab
                #expect(linked?.browserPage?.webView === webView)
                #expect(linked?.openerURL == shownNow)
            }
        }

        /// A popup knows the page that opened it, and the tabs it opens know
        /// the popup's page.
        @Test func popupsRememberTheOpenerPage() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("opener")
                let page = try #require(tab.browserPage)
                let delegate = try #require(tab.pageDelegate)
                let configuration = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
                let popupView = try #require(delegate.browserPage(
                    page, openPopupWith: configuration, windowFeatures: WKWindowFeatures(), openerOrigin: opener
                ))
                let popup = try #require(BrowserPopupWindow.popup(showing: popupView))
                defer { popup.popupPage.closeWindow?() }
                let shown = tab.shownURL
                #expect(popup.popupPage.openerURL == shown)

                // The popup shows nothing yet: its tabs get its opener's page.
                let popupPage = popup.popupPage.page
                let popupDelegate = try #require(popupPage.delegate)
                let file = try #require(file)
                popupDelegate.browserPage(popupPage, didRequestOpenInNewTab: file, disposition: .background)
                let opened = tab.container.tabs.first { $0.url == file }
                #expect(opened?.openerURL == shown)
            }
        }
    }
}
