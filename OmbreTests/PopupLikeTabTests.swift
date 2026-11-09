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
                defer { popup.popup.closeWindow?() }

                #expect(popup.popup.context.spaceID == tab.container.id)
                #expect(popup.popup.context.isPrivate == tab.isPrivate)
                #expect(popup.popup.page.delegate != nil)
                #expect(popup.popup.page !== tab.browserPage)
                // Its own content controller, not the opener's.
                #expect(
                    popup.popup.page.webView.configuration.userContentController
                        !== tab.browserPage?.webView.configuration.userContentController
                )
            }
        }

        @Test func permissionIsAskedInThePopupAndRemembered() async throws {
            try await TabManagerTestWindow.run { window in
                let (_, popup) = try await openPopup(in: window)
                let page = popup.popup.page
                defer {
                    popup.popup.closeWindow?()
                    SitePermissionStore.shared.removeAll(in: popup.popup.context.spaceID)
                }
                let delegate = try #require(page.delegate)

                var notifications: BrowserPermissionDecision?
                delegate.browserPage(page, requestPermission: .notifications, origin: site) { notifications = $0 }
                #expect(notifications == .deny)

                var camera: BrowserPermissionDecision?
                delegate.browserPage(page, requestPermission: .camera, origin: site) { camera = $0 }
                #expect(popup.popup.permissionRequest != nil)
                popup.popup.answerPermissionRequest(granted: true, remember: true)

                #expect(camera == .grant)
                #expect(delegate.browserPage(page, queryPermission: .camera, origin: site) == .grant)
            }
        }

        @Test func closingThePopupRefusesItsPrompt() async throws {
            try await TabManagerTestWindow.run { window in
                let (_, popup) = try await openPopup(in: window)
                let page = popup.popup.page
                let delegate = try #require(page.delegate)
                var camera: BrowserPermissionDecision?
                delegate.browserPage(page, requestPermission: .camera, origin: site) { camera = $0 }

                delegate.browserPageDidClose(page)

                #expect(camera == .deny)
                #expect(BrowserPopupWindow.popup(showing: page.webView) == nil)
            }
        }

        /// A `target="_blank"` link in a popup opens another popup window,
        /// in the same space.
        @Test func linkToANewWindowOpensAnotherPopup() async throws {
            try await TabManagerTestWindow.run { window in
                let (_, popup) = try await openPopup(in: window)
                defer { popup.popup.closeWindow?() }
                let page = popup.popup.page
                let delegate = try #require(page.delegate)
                let configuration = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)

                let webView = try #require(delegate.browserPage(
                    page, linkedPageWith: configuration, for: site, disposition: .foreground
                ))
                let second = try #require(BrowserPopupWindow.popup(showing: webView))
                defer { second.popup.closeWindow?() }

                #expect(second.popup.context.spaceID == popup.popup.context.spaceID)
            }
        }

        /// Its downloads still have somewhere to go once its tab is closed.
        @Test func downloadsOutliveTheOpenerTab() async throws {
            try await TabManagerTestWindow.run { window in
                let (tab, popup) = try await openPopup(in: window)
                defer { popup.popup.closeWindow?() }
                let downloads = tab.downloadManager ?? window.tabManager.downloadManager

                window.tabManager.closeTab(tab: tab)

                #expect(popup.popup.context.downloadManager === downloads)
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
