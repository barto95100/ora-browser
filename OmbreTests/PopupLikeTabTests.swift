import AppKit
import Foundation
@testable import Ombre
import Testing
@preconcurrency import WebKit

extension TabManagerTests {
    /// A popup's page behaves like a tab of its space: its own page and
    /// delegate, site permissions, `window.close()`, downloads once its tab
    /// is gone.
    @MainActor
    struct PopupLikeTab {
        private let site = URL(string: "https://login.example")

        /// Before: the popup was a bare web view with the opener's scripts
        /// and handlers, and no permissions, uploads or logins.
        @Test func popupIsAPageOfTheTabsSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let (tab, popup) = try await openPopup(in: window)
                defer { popup.popupPage.closeWindow?() }

                #expect(popup.popupPage.context.spaceID == tab.container.id)
                #expect(popup.popupPage.context.isPrivate == tab.isPrivate)
                #expect(popup.popupPage.page.delegate != nil)
                #expect(popup.popupPage.page !== tab.browserPage)
                // Its own content controller, not the opener's.
                #expect(
                    popup.popupPage.page.webView.configuration.userContentController
                        !== tab.browserPage?.webView.configuration.userContentController
                )
            }
        }

        @Test func permissionIsAskedInThePopupAndRemembered() async throws {
            try await TabManagerTestWindow.run { window in
                let (_, popup) = try await openPopup(in: window)
                let page = popup.popupPage.page
                defer {
                    popup.popupPage.closeWindow?()
                    SitePermissionStore.shared.removeAll(in: popup.popupPage.context.spaceID)
                }
                let delegate = try #require(page.delegate)

                var notifications: BrowserPermissionDecision?
                delegate.browserPage(page, requestPermission: .notifications, origin: site) { notifications = $0 }
                #expect(notifications == .deny)
                #expect(delegate.browserPage(page, queryPermission: .notifications, origin: site) == .deny)

                var camera: BrowserPermissionDecision?
                delegate.browserPage(page, requestPermission: .camera, origin: site) { camera = $0 }
                #expect(popup.popupPage.permissionRequest != nil)
                popup.popupPage.answerPermissionRequest(granted: true, remember: true)

                #expect(camera == .grant)
                #expect(delegate.browserPage(page, queryPermission: .camera, origin: site) == .grant)
            }
        }

        @Test func closingThePopupRefusesItsPrompt() async throws {
            try await TabManagerTestWindow.run { window in
                let (_, popup) = try await openPopup(in: window)
                let page = popup.popupPage.page
                let delegate = try #require(page.delegate)
                var camera: BrowserPermissionDecision?
                delegate.browserPage(page, requestPermission: .camera, origin: site) { camera = $0 }

                delegate.browserPageDidClose(page)

                #expect(camera == .deny)
                #expect(BrowserPopupWindow.popup(showing: page.webView) == nil)
            }
        }

        /// A link to a new window (`target="_blank"`, "Open Link in New Tab")
        /// opens a tab linked to the popup, beside its tab; once that tab is
        /// closed, another popup window in the same space.
        @Test func linkToANewWindowOpensATabThenAPopup() async throws {
            try await TabManagerTestWindow.run { window in
                let (tab, popup) = try await openPopup(in: window)
                defer { popup.popupPage.closeWindow?() }
                let page = popup.popupPage.page
                let delegate = try #require(page.delegate)

                let first = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
                let tabView = try #require(delegate.browserPage(
                    page, linkedPageWith: first, for: site, disposition: .foreground
                ))
                #expect(window.tabManager.activeTab?.browserPage?.webView === tabView)
                #expect(BrowserPopupWindow.popup(showing: tabView) == nil)

                window.tabManager.closeTab(tab: tab)
                let second = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
                let popupView = try #require(delegate.browserPage(
                    page, linkedPageWith: second, for: site, disposition: .foreground
                ))
                let other = try #require(BrowserPopupWindow.popup(showing: popupView))
                defer { other.popupPage.closeWindow?() }
                #expect(other.popupPage.context.spaceID == popup.popupPage.context.spaceID)
            }
        }

        /// Its downloads still have somewhere to go once its tab is closed.
        @Test func downloadsOutliveTheOpenerTab() async throws {
            try await TabManagerTestWindow.run { window in
                let (tab, popup) = try await openPopup(in: window)
                defer { popup.popupPage.closeWindow?() }
                let downloads = tab.downloadManager ?? window.tabManager.downloadManager

                window.tabManager.closeTab(tab: tab)

                #expect(popup.popupPage.context.downloadManager === downloads)
            }
        }

        private func openPopup(in window: TabManagerTestWindow) async throws -> (Tab, BrowserPopupWindow) {
            let tab = try await window.openLoaded("opener")
            let page = try #require(tab.browserPage)
            let delegate = try #require(tab.pageDelegate)
            let configuration = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
            let features = WKWindowFeatures()
            let webView = delegate.browserPage(
                page, openPopupWith: configuration, windowFeatures: features, openerOrigin: nil
            )
            let popupWebView = try #require(webView)
            let popup = try #require(BrowserPopupWindow.popup(showing: popupWebView))
            return (tab, popup)
        }
    }
}
