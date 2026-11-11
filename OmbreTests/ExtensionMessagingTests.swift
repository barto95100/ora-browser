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
             "host_permissions": ["<all_urls>"], "permissions": ["contextMenus", "tabs"],
             "content_scripts": [{"matches": ["<all_urls>"], "js": ["content.js"], "run_at": "document_end"}]}
            """
            let background = """
            browser.contextMenus.create({ id: "probe", title: "Probe item", contexts: ["all"] });
            const page = browser.runtime.getURL("page.html");
            browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
              if (message === "open-window") {
                // As Bitwarden opens its unlock window.
                browser.windows.create({ url: page, type: "popup", width: 320, height: 480 })
                  .then(w => sendResponse(w && w.tabs && w.tabs.length === 1 ? "window" : "no-window"))
                  .catch(e => sendResponse("error: " + e.message));
                return true;
              }
              if (message === "open-tab") {
                browser.tabs.create({ url: page })
                  .then(t => sendResponse(t ? "tab" : "no-tab"))
                  .catch(e => sendResponse("error: " + e.message));
                return true;
              }
              sendResponse({ tab: sender.tab ? sender.tab.id : null });
            });
            """
            // The extension's own page: its APIs work there.
            let page = """
            <html><body><script src="page.js"></script></body></html>
            """
            let pageScript = """
            browser.runtime.sendMessage("ping")
              .then(r => { document.documentElement.dataset.page = r && r.tab != null ? "tab" : "no-tab"; })
              .catch(e => { document.documentElement.dataset.page = "error: " + e.message; });
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
            const action = document.documentElement.dataset.action;
            if (action) {
              browser.runtime.sendMessage(action)
                .then(r => { document.documentElement.dataset.opened = r; })
                .catch(e => { document.documentElement.dataset.opened = "error: " + e.message; });
            }
            """
            try page.write(to: folder.appendingPathComponent("page.html"), atomically: true, encoding: .utf8)
            try pageScript.write(to: folder.appendingPathComponent("page.js"), atomically: true, encoding: .utf8)
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

        /// A normal browser window the extensions know, in front of the
        /// others (off screen): where what they open goes.
        private static func registerInFront(_ window: TabManagerTestWindow) -> NSWindow {
            let nsWindow = NSWindow(
                contentRect: .init(x: -20000, y: -20000, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: true
            )
            nsWindow.isReleasedWhenClosed = false
            nsWindow.orderBack(nil)
            WebExtensionsHub.registerWindow(nsWindow, tabManager: window.tabManager, isPrivate: false)
            return nsWindow
        }

        /// Loads a page of the probe site in `webView` and waits for the
        /// extension's answer. `action`: what the page then asks the
        /// extension to open ("open-window", "open-tab").
        private static func probe(_ webView: WKWebView, asking action: String? = nil) async throws -> String? {
            let site = try #require(probeSite)
            let attribute = action.map { " data-action=\"\($0)\"" } ?? ""
            webView.loadHTMLString("<html\(attribute)><body><input type=password></body></html>", baseURL: site)
            return try await value("probe", in: webView)
        }

        /// Waits for `data-<key>` in `webView`'s page.
        private static func value(_ key: String, in webView: WKWebView) async throws -> String? {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(10)
            while clock.now < deadline {
                let value = try? await webView.evaluateJavaScript("document.documentElement.dataset.\(key) ?? null")
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

        /// `windows.create` with the extension's page (Bitwarden's unlock
        /// window): a window of its own, where the page works.
        @Test func extensionOpensItsPageInAWindow() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.registerInFront(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("tab")
                    // Its own first load (which fails here) over first.
                    await window.waitUntil("tab loaded") { !tab.isLoading }
                    try? await Task.sleep(for: .milliseconds(200))
                    let webView = try #require(tab.browserPage?.webView)
                    _ = try await Self.probe(webView, asking: "open-window")
                    let opened = try await Self.value("opened", in: webView)
                    #expect(opened == "window", "\(opened ?? "nil")")
                    let manager = WebExtensionsManager.shared
                    let popup = try #require(manager.popupWindows.values.first {
                        $0.tab?.page?.extensionWebView.url?.scheme == ExtensionBaseURL.scheme
                    })
                    defer { popup.window?.close() }
                    let page = try #require(popup.tab?.page?.webView)
                    let answer = try await Self.value("page", in: page)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                    #expect(popup.window?.title == "Probe")
                }
            }
        }

        /// `tabs.create` with the extension's page (also its options page):
        /// the tab's page works (WebKit cancels it in a website's page).
        @Test func extensionOpensItsPageInATab() async throws {
            guard #available(macOS 15.4, *) else { return }
            try await TabManagerTestWindow.run { window in
                try await Self.withProbe {
                    let nsWindow = Self.registerInFront(window)
                    defer { nsWindow.close() }
                    let tab = try await window.openLoaded("tab")
                    // Its own first load (which fails here) over first.
                    await window.waitUntil("tab loaded") { !tab.isLoading }
                    try? await Task.sleep(for: .milliseconds(200))
                    let webView = try #require(tab.browserPage?.webView)
                    _ = try await Self.probe(webView, asking: "open-tab")
                    let opened = try await Self.value("opened", in: webView)
                    #expect(opened == "tab", "\(opened ?? "nil")")
                    let pageTab = try #require(window.tabManager.activeTab)
                    #expect(pageTab.url.scheme == ExtensionBaseURL.scheme)
                    await window.waitUntil("extension page ready") { pageTab.isWebViewReady }
                    let page = try #require(pageTab.browserPage?.webView)
                    let answer = try await Self.value("page", in: page)
                    #expect(answer == "tab", "\(answer ?? "nil")")
                    // A website from it: in a tab of its own (WebKit loads
                    // nothing else in the extension's page).
                    _ = try? await page.evaluateJavaScript("location.href = 'https://probe.example/site'")
                    await window.waitUntil("website in a new tab") {
                        window.tabManager.activeTab?.url.host() == "probe.example"
                    }
                    #expect(window.tabManager.activeTab !== pageTab)
                    #expect(pageTab.url.scheme == ExtensionBaseURL.scheme)
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
