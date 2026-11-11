import AppKit
import Foundation
@testable import Ombre
import Testing
@preconcurrency import WebKit

/// A popup shows its full address and its security, like Safari (MOT-10).
@MainActor
struct PopupAddressBarTests {
    @Test func securityFollowsTheSchemeAndTheContent() throws {
        let https = try #require(URL(string: "https://login.example/oauth?x=1"))
        let http = try #require(URL(string: "http://login.example/"))
        let blank = try #require(URL(string: "about:blank"))
        #expect(PageSecurity.of(https, hasOnlySecureContent: true) == .secure)
        // An image or script over HTTP in a secure page: the lock goes.
        #expect(PageSecurity.of(https, hasOnlySecureContent: false) == .notSecure)
        #expect(PageSecurity.of(http, hasOnlySecureContent: false) == .notSecure)
        #expect(PageSecurity.of(blank, hasOnlySecureContent: false) == .local)
        #expect(PageSecurity.of(nil, hasOnlySecureContent: false) == .local)
    }

    /// The site is shown apart (never cut at its domain), without a user
    /// name that could pass for another site.
    @Test func siteIsShownApartFromTheRest() throws {
        let long = try #require(URL(string: "https://accounts.example.com.attacker.example/a/b?x=1#top"))
        let display = PopupDisplayAddress(long)
        #expect(display.site == "accounts.example.com.attacker.example")
        #expect(display.rest == "/a/b?x=1#top")

        let userInfo = try #require(URL(string: "https://accounts.example.com@evil.example:8443/"))
        #expect(PopupDisplayAddress(userInfo).site == "evil.example:8443")
        #expect(PopupDisplayAddress(userInfo).rest.isEmpty)

        let blank = try #require(URL(string: "about:blank"))
        #expect(PopupDisplayAddress(blank).site == "about:blank")
    }
}

extension TabManagerTests {
    @MainActor
    struct PopupAddress {
        /// The bar shows the page's full address once loaded, and is part of
        /// the window, over the page.
        @Test func popupShowsItsAddress() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("opener")
                let page = try #require(tab.browserPage)
                let delegate = try #require(tab.pageDelegate)
                let configuration = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
                let features = WKWindowFeatures()
                let popupView = try #require(delegate.browserPage(
                    page, openPopupWith: configuration, windowFeatures: features, openerOrigin: nil
                ))
                let popup = try #require(BrowserPopupWindow.popup(showing: popupView))
                defer { popup.popupPage.closeWindow?() }
                await window.waitUntil("opener loaded") { page.currentURL?.host() != nil }
                let url = try #require(page.currentURL)

                popup.popupPage.page.load(URLRequest(url: url))
                await window.waitUntil("popup address") { popup.popupPage.address == url }

                #expect(popup.popupPage.address == url)
                // The bar sits over the page, not on it.
                let pageView = popup.popupPage.page.contentView
                let content = try #require(pageView.superview)
                #expect(pageView.frame.maxY == content.bounds.height - PopupAddressBar.height)
                let bar = try #require(content.subviews
                    .first { $0 !== pageView && $0.frame.minY == pageView.frame.maxY })
                #expect(bar.frame.height == PopupAddressBar.height)
                // The local test server is HTTP.
                #expect(popup.popupPage.security == .notSecure)
            }
        }
    }
}
