import AppKit
@testable import Ombre
import SwiftData
import SwiftUI
import Testing
import WebKit

extension TabManagerTests {
    /// A closing window stops everything it runs and frees its pages, even while
    /// something else still holds its managers.
    @MainActor
    struct WindowCloseTests {
        @Test func tearDownFreesPagesAndStopsTimers() async throws {
            try await TabManagerTestWindow.run { window in
                let first = try await window.openLoaded("first")
                let second = try await window.openLoaded("second")
                weak let firstPage = first.browserPage
                weak let secondPage = second.browserPage
                #expect(TabCleaner.shared.isCleaning(window.tabManager))
                #expect(window.tabManager.memoryPressureSource != nil)

                window.tabManager.tearDown()

                #expect(first.browserPage == nil)
                #expect(second.browserPage == nil)
                #expect(!first.isWebViewReady)
                #expect(!TabCleaner.shared.isCleaning(window.tabManager))
                #expect(window.tabManager.memoryPressureSource == nil)
                await window.waitUntil("pages freed") { firstPage == nil && secondPage == nil }
            }
        }

        @Test func tearDownClosesPeek() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("opener")
                tab.openPeek(TabManagerTestWindow.url("peeked"))
                weak let peekPage = window.tabManager.peek?.page
                #expect(peekPage != nil)

                window.tabManager.tearDown()

                #expect(window.tabManager.peek == nil)
                await window.waitUntil("Peek page freed") { peekPage == nil }
            }
        }

        /// Changes not saved yet (a title, an in-page navigation) are saved.
        @Test func tearDownSaves() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("titled")
                window.tabManager.modelContext.saveOrLog("test")
                tab.title = "Changed, not saved"
                #expect(window.tabManager.modelContext.hasChanges)

                window.tabManager.tearDown()

                #expect(!window.tabManager.modelContext.hasChanges)
            }
        }

        @Test func tearDownTwiceDoesNothingMore() async throws {
            try await TabManagerTestWindow.run { window in
                try await window.openLoaded("once")
                window.tabManager.tearDown()
                window.tabManager.tearDown()
                #expect(!TabCleaner.shared.isCleaning(window.tabManager))
            }
        }
    }

    /// Closing the window itself tears it down (`windowLifecycle`), and only it.
    @MainActor
    struct WindowLifecycleTests {
        /// Whether the view knows its window yet (read after the first render).
        @MainActor
        private final class Probe {
            var isWindowKnown = false
        }

        private struct Content: View {
            @State private var window: NSWindow?
            let tabManager: TabManager
            let probe: Probe

            var body: some View {
                Color.clear
                    .background(WindowReader(window: $window))
                    .windowLifecycle(window: window, tabManager: tabManager, isPrivate: false)
                    .onChange(of: window) { _, newWindow in probe.isWindowKnown = newWindow != nil }
            }
        }

        /// A window showing `tabManager`'s content, once its window is known.
        private func makeWindow(hosting tabManager: TabManager, in managers: TabManagerTestWindow) async -> NSWindow {
            let probe = Probe()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: Content(tabManager: tabManager, probe: probe))
            host.frame = window.contentRect(forFrameRect: window.frame)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            await managers.waitUntil("window known") { probe.isWindowKnown }
            return window
        }

        @Test func closingTheWindowTearsItDown() async throws {
            try await TabManagerTestWindow.run { managers in
                let tab = try await managers.openLoaded("shown")
                let window = await makeWindow(hosting: managers.tabManager, in: managers)

                window.close()

                #expect(tab.browserPage == nil)
                #expect(!TabCleaner.shared.isCleaning(managers.tabManager))
                window.contentView = nil
            }
        }

        @Test func closingAnotherWindowDoesNotTearItDown() async throws {
            try await TabManagerTestWindow.run { managers in
                let tab = try await managers.openLoaded("kept")
                let window = await makeWindow(hosting: managers.tabManager, in: managers)

                let other = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: true
                )
                other.isReleasedWhenClosed = false
                other.close()

                #expect(tab.browserPage != nil)
                #expect(TabCleaner.shared.isCleaning(managers.tabManager))
                // Its own closing does reach it.
                window.close()
                #expect(tab.browserPage == nil)
                window.contentView = nil
            }
        }
    }
}

/// Popups (`window.open` with a size) close with the window of the page that
/// opened them: they share its process and website data.
@MainActor
struct PopupCloseTests {
    @Test func popupsCloseWithTheirOpenerWindow() {
        let opener = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        opener.isReleasedWhenClosed = false
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        other.isReleasedWhenClosed = false
        let context = PopupContext(spaceID: UUID(), isPrivate: true, privateSession: UUID(), downloadManager: nil)

        _ = BrowserPopupWindow.open(
            configuration: WKWebViewConfiguration(), windowFeatures: WKWindowFeatures(), openerWindow: opener,
            opener: nil, context: context
        )
        _ = BrowserPopupWindow.open(
            configuration: WKWebViewConfiguration(), windowFeatures: WKWindowFeatures(), openerWindow: other,
            opener: nil, context: context
        )
        #expect(BrowserPopupWindow.popupCount(openedFrom: opener) == 1)

        BrowserPopupWindow.closePopups(openedFrom: opener)

        #expect(BrowserPopupWindow.popupCount(openedFrom: opener) == 0)
        #expect(BrowserPopupWindow.popupCount(openedFrom: other) == 1)
        BrowserPopupWindow.closePopups(openedFrom: other)
        #expect(BrowserPopupWindow.popupCount(openedFrom: other) == 0)
    }
}
