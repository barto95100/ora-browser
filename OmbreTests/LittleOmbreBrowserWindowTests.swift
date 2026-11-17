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
            let open: (NSWindow) -> Bool = { _ in true }
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
            // A minimized other window is still open.
            #expect(hiding(.milliseconds(200), others: [other], isOpen: open) == nil)
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
