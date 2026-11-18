import AppKit
import Foundation
@testable import Ombre
import Testing

/// A link while no browser window is open: SwiftUI makes one to hand it over;
/// Little Ombre hides it and opens alone.
extension TabManagerTests {
    @MainActor
    @Suite(.serialized)
    struct LittleOmbreBrowserWindow {
        /// Remembers being closed (never shown on screen).
        private final class BrowserWindowStandIn: NSWindow {
            var isClosed = false

            init() {
                super.init(
                    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: true
                )
                isReleasedWhenClosed = false
            }

            override func close() {
                isClosed = true
                super.close()
            }
        }

        private let longAgo: TimeInterval = 600

        @Test func onlyAWindowMadeForTheLinkIsHidden() {
            let made = BrowserWindowStandIn()
            let other = BrowserWindowStandIn()
            func hiding(
                _ elapsed: Duration, others: [NSWindow] = [], launched: TimeInterval = 600,
                isOpen: @escaping (NSWindow) -> Bool = { _ in true }
            ) -> HiddenBrowserWindow? {
                LittleOmbreWindow.hiding(
                    made, appearedFor: elapsed, otherWindows: others, launchedFor: launched, isOpen: isOpen
                )
            }
            // Ombre running without a window: closed once done.
            #expect(hiding(.milliseconds(200), others: [made]) == .close)
            // The link launched Ombre: its window shows once done, as a launch would.
            #expect(hiding(.milliseconds(200), launched: 2) == .show)
            // Another window was open, or this one was there before the link.
            #expect(hiding(.milliseconds(200), others: [made, other]) == nil)
            #expect(hiding(.seconds(3)) == nil)
            // A window closed or hidden with the app isn't one to hide.
            #expect(hiding(.milliseconds(200), isOpen: { _ in false }) == nil)
            // Another window closed: as if none.
            #expect(hiding(.milliseconds(200), others: [other], isOpen: { $0 === made }) == .close)
        }

        /// Why a window is kept, for the log.
        @Test func aKeptWindowSaysWhy() {
            let made = BrowserWindowStandIn()
            let other = BrowserWindowStandIn()
            func decision(_ elapsed: Duration, others: [NSWindow] = [], open: Bool = true) -> LittleOmbreWindow
                .HidingDecision
            {
                LittleOmbreWindow.hidingDecision(
                    made, appearedFor: elapsed, otherWindows: others, launchedFor: longAgo, isOpen: { _ in open }
                )
            }
            #expect(decision(.milliseconds(200)) == .hide(.close))
            #expect(decision(.milliseconds(200), open: false) == .keep(reason: "not on screen"))
            #expect(decision(.milliseconds(200), others: [other]) == .keep(reason: "1 other browser window(s) open"))
            guard case let .keep(reason) = decision(.seconds(3)) else {
                Issue.record("A window there before the link is kept")
                return
            }
            #expect(reason.hasPrefix("there before the link"))
        }

        /// At launch, SwiftUI may give the window before it is on screen: the
        /// decision waits for it (taken before, it kept the window, which
        /// then came in front of Little Ombre).
        @Test func theDecisionWaitsForTheWindowOnScreen() {
            let window = BrowserWindowStandIn()
            defer { window.orderOut(nil) }
            var decided = 0
            LittleOmbreWindow.whenOnScreen(window) { decided += 1 }
            #expect(decided == 0)

            window.orderBack(nil)
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            #expect(decided == 1)
            // Once only.
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            #expect(decided == 1)
            // On screen already: at once.
            LittleOmbreWindow.whenOnScreen(window) { decided += 1 }
            #expect(decided == 2)
        }

        /// Closed before it showed: never decided, the wait is over.
        @Test func aWindowClosedBeforeItShowsIsNeverDecided() {
            let window = BrowserWindowStandIn()
            var decided = false
            var expired = false
            LittleOmbreWindow.whenOnScreen(window) {
                decided = true
            } expired: {
                expired = true
            }
            window.close()
            #expect(expired)
            window.orderBack(nil)
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            window.orderOut(nil)
            #expect(!decided)
        }

        /// Shown only after the wait: the user's window, never decided (it
        /// could be hidden under them).
        @Test func aWindowShownAfterTheWaitIsNeverDecided() async throws {
            let window = BrowserWindowStandIn()
            defer { window.orderOut(nil) }
            var decided = false
            var expired = false
            LittleOmbreWindow.whenOnScreen(
                window, within: .milliseconds(20)
            ) {
                decided = true
            } expired: {
                expired = true
            }
            try await Task.sleep(for: .milliseconds(200))
            #expect(expired)
            window.orderBack(nil)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            #expect(!decided)
        }

