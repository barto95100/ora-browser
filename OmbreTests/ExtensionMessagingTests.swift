import AppKit
import Foundation
@testable import Ombre
import Testing
@preconcurrency import WebKit

extension TabManagerTests {
    /// An extension's scripts in a page reach the extension (Bitwarden's
    /// inline menu): every page with them must be a tab the extensions know,
    /// or WebKit drops their messages ("Tab not found").
    @MainActor
    struct ExtensionMessaging {
        private static let probeSite = URL(string: "https://probe.example/login")

        /// A small extension: its script in the page asks its background,
        /// which answers with the tab it sees; the answer goes in the page.
        private static func makeProbeExtension() throws -> URL {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("probe-extension-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest = """
            {"manifest_version": 3, "name": "Probe", "version": "1.0",
             "background": {"service_worker": "background.js"},
             "host_permissions": ["<all_urls>"], "permissions": ["contextMenus"],
             "content_scripts": [{"matches": ["<all_urls>"], "js": ["content.js"], "run_at": "document_end"}]}
            """
            let background = """
            browser.contextMenus.create({ id: "probe", title: "Probe item", contexts: ["all"] });
            browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
              sendResponse({ tab: sender.tab ? sender.tab.id : null });
            });
            """
            // Bitwarden's check before showing its menu under login fields:
            // a Safari, Chrome or Firefox extension URL of its own origin.
            let content = """
            const own = new URL(browser.runtime.getURL("page.html"));
            const schemes = ["chrome-extension:", "moz-extension:", "safari-web-extension:"];
            document.documentElement.dataset.base = schemes.includes(own.protocol)
              && own.origin === browser.runtime.getURL("").slice(0, -1) ? "accepted" : "refused " + own.href;
            browser.runtime.sendMessage("ping")
              .then(r => { document.documentElement.dataset.probe = r && r.tab != null ? "tab" : "no-tab"; })
              .catch(e => { document.documentElement.dataset.probe = "error: " + e.message; });
            """
            try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try background.write(to: folder.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
            try content.write(to: folder.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)
            return folder
        }

        @available(macOS 15.4, *)
        private static func withProbe(_ body: () async throws -> Void) async throws {
            let folder = try makeProbeExtension()
            defer { try? FileManager.default.removeItem(at: folder) }
            let webExtension = try await WKWebExtension(resourceBaseURL: folder)
            let context = WKWebExtensionContext(for: webExtension)
            // As the manager loads them (`run`), with an id in capitals.
            let id = UUID().uuidString
            context.uniqueIdentifier = id
            ExtensionBaseURL.registerScheme()
            ExtensionBaseURL.apply(to: context, id: id)
            context.hasAccessToPrivateData = true
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.MatchPattern.allURLs())
            context.setPermissionStatus(.grantedExplicitly, for: .contextMenus)
            let controller = WebExtensionsManager.shared.controller
            try controller.load(context)
            defer { try? controller.unload(context) }
            // Its background ready before the page asks it.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                context.loadBackgroundContent { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            try await body()
        }

        /// The test window as a browser window the extensions know.
        private static func register(_ window: TabManagerTestWindow) -> NSWindow {
            let nsWindow = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: true
            )
            nsWindow.isReleasedWhenClosed = false
            WebExtensionsHub.registerWindow(nsWindow, tabManager: window.tabManager, isPrivate: true)
            return nsWindow
        }

        /// Loads a page of the probe site in `webView` and waits for the
        /// extension's answer.
        private static func probe(_ webView: WKWebView) async throws -> String? {
            let site = try #require(probeSite)
            webView.loadHTMLString("<html><body><input type=password></body></html>", baseURL: site)
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(10)
            while clock.now < deadline {
                let value = try? await webView.evaluateJavaScript("document.documentElement.dataset.probe ?? null")
                if let answer = value as? String { return answer }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let url = try? await webView.evaluateJavaScript("document.URL + ' ' + typeof browser")
            Issue.record("No answer from the extension: \(String(describing: url))")
            return nil
        }

        @Test func scriptsInATabReachTheExtension() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("tab")
                    let webView = try #require(tab.browserPage?.webView)
                    let answer = try await Self.probe(webView)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                }
            }
        }

        /// Extensions see Safari's URLs for their own files: Bitwarden's menu
        /// under login fields refuses WebKit's `webkit-extension:` ones (it
        /// stayed a dark line under the field).
        @Test func extensionURLsAreSafaris() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("tab")
                    let webView = try #require(tab.browserPage?.webView)
                    _ = try await Self.probe(webView)
                    let base = try? await webView.evaluateJavaScript("document.documentElement.dataset.base ?? null")
                    #expect(base as? String == "accepted", "\(String(describing: base))")
                }
            }
        }

        /// WebKit adds the extensions' items to the context menu itself:
        /// Ombre adds none (Bitwarden's showed twice).
        @Test func ombreAddsNoExtensionItemsToTheContextMenu() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("tab")
                    let page = try #require(tab.browserPage)
                    _ = try await Self.probe(page.webView)
                    let delegate = try #require(page.delegate)
                    let titles = delegate.browserPageContextMenuItems(page).flatMap { item in
                        [item.title] + (item.submenu?.items.map(\.title) ?? [])
                    }
                    #expect(!titles.contains("Probe item"), "\(titles)")
                }
            }
        }

        /// Bitwarden loads at launch while tabs are restored: tabs opened
        /// before it must still be known to it.
        @Test func scriptsInATabOpenedBeforeTheExtensionReachIt() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                let nsWindow = Self.register(window)
                defer { nsWindow.close() }
                let tab = try await window.openLoaded("tab")
                let background = try await window.openLoaded("background")
                window.tabManager.activateTab(tab)
                try await Self.withProbe {
                    for page in [tab, background] {
                        let webView = try #require(page.browserPage?.webView)
                        let answer = try await Self.probe(webView)
                        #expect(answer == "tab", "\(answer ?? "nil")")
                    }
                }
            }
        }

        /// After a reload or another page, the tab is still known.
        @Test func scriptsReachTheExtensionAfterAReload() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("tab")
                    window.tabManager.togglePinTab(tab)
                    let webView = try #require(tab.browserPage?.webView)
                    _ = try await Self.probe(webView)
                    webView.reload()
                    try? await Task.sleep(for: .milliseconds(300))
                    let answer = try await Self.probe(webView)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                }
            }
        }

        @Test func scriptsInPeekReachTheExtension() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let opener = try await window.openLoaded("opener")
                    opener.openPeek(TabManagerTestWindow.url("peek"))
                    let peek = try #require(window.tabManager.peek)
                    defer { window.tabManager.closePeek() }
                    // Its own first load (which fails here) over first.
                    await window.waitUntil("Peek loaded") { !peek.isLoading }
                    try? await Task.sleep(for: .milliseconds(200))
                    let answer = try await Self.probe(peek.page.webView)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                }
            }
        }

        /// Peek opened in a tab (⌘O): its page is then the tab's, still known.
        @Test func peekMovedToATabStillReachesTheExtension() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let opener = try await window.openLoaded("opener")
                    opener.openPeek(TabManagerTestWindow.url("peek"))
                    let peek = try #require(window.tabManager.peek)
                    await window.waitUntil("Peek loaded") { !peek.isLoading }
                    window.tabManager.openPeekInTab()
                    await window.waitUntil("Peek in a tab") { window.tabManager.peek == nil }
                    try? await Task.sleep(for: .milliseconds(100))
                    let answer = try await Self.probe(peek.page.webView)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                }
            }
        }

        /// An extension loaded (or updated) while Peek shows still knows it.
        @Test func extensionLoadedWhilePeekShowsReachesIt() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                let nsWindow = Self.register(window)
                defer { nsWindow.close() }
                let opener = try await window.openLoaded("opener")
                opener.openPeek(TabManagerTestWindow.url("peek"))
                let peek = try #require(window.tabManager.peek)
                defer { window.tabManager.closePeek() }
                await window.waitUntil("Peek loaded") { !peek.isLoading }
                try? await Task.sleep(for: .milliseconds(200))
                try await Self.withProbe {
                    let answer = try await Self.probe(peek.page.webView)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                }
            }
        }

        @Test func scriptsInAPopupReachTheExtension() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.register(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("opener")
                    let page = try #require(tab.browserPage)
                    let delegate = try #require(tab.pageDelegate)
                    let configuration = try #require(page.webView.configuration.copy() as? WKWebViewConfiguration)
                    let popupView = try #require(delegate.browserPage(
                        page, openPopupWith: configuration, windowFeatures: WKWindowFeatures(), openerOrigin: nil
                    ))
                    let popup = try #require(BrowserPopupWindow.popup(showing: popupView))
                    defer { popup.popupPage.closeWindow?() }
                    let answer = try await Self.probe(popupView)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                }
            }
        }
    }
}
