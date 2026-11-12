import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// Peek's page behaves like a tab of its space: site permissions, dialogs,
    /// blocked content.
    @MainActor
    struct PeekLikeTab {
        private let site = URL(string: "https://camera.example")

        @Test func savedPermissionOfTheSpaceApplies() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                defer {
                    window.tabManager.closePeek()
                    SitePermissionStore.shared.removeAll(in: peek.spaceID)
                }
                let origin = try #require(site.flatMap(SiteOrigin.init(url:)))
                SitePermissionStore.shared.setState(
                    .allow, for: [.camera], origin: origin, in: peek.spaceID, isPrivate: peek.isPrivate
                )
                let delegate = try #require(peek.page.delegate)

                var decision: BrowserPermissionDecision?
                delegate.browserPage(peek.page, requestPermission: .camera, origin: site) { decision = $0 }

                #expect(decision == .grant)
                #expect(peek.permissionRequest == nil)
                #expect(delegate.browserPage(peek.page, queryPermission: .camera, origin: site) == .grant)
            }
        }

        /// Before: Peek denied every permission without asking.
        @Test func undecidedPermissionIsAskedInPeekAndRemembered() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                defer { SitePermissionStore.shared.removeAll(in: peek.spaceID) }
                defer { window.tabManager.closePeek() }
                let delegate = try #require(peek.page.delegate)

                var decision: BrowserPermissionDecision?
                delegate.browserPage(peek.page, requestPermission: .camera, origin: site) { decision = $0 }
                #expect(decision == nil)
                #expect(peek.permissionRequest != nil)

                peek.answerPermissionRequest(granted: true, remember: true)

                #expect(decision == .grant)
                #expect(peek.permissionRequest == nil)
                #expect(delegate.browserPage(peek.page, queryPermission: .camera, origin: site) == .grant)
            }
        }

        @Test func closingPeekDeniesItsPrompt() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                defer { SitePermissionStore.shared.removeAll(in: peek.spaceID) }
                let delegate = try #require(peek.page.delegate)
                var decision: BrowserPermissionDecision?
                delegate.browserPage(peek.page, requestPermission: .microphone, origin: site) { decision = $0 }

                window.tabManager.closePeek()

                #expect(decision == .deny)
                #expect(peek.permissionRequest == nil)
            }
        }

        /// Peek opened as a tab: its waiting prompt is refused (the tab asks
        /// again if the page does), and a preview never gets notifications.
        @Test func promptGoesWhenPeekBecomesATabAndNotificationsAreRefused() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                defer { SitePermissionStore.shared.removeAll(in: peek.spaceID) }
                let delegate = try #require(peek.page.delegate)
                var notifications: BrowserPermissionDecision?
                delegate.browserPage(peek.page, requestPermission: .notifications, origin: site) { notifications = $0 }
                #expect(notifications == .deny)
                #expect(peek.permissionRequest == nil)

                var camera: BrowserPermissionDecision?
                delegate.browserPage(peek.page, requestPermission: .camera, origin: site) { camera = $0 }
                window.tabManager.openPeekInTab()

                #expect(camera == .deny)
                #expect(peek.permissionRequest == nil)
                for _ in 0 ..< 50 where window.tabManager.peek != nil {
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
        }

        /// A page in no window (as in the tests) gets no dialog, and a new
        /// document may show dialogs again, like a tab.
        @Test func dialogsFollowTheTabsPolicy() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                defer { window.tabManager.closePeek() }
                let delegate = try #require(peek.page.delegate)
                let dialog = BrowserJavaScriptDialog(kind: .confirm, message: "Leave?", host: "example.com")

                var reply: BrowserJavaScriptDialogReply?
                delegate.browserPage(peek.page, runJavaScriptDialog: dialog) { reply = $0 }
                #expect(reply == .refused)

                peek.sheets.dialogPolicy.stopDialogs()
                delegate.browserPage(peek.page, didUpdateNavigation: BrowserNavigationEvent(
                    phase: .committed, url: peek.url, title: nil, progress: 0.5, isLoading: true
                ))
                #expect(!peek.sheets.dialogPolicy.isStopped)
            }
        }

        /// Dialogs stopped in Peek stay stopped in the tab it becomes.
        @Test func stoppedDialogsStayStoppedInTheTab() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                _ = peek.sheets.dialogPolicy.decide(isPageShown: true)
                peek.sheets.dialogPolicy.stopDialogs()

                window.tabManager.openPeekInTab()
                for _ in 0 ..< 50 where window.tabManager.peek != nil {
                    try await Task.sleep(for: .milliseconds(20))
                }

                let tab = try #require(window.tabManager.activeTab)
                #expect(tab.browserPage === peek.page)
                #expect(tab.pageDelegate?.sheets.dialogPolicy.isStopped == true)
                #expect(tab.pageDelegate?.sheets.dialogPolicy.shownCount == 1)
            }
        }

        /// What Peek blocked shows in the tab it becomes.
        @Test func blockedContentGoesToTheTab() async throws {
            try await TabManagerTestWindow.run { window in
                let peek = try await openPeek(in: window)
                let delegate = try #require(peek.page.delegate)
                let tracker = try #require(URL(string: "https://tracker.example/pixel.gif"))
                delegate.browserPage(peek.page, didBlockContentFrom: tracker)
                delegate.browserPage(peek.page, didBlockContentFrom: tracker)

                window.tabManager.openPeekInTab()
                for _ in 0 ..< 50 where window.tabManager.peek != nil {
                    try await Task.sleep(for: .milliseconds(20))
                }

                let tab = try #require(window.tabManager.activeTab)
                #expect(tab.browserPage === peek.page)
                #expect(tab.blockedContent == ["tracker.example": 2])
            }
        }

        private func openPeek(in window: TabManagerTestWindow) async throws -> PeekPage {
            let opener = try await window.openLoaded("opener")
            opener.openPeek(TabManagerTestWindow.url("peek"))
            return try #require(window.tabManager.peek)
        }
    }
}