        /// Shown for a tab (in front or behind): the user's now, a decision
        /// still waiting for it leaves it.
        @Test func aWindowShownForATabIsMarked() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = BrowserWindowStandIn()
                defer { browser.orderOut(nil) }
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: browser
                ))
                defer { little.window.close() }
                #expect(!LittleOmbreWindow.shownForATab.contains(browser))
                little.showBrowserWindowBehind()
                #expect(LittleOmbreWindow.shownForATab.contains(browser))
            }
        }

        /// Closed: the browser window it hid goes once no Little Ombre uses it.
        @Test func theHiddenWindowClosesWithTheLastLittleOmbre() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = BrowserWindowStandIn()
                let first = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("first"), from: window.tabManager, window: browser
                ))
                first.hideBrowserWindow(.close)
                #expect(browser.isExcludedFromWindowsMenu)
                let second = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("second"), from: window.tabManager, window: browser
                ))
                // Already hidden: held by the second one too.
                let fate = try #require(LittleOmbreWindow.hiding(
                    browser, appearedFor: .seconds(30), otherWindows: [], launchedFor: longAgo
                ))
                second.hideBrowserWindow(fate)

                first.window.close()
                await Task.yield()
                #expect(!browser.isClosed)
                second.window.close()
                await window.waitUntil("browser window closed") { browser.isClosed }
            }
        }

        /// Opened from the hidden window without hiding it (⌥⌘N, a link
        /// handed over): it holds the window too, which doesn't close under it.
        @Test func aLittleOmbreFromTheHiddenWindowHoldsItToo() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = BrowserWindowStandIn()
                let first = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: browser))
                first.hideBrowserWindow(.close)
                let second = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: browser))
                #expect(second.hiddenBrowserWindow == .close)
                first.window.close()
                await Task.yield()
                #expect(!browser.isClosed)
                #expect(LittleOmbreWindow.isLittleOmbreWindow(second.window))
                second.window.close()
                await window.waitUntil("browser window closed") { browser.isClosed }
            }
        }

        /// The browser window closes for another reason (an extension): its
        /// Little Ombres close with it, without closing or showing it again.
        @Test func theHiddenWindowClosedElsewhereIsLeftAlone() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = BrowserWindowStandIn()
                let little = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: browser))
                little.hideBrowserWindow(.show)
                LittleOmbreWindow.closeAll(from: window.tabManager)
                #expect(!LittleOmbreWindow.isLittleOmbreWindow(little.window))
                await Task.yield()
                #expect(!browser.isVisible)
                #expect(!browser.isClosed)
            }
        }

        /// The link launched Ombre: its window shows once Little Ombre closes.
        @Test func aWindowOfTheLaunchShowsAfterwards() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = BrowserWindowStandIn()
                defer { browser.orderOut(nil) }
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("launch"), from: window.tabManager, window: browser
                ))
                little.hideBrowserWindow(.show)
                little.window.close()
                #expect(!browser.isExcludedFromWindowsMenu)
                #expect(browser.isVisible)
                await Task.yield()
                #expect(!browser.isClosed)
            }
        }

        /// "Open in Ombre" or a link opened as a tab: the window is needed, shown.
        @Test func theHiddenWindowShowsWhenNeeded() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = BrowserWindowStandIn()
                defer { browser.orderOut(nil) }
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("tab"), from: window.tabManager, window: browser
                ))
                await window.waitUntil("address known") { little.popup.page.currentURL != nil }
                little.hideBrowserWindow(.close)
                little.openInOmbre()
                await window.waitUntil("moved to a tab") { !LittleOmbreWindow.isLittleOmbreWindow(little.window) }
                #expect(!browser.isExcludedFromWindowsMenu)
                #expect(browser.isVisible)
                await Task.yield()
                #expect(!browser.isClosed)

                let other = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("other"), from: window.tabManager, window: browser
                ))
                defer { other.window.close() }
                browser.orderOut(nil)
                other.hideBrowserWindow(.close)
                LittleOmbreWindow.browserWindowNeeded(browser)
                #expect(other.hiddenBrowserWindow == nil)
                #expect(browser.isVisible)
            }
        }
    }
}
