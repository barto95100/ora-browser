import AppKit
import Foundation
@testable import Ombre
import Testing
import WebKit

/// Links of Little Ombre's page that open a new window (`target="_blank"`,
/// ⌘-click): tabs of its space in its browser window, not popups.
extension TabManagerTests {
    @MainActor
    @Suite(.serialized)
    struct LittleOmbreLinks {
        @Test func aNewWindowLinkOpensALinkedTab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: nil
                ))
                defer { little.window.close() }
                let page = little.popup.page
                let delegate = try #require(page.delegate)
                let link = TabManagerTestWindow.url("blank")

                let webView = delegate.browserPage(
                    page,
                    linkedPageWith: page.webView.configuration,
                    for: link,
                    disposition: .foreground
                )

                let tab = try #require(window.tabManager.activeTab)
                #expect(webView != nil)
                #expect(tab.browserPage?.webView === webView)
                #expect(tab.container.id == space.id)
                #expect(tab.url == link)
                // Little Ombre stays, with its page.
                #expect(LittleOmbreWindow.isLittleOmbreWindow(little.window))
                #expect(!little.model.isPageGone)
            }
        }

        @Test func aCommandClickOpensATabInTheBackground() async throws {
            try await TabManagerTestWindow.run { window in
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: nil
                ))
                defer { little.window.close() }
                let page = little.popup.page
                let delegate = try #require(page.delegate)
                let previous = window.tabManager.activeTab?.id
                let link = TabManagerTestWindow.url("command-click")

                // As WebKit asks for the click: opened here, the navigation
                // cancelled (allowed, WebKit would ask for a window in front).
                let action = BrowserNavigationAction(request: URLRequest(url: link), modifierFlags: .command)
                #expect(delegate.browserPage(page, decidePolicyFor: action) == .cancel)

                #expect(window.tabManager.activeTab?.id == previous)
                let space = try window.activeSpace
                let opened = try #require(space.tabs.first { $0.url == link })
                // Loaded, not only listed.
                #expect(opened.browserPage != nil)
            }
        }

        /// ⌘⇧-click: in front, like Safari; a plain click stays in the page.
        @Test func aCommandShiftClickOpensATabInFront() async throws {
            try await TabManagerTestWindow.run { window in
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: nil
                ))
                defer { little.window.close() }
                let page = little.popup.page
                let delegate = try #require(page.delegate)
                let link = TabManagerTestWindow.url("command-shift-click")

                let plain = BrowserNavigationAction(request: URLRequest(url: link), modifierFlags: [])
                #expect(delegate.browserPage(page, decidePolicyFor: plain) == .allow)
                let action = BrowserNavigationAction(request: URLRequest(url: link), modifierFlags: [.command, .shift])
                #expect(delegate.browserPage(page, decidePolicyFor: action) == .cancel)

                #expect(window.tabManager.activeTab?.url == link)
            }
        }

        /// Another popup window (a sign-in page): ⌘-click left to WebKit, as before.
        @Test func aCommandClickInAnotherPopupIsLeftToWebKit() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let page = Tab.makeSpacePage(spaceID: space.id, isPrivate: false, privateSession: nil)
                let popup = PopupPage(page: page, context: PopupContext(
                    spaceID: space.id, isPrivate: false, privateSession: nil, downloadManager: nil
                ))
                defer { popup.close() }
                let delegate = try #require(page.delegate)
                let link = TabManagerTestWindow.url("popup-command-click")

                let action = BrowserNavigationAction(request: URLRequest(url: link), modifierFlags: .command)
                #expect(delegate.browserPage(page, decidePolicyFor: action) == .allow)
                #expect(!space.tabs.contains { $0.url == link })
            }
        }

        /// In front: the browser window Little Ombre hid shows with the tab.
        @Test func aTabInFrontShowsTheHiddenBrowserWindow() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: true
                )
                browser.isReleasedWhenClosed = false
                defer { browser.orderOut(nil) }
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: browser
                ))
                defer { little.window.close() }
                little.hideBrowserWindow(.close)
                let page = little.popup.page
                let delegate = try #require(page.delegate)

                delegate.browserPage(
                    page, didRequestOpenInNewTab: TabManagerTestWindow.url("front"), disposition: .foreground
                )

                #expect(little.hiddenBrowserWindow == nil)
                #expect(browser.isVisible)
                #expect(!browser.isExcludedFromWindowsMenu)
            }
        }

        /// Its space gone, or another privacy than the window's: no tab (a
        /// popup window then, as before).
        @Test func noTabWithoutItsSpaceOrInAnotherPrivacy() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                @MainActor func popup(spaceID: UUID, isPrivate: Bool) -> PopupPage {
                    let page = Tab.makeSpacePage(spaceID: spaceID, isPrivate: isPrivate, privateSession: nil)
                    return PopupPage(page: page, context: PopupContext(
                        spaceID: spaceID, isPrivate: isPrivate, privateSession: nil, downloadManager: nil
                    ))
                }
                let gone = popup(spaceID: UUID(), isPrivate: false)
                let otherPrivacy = popup(spaceID: space.id, isPrivate: true)
                defer {
                    gone.close()
                    otherPrivacy.close()
                }
                for popup in [gone, otherPrivacy] {
                    #expect(window.tabManager.openLittleOmbreLink(
                        TabManagerTestWindow.url("x"), from: popup, configuration: nil, disposition: .foreground
                    ) == nil)
                }
            }
        }

        /// Another space active: the tab still goes to Little Ombre's (its
        /// data), shown in front; in the background, the space stays.
        @Test func theTabGoesToLittleOmbresSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: nil
                ))
                defer { little.window.close() }
                let other = window.createSpace("Other")
                window.tabManager.activateContainer(other)
                let page = little.popup.page
                let delegate = try #require(page.delegate)

                delegate.browserPage(
                    page, didRequestOpenInNewTab: TabManagerTestWindow.url("back"), disposition: .background
                )
                #expect(window.tabManager.activeContainer?.id == other.id)
                #expect(space.tabs.contains { $0.url == TabManagerTestWindow.url("back") })

                let link = TabManagerTestWindow.url("front")
                _ = delegate.browserPage(
                    page, linkedPageWith: page.webView.configuration, for: link, disposition: .foreground
                )
                #expect(window.tabManager.activeContainer?.id == space.id)
                #expect(window.tabManager.activeTab?.url == link)
                #expect(window.tabManager.activeTab?.container.id == space.id)
            }
        }

        /// In the background: the browser window Little Ombre hid shows
        /// behind it, and no longer closes with it.
        @Test func aTabInTheBackgroundKeepsTheHiddenBrowserWindow() async throws {
            try await TabManagerTestWindow.run { window in
                let browser = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: true
                )
                browser.isReleasedWhenClosed = false
                defer { browser.orderOut(nil) }
                let little = try #require(LittleOmbreWindow.open(
                    TabManagerTestWindow.url("little"), from: window.tabManager, window: browser
                ))
                little.hideBrowserWindow(.close)
                let page = little.popup.page
                let delegate = try #require(page.delegate)
                delegate.browserPage(
                    page, didRequestOpenInNewTab: TabManagerTestWindow.url("later"), disposition: .background
                )
                #expect(little.hiddenBrowserWindow == nil)
                #expect(browser.isVisible)
                little.window.close()
                await Task.yield()
                #expect(browser.isVisible)
            }
        }
    }
}
