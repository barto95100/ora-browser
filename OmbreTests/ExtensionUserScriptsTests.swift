import Foundation
import JavaScriptCore
@testable import Ombre
import Testing
import WebKit

/// `chrome.userScripts` (`ExtensionUserScripts`, `ExtensionUserScriptMatcher`,
/// `ExtensionUserScriptInjector`, `ExtensionUserScriptMessages`): Chrome's
/// checks, the pages a script runs in, and the channel's refusals. With a
/// folder, controller and pages of the tests' own (never the app's).
@MainActor
@Suite(.serialized)
struct ExtensionUserScriptsTests {
    static let extensionID = UUID().uuidString

    func makeStore() -> (ExtensionUserScripts, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("userscripts-\(UUID().uuidString)")
        return (ExtensionUserScripts(folder: folder), folder)
    }

    static func script(_ id: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["id": id, "matches": ["https://example.com/*"], "js": [["code": "1"]]].merging(extra) { $1 }
    }

    private func register(_ store: ExtensionUserScripts, _ scripts: [[String: Any]]) throws {
        _ = try store.handle("register", ["scripts": scripts], extensionID: Self.extensionID)
    }

    private func failure(_ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Chrome's checks

    @Test func registersAndGivesBackAsWritten() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try register(store, [
            Self.script("a", ["js": [["file": "a.js", "code": "read"]], "runAt": "document_start"]),
            Self.script("b", ["world": "MAIN", "allFrames": true])
        ])
        let scripts = try #require(
            store.handle("getScripts", [:], extensionID: Self.extensionID) as? [[String: Any]]
        )
        #expect(scripts.map { $0["id"] as? String } == ["a", "b"])
        // A file is given back as a file, its code kept for the pages.
        #expect((scripts[0]["js"] as? [[String: String]]) == [["file": "a.js"]])
        #expect(scripts[0]["world"] as? String == "USER_SCRIPT" && scripts[1]["world"] as? String == "MAIN")
        #expect(scripts[1]["runAt"] as? String == "document_idle" && scripts[1]["allFrames"] as? Bool == true)
        #expect(store.registered(for: Self.extensionID).scripts[0].sources[0].code == "read")

