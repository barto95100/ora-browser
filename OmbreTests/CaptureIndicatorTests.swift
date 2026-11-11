import AppKit
import Foundation
@testable import Ombre
import Testing
@preconcurrency import WebKit

extension TabManagerTests {
    /// Peek and popups show the camera and microphone their page uses, like a
    /// tab's address bar (and let them be paused).
    @MainActor
    struct CaptureIndicator {
        private let capturing = BrowserMediaCaptureState(camera: .active, microphone: .muted)

        @Test func peekFollowsItsPagesCapture() async throws {
            try await TabManagerTestWindow.run { window in
                let opener = try await window.openLoaded("opener")
                opener.openPeek(TabManagerTestWindow.url("peek"))
                let peek = try #require(window.tabManager.peek)
                defer { window.tabManager.closePeek() }
                let delegate = try #require(peek.page.delegate)

                delegate.browserPage(peek.page, didChangeMediaCaptureState: capturing)
                #expect(peek.mediaCaptureState == capturing)

                delegate.browserPage(peek.page, didChangeMediaCaptureState: BrowserMediaCaptureState())
                #expect(!peek.mediaCaptureState.isCapturing)
            }
        }

        @Test func popupFollowsItsPagesCapture() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("opener")
                let page = try #require(tab.browserPage)
                let delegate = try #require(tab.pageDelegate)
                let configuration = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
                let popupView = try #require(delegate.browserPage(
                    page, openPopupWith: configuration, windowFeatures: WKWindowFeatures(), openerOrigin: nil
                ))
                let popup = try #require(BrowserPopupWindow.popup(showing: popupView))
                defer { popup.popupPage.closeWindow?() }
                let popupPage = popup.popupPage.page
                let popupDelegate = try #require(popupPage.delegate)

                popupDelegate.browserPage(popupPage, didChangeMediaCaptureState: capturing)
                #expect(popup.popupPage.mediaCaptureState == capturing)
            }
        }
    }
}