        // Kept between launches.
        let again = ExtensionUserScripts(folder: folder)
        #expect(again.registered(for: Self.extensionID).scripts.map(\.id) == ["a", "b"])
        // Gone with the extension.
        again.forget(id: Self.extensionID)
        #expect(ExtensionUserScripts(folder: folder).registered(for: Self.extensionID).scripts.isEmpty)
    }

    @Test func refusesWhatChromeRefuses() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try register(store, [Self.script("a")])
        let cases: [[String: Any]] = [
            Self.script("a"), // duplicate
            Self.script(""),
            Self.script("_reserved"),
            Self.script("b", ["matches": []]),
            Self.script("c", ["matches": ["not a pattern"]]),
            Self.script("d", ["matches": ["https://*foo.com/*"]]),
            Self.script("e", ["js": []]),
            Self.script("f", ["js": [["file": "f.js"]]]), // a file without its code
            Self.script("g", ["runAt": "later"]),
            Self.script("h", ["world": "ISOLATED"]),
            Self.script("i", ["world": "MAIN", "worldId": "w"]),
            Self.script("j", ["js": [["file": "../outside.js", "code": "x"]]])
        ]
        for item in cases {
            #expect(failure { try register(store, [item]) } != nil, "\(item)")
        }
        #expect(failure { try register(store, [Self.script("k"), Self.script("k")]) }?.contains("Duplicate") == true)
        // Nothing of a refused call was kept.
        #expect(store.registered(for: Self.extensionID).scripts.map(\.id) == ["a"])
        #expect(failure {
            _ = try store.handle("update", ["scripts": [["id": "missing"]]], extensionID: Self.extensionID)
        } != nil)
        #expect(failure {
            _ = try store.handle("unregister", ["filter": ["ids": ["missing"]]], extensionID: Self.extensionID)
        } != nil)
        #expect(failure { _ = try store.handle("execute", [:], extensionID: Self.extensionID) } != nil)
    }

    @Test func updatesUnregistersAndConfiguresWorlds() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try register(store, [Self.script("a"), Self.script("b")])
        _ = try store.handle(
            "update", ["scripts": [["id": "a", "runAt": "document_end", "worldId": "w"]]], extensionID: Self.extensionID
        )
        let updated = store.registered(for: Self.extensionID).scripts[0]
        #expect(updated.runAt == "document_end" && updated.worldId == "w" && updated
            .matches == ["https://example.com/*"])

        _ = try store.handle("unregister", ["filter": ["ids": ["a"]]], extensionID: Self.extensionID)
        #expect(store.registered(for: Self.extensionID).scripts.map(\.id) == ["b"])
        _ = try store.handle("unregister", [:], extensionID: Self.extensionID)
        #expect(store.registered(for: Self.extensionID).scripts.isEmpty)

        _ = try store.handle("configureWorld", ["properties": ["messaging": true]], extensionID: Self.extensionID)
        _ = try store.handle(
            "configureWorld", ["properties": ["worldId": "w", "csp": "x"]], extensionID: Self.extensionID
        )
        let registered = store.registered(for: Self.extensionID)
        // A world without its own setting has the default world's.
        #expect(registered.world("other").messaging && registered.world(nil).messaging && !registered.world("w")
            .messaging)
        let worlds = try #require(
            store.handle("getWorldConfigurations", [:], extensionID: Self.extensionID) as? [[String: Any]]
        )
        #expect(worlds.count == 2)
        _ = try store.handle("resetWorldConfiguration", [:], extensionID: Self.extensionID)
        #expect(!store.registered(for: Self.extensionID).world(nil).messaging)
    }

    // MARK: - Which pages

    private static func runs(
        _ script: [String: Any],
        on href: String,
        access: ExtensionUserScriptMatcher.Access = .init(allURLs: true, granted: [], denied: []),
        tampered: Bool = false
    ) throws -> Bool {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("userscripts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ExtensionUserScripts(folder: folder)
        _ = try store.handle("register", ["scripts": [script]], extensionID: extensionID)
        let registered = try #require(store.registered(for: extensionID).scripts.first)
        store.forget(id: extensionID)
        let condition = ExtensionUserScriptMatcher.condition(for: registered, access: access)
            .replacingOccurrences(of: "location.href", with: "href")
        let context = try #require(JSContext())
        context.setObject(href, forKeyedSubscript: "href" as NSString)
        if tampered {
            // What a page could have done before: nothing the matcher uses.
            context.evaluateScript("""
            String.prototype.indexOf = () => 0; String.prototype.startsWith = () => true;
            Array.prototype.some = () => true; RegExp.prototype.test = () => true;
            JSON.parse = () => ({}); Object.prototype.d = [];
            """)
        }
        return context.evaluateScript(condition)?.toBool() == true
    }

    @Test func matchesAsChrome() throws {
        let plain = Self.script("a", ["matches": ["https://*.example.com/news/*"]])
        #expect(try Self.runs(plain, on: "https://example.com/news/1"))
        #expect(try Self.runs(plain, on: "https://www.example.com/news/1?x=1#top"))
        #expect(try !Self.runs(plain, on: "https://example.com/sport/1"))
        #expect(try !Self.runs(plain, on: "https://badexample.com/news/1"))
        #expect(try !Self.runs(plain, on: "http://example.com/news/1"))
        #expect(try !Self.runs(plain, on: "about:blank"))

        let all = Self.script("b", ["matches": ["<all_urls>"], "excludeMatches": ["*://*.bank.com/*"]])
        #expect(try Self.runs(all, on: "http://site.org:8080/"))
        #expect(try !Self.runs(all, on: "https://my.bank.com/account"))

        let globs = Self.script("c", [
            "matches": ["*://*/*"], "includeGlobs": ["*wiki?pedia*"], "excludeGlobs": ["*edit*"]
        ])
        #expect(try Self.runs(globs, on: "https://en.wiki-pedia.org/page"))
        #expect(try !Self.runs(globs, on: "https://en.wikipedia.org/page"))
        #expect(try !Self.runs(globs, on: "https://en.wiki-pedia.org/edit"))
        // A page can't make it run where it shouldn't.
        #expect(try !Self.runs(plain, on: "https://other.com/news/1", tampered: true))
        #expect(try Self.runs(plain, on: "https://example.com/news/1", tampered: true))
    }

    @Test func onlyWhereTheExtensionMayRead() throws {
        let everywhere = Self.script("a", ["matches": ["<all_urls>"]])
        let some = ExtensionUserScriptMatcher.Access(
            allURLs: false,
            granted: [("*://*.allowed.com/*", nil), ("*://old.com/*", Date(timeIntervalSinceNow: -60))],
            denied: ["*://refused.allowed.com/*"]
        )
        #expect(try Self.runs(everywhere, on: "https://www.allowed.com/", access: some))
        #expect(try !Self.runs(everywhere, on: "https://refused.allowed.com/", access: some))
        #expect(try !Self.runs(everywhere, on: "https://other.com/", access: some))
        // A website allowed for one day, the day over.
        #expect(try !Self.runs(everywhere, on: "https://old.com/", access: some))
        let refusedAll = ExtensionUserScriptMatcher.Access(allURLs: true, granted: [], denied: ["*://*.bank.com/*"])
        #expect(try !Self.runs(everywhere, on: "https://bank.com/", access: refusedAll))
    }

    @Test func validPatterns() {
        for pattern in ["<all_urls>", "*://*/*", "https://example.com/", "file:///*", "https://*.a.org/x*"] {
            #expect(ExtensionUserScriptMatcher.isValidPattern(pattern), "\(pattern)")
        }
        for pattern in ["", "example.com", "https://", "https://exa*mple.com/", "chrome://x/", "https://a.com"] {
            #expect(!ExtensionUserScriptMatcher.isValidPattern(pattern), "\(pattern)")
        }
    }

    @available(macOS 15.4, *)
    private func entry(_ scripts: [[String: Any]], worlds: [[String: Any]] = [], allowsPrivate: Bool = false) throws
        -> ExtensionUserScriptInjector.Entry
    {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        try register(store, scripts)
        for world in worlds {
            _ = try store.handle("configureWorld", ["properties": world], extensionID: Self.extensionID)
        }
        return ExtensionUserScriptInjector.Entry(
            extensionID: Self.extensionID,
            access: .init(allURLs: true, granted: [], denied: []),
            allowsPrivate: allowsPrivate,
            registered: store.registered(for: Self.extensionID)
        )
    }

    @Test func plansThePagesScripts() throws {
        guard #available(macOS 15.4, *) else { return }
        let entry = try entry([
            Self.script("a", ["runAt": "document_start", "js": [["code": "1"], ["code": "2"]]]),
            Self.script("b", ["world": "MAIN", "allFrames": true, "matches": ["*://*/*"], "worldId": NSNull()]),
            Self.script("c", ["worldId": "quiet"])
        ], worlds: [["messaging": true], ["worldId": "quiet", "messaging": false]])
        let page = try #require(URL(string: "https://example.com/x"))
        let plan = ExtensionUserScriptInjector.plan([entry], isPrivate: false, url: page)
        let defaultWorld = ExtensionUserScriptInjector.worldName(extensionID: Self.extensionID, worldId: nil)
        let quiet = ExtensionUserScriptInjector.worldName(extensionID: Self.extensionID, worldId: "quiet")
        // Its runtime first, in the world with messaging only; then each source, in order.
        #expect(plan.scripts.map(\.worldName) == [defaultWorld, defaultWorld, defaultWorld, nil, quiet])
        #expect(plan.worlds.map(\.worldId) == [nil])
        #expect(plan.scripts[0].source.contains(ExtensionUserScriptMessages.handlerName) && plan.scripts[0]
            .forMainFrameOnly)
        // A script of the main frame that runs here: as it is, Ombre decided.
        #expect(plan.scripts[1].source == "1" && plan.scripts[1].injectionTime == .atDocumentStart)
        // A script of every frame: guarded in each.
        #expect(plan.scripts[3].source.hasPrefix("if (") && !plan.scripts[3].forMainFrameOnly)
        #expect(plan.scripts[3].injectionTime == .atDocumentEnd)

        // Another website, or not known yet: only the script of every frame.
        let other = try #require(URL(string: "https://other.com/"))
        #expect(ExtensionUserScriptInjector.plan([entry], isPrivate: false, url: other).scripts
            .map(\.worldName) == [nil])
        #expect(ExtensionUserScriptInjector.plan([entry], isPrivate: false, url: nil).worlds.isEmpty)
        // Private windows: only an extension allowed there.
        #expect(ExtensionUserScriptInjector.plan([entry], isPrivate: true, url: page).scripts.isEmpty)
        let allowed = try self.entry([Self.script("a")], allowsPrivate: true)
        #expect(ExtensionUserScriptInjector.plan([allowed], isPrivate: true, url: page).scripts.count == 1)
    }

    /// In a real page: the main world's script sees the page, the user
    /// script world's doesn't, and none runs on another website.
    @Test func runsInARealPage() async throws {
        guard #available(macOS 15.4, *) else { return }
        let isolated = """
        window.webkit.messageHandlers.probe.postMessage(
          [typeof pageValue, typeof chrome.runtime.sendMessage, chrome.runtime.id === "\(Self.extensionID)"].join(" "));
        """
        let escape = "}\nwindow.webkit.messageHandlers.probe.postMessage('escaped');\nif (0) {"
        let escapeMain = "}\nwindow.escaped = true;\nif (0) {"
        let sharedCheck = "window.webkit.messageHandlers.probe.postMessage('shared ' + sharedValue);"
        let entry = try entry([
            Self.script("main", ["world": "MAIN", "js": [["code": "window.ranMain = typeof pageValue;"]]]),
            Self.script("isolated", ["js": [["code": isolated]]]),
            Self.script("elsewhere", ["matches": ["https://other.com/*"], "js": [["code": "window.ranOther = true;"]]]),
            // Of every frame, for another website: stopped, and the page sees no error.
            Self.script(
                "framesElsewhere",
                ["matches": ["https://other.com/*"], "allFrames": true, "js": [["code": "1"]]]
            ),
            // For another website: not even its declarations here.
            Self.script(
                "declares",
                ["matches": ["https://other.com/*"], "world": "MAIN", "js": [["code": "var leaked = 1;"]]]
            ),
            // Code that tries to end its guard early: never runs, in either world.
            Self.script("escape", ["matches": ["https://other.com/*"], "allFrames": true, "js": [["code": escape]]]),
            Self.script("escapeMain", [
                "matches": ["https://other.com/*"], "world": "MAIN", "allFrames": true, "js": [["code": escapeMain]]
            ]),
            // Two sources share their declarations, as two scripts of one world.
            Self.script("shared", ["js": [["code": "const sharedValue = 2;"], ["code": sharedCheck]]])
        ], worlds: [["messaging": true]])
        let controller = WKUserContentController()
        let probe = UserScriptProbe()
        let world = WKContentWorld.world(
            name: ExtensionUserScriptInjector.worldName(extensionID: Self.extensionID, worldId: nil)
        )
        controller.add(probe, contentWorld: world, name: "probe")
        controller.add(probe, contentWorld: world, name: ExtensionUserScriptMessages.handlerName)
        for planned in ExtensionUserScriptInjector.plan(
            [entry],
            isPrivate: false,
            url: URL(string: "https://example.com/page")
        )
        .scripts {
            controller.addUserScript(WKUserScript(
                source: planned.source,
                injectionTime: planned.injectionTime,
                forMainFrameOnly: planned.forMainFrameOnly,
                in: planned.worldName.map { WKContentWorld.world(name: $0) } ?? .page
            ))
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(
            """
            <script>var pageValue = 1; window.pageErrors = 0;
            addEventListener("error", () => { window.pageErrors++; });</script>
            """, baseURL: URL(string: "https://example.com/page")
        )
        try await delegate.wait()
        try await probe.wait(for: 2)
        #expect(probe.messages == ["undefined function true", "shared 2"])
        let ran = "[window.ranMain, window.ranOther, window.escaped, 'leaked' in window, pageErrors].map(String).join(' ')"
        let got = try await webView.evaluateJavaScript(ran) as? String
        #expect(got == "number undefined undefined false 0", "\(got ?? "nil")")
    }

    /// In a page of Ombre: added beside its own scripts (kept), the same
    /// objects while nothing changes, replaced when they change, and none
    /// in an extension's page.
    @Test func installsInAPage() throws {
        guard #available(macOS 15.4, *) else { return }
        let injector = ExtensionUserScriptInjector()
        var entries = try [entry([Self.script("a")], worlds: [["messaging": true]])]
        injector.entries = { entries }
        let page = BrowserPage(
            profile: BrowserEngine.shared.makeProfile(identifier: UUID(), isPrivate: false),
            configuration: .ombreDefault(userScripts: [], privacySettings: SpacePrivacySettings()),
            delegate: nil
        )
        defer { page.teardown() }
        let controller = page.webView.configuration.userContentController
        let own = controller.userScripts.count
        injector.attach(page)
        // Nothing until the page's address is known: its script is for example.com.
        #expect(controller.userScripts.count == own)
        injector.prepare(page, for: URL(string: "https://example.com/"))
        #expect(controller.userScripts.count == own + 2 && page.extensionUserScriptWorlds.count == 1)
        let installed = page.extensionUserScripts.map(ObjectIdentifier.init)
        injector.refresh()
        #expect(page.extensionUserScripts.map(ObjectIdentifier.init) == installed)

        entries = try [entry([Self.script("a"), Self.script("b")])]
        injector.refresh()
        #expect(controller.userScripts.count == own + 2 && page.extensionUserScriptWorlds.isEmpty)
        entries = []
        injector.refresh()
        #expect(controller.userScripts.count == own && page.extensionUserScripts.isEmpty)

        entries = try [entry([Self.script("a")])]
        injector.refresh()
        injector.detach(page)
        #expect(controller.userScripts.count == own)
    }

    /// What Ombre relies on: a script added while WebKit asks whether to
    /// load a page (`decidePolicyFor`) runs in that page.
    @Test func aScriptAddedBeforeTheLoadRunsInIt() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = AddingWaiter()
        webView.navigationDelegate = delegate
        webView.loadHTMLString("<p>page</p>", baseURL: URL(string: "https://example.com/"))
        try await delegate.wait()
        #expect(try await webView.evaluateJavaScript("String(window.addedBefore)") as? String == "yes")
    }

    // MARK: - The channel's refusals

    @available(macOS 15.4, *)
    func context(permissions: [String]) async throws -> WKWebExtensionContext {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("userscripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let list = permissions.map { "\"\($0)\"" }.joined(separator: ",")
        let manifest = #"{"manifest_version":3,"name":"U","version":"1","permissions":[\#(list)]}"#
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
        context.uniqueIdentifier = Self.extensionID
        return context
    }

    @available(macOS 15.4, *)
    func complements() throws -> (ExtensionComplements, URL) {
        let defaults = try #require(UserDefaults(suiteName: "ExtensionUserScriptsTests-\(UUID().uuidString)"))
        let (store, folder) = makeStore()
        let complements = ExtensionComplements(
            privacy: ExtensionPrivacy(settings: PrivacySetting(), defaults: defaults, key: "privacy"),
            userScripts: store,
            grants: ExtensionComplementGrants(defaults: defaults, key: "grants")
        )
        complements.userScriptsAllowed = { _ in true }
        return (complements, folder)
    }

    @Test func refusedWithoutThePermission() async throws {
        guard #available(macOS 15.4, *) else { return }
        let (complements, folder) = try complements()
        defer { try? FileManager.default.removeItem(at: folder) }
        let without = try await context(permissions: ["storage"])
        let call: [String: Any] = [
            "api": "userScripts",
            "method": "register",
            "details": ["scripts": [Self.script("a")]]
        ]
        await #expect(throws: ExtensionComplementFailure.notAllowed("userScripts")) {
            try await complements.handle(call, from: without)
        }
        #expect(complements.userScripts.registered(for: Self.extensionID).scripts.isEmpty)

        let with = try await context(permissions: ["userScripts"])
        _ = try await complements.handle(call, from: with)
        // The extension is the context's, whatever the message says.
        #expect(complements.userScripts.registered(for: Self.extensionID).scripts.map(\.id) == ["a"])
        complements.userScripts.forget(id: Self.extensionID)
    }

    @Test func messagesAreChecked() async throws {
        guard #available(macOS 15.4, *) else { return }
        let with = try await context(permissions: ["userScripts"])
        let without = try await context(permissions: ["storage"])
        var registered = ExtensionUserScripts.Registered()
        registered.worlds = [
            .init(worldId: nil, csp: nil, messaging: true),
            .init(worldId: "off", csp: nil, messaging: false)
        ]
        var current = with
        var readable = true
        let messages = ExtensionUserScriptMessages(checks: .init(
            context: { $0 == Self.extensionID ? current : nil },
            allowsUserScripts: { ExtensionComplementScript.permissions.contains("userScripts")
                && ExtensionComplements.declaredPermissions(of: $0.webExtension).required.contains("userScripts")
            },
            registered: { _ in registered },
            mayRead: { _, _ in readable }
        ))
        func origin(worldId: String? = nil, name: String? = nil, isPrivate: Bool = false, extensionID: String? = nil)
            -> ExtensionUserScriptMessages.Origin
        {
            let extensionID = extensionID ?? Self.extensionID
            let world = ExtensionUserScriptInjector.MessagingWorld(
                extensionID: extensionID,
                worldId: worldId,
                name: ExtensionUserScriptInjector.worldName(extensionID: extensionID, worldId: worldId)
            )
            return .init(
                world: world,
                worldName: name ?? world.name,
                frameURL: URL(string: "https://example.com/"),
                isMainFrame: true,
                isPrivate: isPrivate
            )
        }
        #expect(throws: Never.self) { try messages.check(origin()) }
        // Posted from another world than its handler's.
        #expect(throws: ExtensionComplementFailure.self) { try messages.check(origin(name: "page")) }
        // Another extension, not running.
        #expect(throws: ExtensionComplementFailure.self) { try messages.check(origin(extensionID: UUID().uuidString)) }
        // A world without messaging.
        #expect(throws: ExtensionComplementFailure.self) { try messages.check(origin(worldId: "off")) }
        // A private window, the extension not allowed there.
        #expect(throws: ExtensionComplementFailure.self) { try messages.check(origin(isPrivate: true)) }
        // A website it may not read.
        readable = false
        #expect(throws: ExtensionComplementFailure.self) { try messages.check(origin()) }
        readable = true
        // Its manifest doesn't ask for the API.
        current = without
        #expect(throws: ExtensionComplementFailure.notAllowed("userScripts")) { try messages.check(origin()) }
    }

    /// In the service worker of Ombre's copy: a file's code read from the
    /// package, and a user script's message answered by the worker.
    @Test func inAServiceWorker() async throws {
        guard #available(macOS 15.4, *) else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("userscripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = [
            "manifest.json": #"{"manifest_version":3,"name":"U","version":"1","permissions":["userScripts"],"host_permissions":["<all_urls>"],"background":{"service_worker":"sw.js"}}"#,
            "user.js": "window.fromFile = 1;",
            "sw.js": """
            chrome.runtime.onUserScriptMessage.addListener((message, sender, respond) => {
              setTimeout(() => respond({ echo: message.text, url: sender.url }), 10);
              return true;
            });
            chrome.userScripts.configureWorld({ messaging: true })
              .then(() => chrome.userScripts.register([{ id: "f", matches: ["https://example.com/*"], js: [{ file: "user.js" }] }]))
              .then(() => chrome.userScripts.getScripts({ ids: ["f"] }))
              .then(scripts => browser.runtime.sendNativeMessage("probe", JSON.stringify(scripts[0].js)))
              .catch(error => browser.runtime.sendNativeMessage("probe", "error " + error.message));
            """
        ]
        for (path, content) in files {
            try content.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        #expect(ExtensionComplementPackage.add(toFolder: folder) != nil)
        #expect(ExtensionComplementPackage.setUserScriptsAllowed(true, at: folder.path))
        let (complements, storeFolder) = try complements()
        defer { try? FileManager.default.removeItem(at: storeFolder) }
        let delegate = WorkerProbe(complements: complements)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = delegate
        ExtensionBaseURL.registerScheme()
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
        let id = Self.extensionID
        context.uniqueIdentifier = id
        ExtensionBaseURL.apply(to: context, id: id)
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        context.setPermissionStatus(.grantedExplicitly, for: .userScripts)
        try context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.MatchPattern(string: "<all_urls>"))
        complements.loadedContext = { $0 == id ? context : nil }
        try controller.load(context)
        defer {
            try? controller.unload(context)
            complements.userScripts.forget(id: id)
        }
        try await delegate.wait()
        #expect(delegate.messages == [#"[{"file":"user.js"}]"#])
        #expect(complements.userScripts.registered(for: id).scripts.first?.sources.first?
            .code == "window.fromFile = 1;")

        let world = ExtensionUserScriptInjector.plan([.init(
            extensionID: id,
            access: .init(allURLs: true, granted: [], denied: []),
            allowsPrivate: false,
            registered: complements.userScripts.registered(for: id)
        )], isPrivate: false, url: URL(string: "https://example.com/a")).worlds
        let messagingWorld = try #require(world.first)
        let reply = try await complements.userScriptMessages.send(["message": ["text": "hi"]], from: .init(
            world: messagingWorld,
            worldName: messagingWorld.name,
            frameURL: URL(string: "https://example.com/a"),
            isMainFrame: true,
            isPrivate: false
        ))
        let value = try #require(reply as? [String: Any])
        #expect(value["echo"] as? String == "hi" && value["url"] as? String == "https://example.com/a")
    }
}

@available(macOS 15.4, *)
extension WKWebExtension.Permission {
    static let userScripts = WKWebExtension.Permission(rawValue: "userScripts")
}

final class PrivacySetting: PasswordSavingSetting {
    var passwordSavePromptsEnabled = true
}

@MainActor
private final class UserScriptProbe: NSObject, WKScriptMessageHandler {
    var messages: [String] = []

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "probe" { messages.append(message.body as? String ?? "") }
    }

    func wait(for count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while messages.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        // A little longer: nothing more should come.
        try await Task.sleep(for: .milliseconds(200))
        if messages.count < count { Issue.record("The page said \(messages)") }
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var done = false

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        done = true
    }

    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !done, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if !done { Issue.record("The page didn't load") }
    }
}

@MainActor
private final class AddingWaiter: NSObject, WKNavigationDelegate {
    private var done = false

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: "window.addedBefore = 'yes';", injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        decisionHandler(.allow)
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        done = true
    }

    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !done, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if !done { Issue.record("The page didn't load") }
    }
}

/// The tests' controller delegate: Ombre's channel (messages and port),
/// and "probe" for what the worker says.
@available(macOS 15.4, *)
@MainActor
final class WorkerProbe: NSObject, WKWebExtensionControllerDelegate {
    let complements: ExtensionComplements
    var messages: [String] = []

    init(complements: ExtensionComplements) {
        self.complements = complements
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        if applicationIdentifier == ExtensionComplements.applicationIdentifier {
            Task { @MainActor in
                do {
                    let value = try await complements.handle(message, from: extensionContext)
                    replyHandler(["value": value ?? NSNull()], nil)
                } catch {
                    replyHandler(["error": error.localizedDescription], nil)
                }
            }
            return
        }
        messages.append(message as? String ?? "\(message)")
        replyHandler(nil, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        _ = complements.connect(port, for: extensionContext)
        completionHandler(nil)
    }

    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while messages.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if messages.isEmpty { Issue.record("The worker said nothing") }
    }
}
