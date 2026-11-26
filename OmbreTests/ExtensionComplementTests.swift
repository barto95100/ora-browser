import Compression
import Foundation
@testable import Ombre
import Testing
import WebKit

/// The APIs Ombre adds to extensions (`ExtensionComplements`): in real
/// extension pages and service workers of a controller of the tests' own
/// (never the app's), with a setting of their own.
@MainActor
@Suite(.serialized)
struct ExtensionComplementTests {
    /// "Prompt to save passwords", for the tests only.
    final class Setting: PasswordSavingSetting {
        var passwordSavePromptsEnabled = true
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ExtensionComplementTests-\(UUID().uuidString)"))
    }

    @available(macOS 15.4, *)
    private func makeComplements(_ setting: Setting) throws -> ExtensionComplements {
        let defaults = try makeDefaults()
        return ExtensionComplements(
            privacy: ExtensionPrivacy(settings: setting, defaults: defaults, key: "privacy"),
            grants: ExtensionComplementGrants(defaults: defaults, key: "grants")
        )
    }

    private static func makeExtension(_ files: [String: String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("complement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, content) in files {
            try content.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        return folder
    }

    // MARK: - Privacy

    @Test func passwordSavingIsOmbresSetting() throws {
        let setting = Setting()
        let privacy = try ExtensionPrivacy(settings: setting, defaults: makeDefaults(), key: "privacy")
        let set = ["setting": "services.passwordSavingEnabled", "details": ["value": false]] as [String: Any]
        _ = try privacy.handle("set", set, extensionID: "a", extensionName: "Bitwarden")
        #expect(!setting.passwordSavePromptsEnabled)
        #expect(privacy.passwordSavingControllerName == "Bitwarden")

        let get = ["setting": "services.passwordSavingEnabled"] as [String: Any]
        let mine = try #require(privacy.handle("get", get, extensionID: "a", extensionName: nil) as? [String: Any])
        #expect(mine["value"] as? Bool == false && mine["levelOfControl"] as? String == "controlled_by_this_extension")
        let theirs = try #require(privacy.handle("get", get, extensionID: "b", extensionName: nil) as? [String: Any])
        #expect(theirs["levelOfControl"] as? String == "controlled_by_other_extensions")

        // Another extension's clear changes nothing; its own gives it back.
        _ = try privacy.handle("clear", get, extensionID: "b", extensionName: nil)
        #expect(!setting.passwordSavePromptsEnabled)
        _ = try privacy.handle("clear", get, extensionID: "a", extensionName: nil)
        #expect(setting.passwordSavePromptsEnabled && privacy.passwordSavingController == nil)

        // The user changing it: theirs again, the extension's removal changes nothing.
        _ = try privacy.handle("set", set, extensionID: "a", extensionName: "Bitwarden")
        setting.passwordSavePromptsEnabled = true
        privacy.userChangedPasswordSaving()
        privacy.release(extensionID: "a")
        #expect(setting.passwordSavePromptsEnabled)
    }

    /// What Ombre can't change: read, never set (as Chrome's "not_controllable").
    @Test func otherSettingsAreNotControllable() throws {
        let privacy = try ExtensionPrivacy(settings: Setting(), defaults: makeDefaults(), key: "privacy")
        let webRTC = ["setting": "network.webRTCIPHandlingPolicy"] as [String: Any]
        let value = try #require(privacy.handle("get", webRTC, extensionID: "a", extensionName: nil) as? [String: Any])
        #expect(value["levelOfControl"] as? String == "not_controllable")
        #expect(throws: ExtensionComplementFailure.self) {
            try privacy.handle(
                "set",
                ["setting": "network.networkPredictionEnabled", "details": ["value": false]],
                extensionID: "a",
                extensionName: nil
            )
        }
        // A password manager turns them all off: already off here.
        _ = try privacy.handle(
            "set",
            ["setting": "services.autofillAddressEnabled", "details": ["value": false]],
            extensionID: "a",
            extensionName: nil
        )
        #expect(throws: ExtensionComplementFailure.self) {
            try privacy.handle(
                "get",
                ["setting": "services.passwordSavingEnabled", "details": ["scope": "incognito_persistent"]],
                extensionID: "a",
                extensionName: nil
            )
        }
    }

    @Test func passwordManagersAreKnown() {
        #expect(PasswordManagerExtensionOffer.isPasswordManager("Bitwarden Password Manager"))
        #expect(PasswordManagerExtensionOffer.isPasswordManager("1Password – Password Manager"))
        #expect(PasswordManagerExtensionOffer.isPasswordManager("Proton Pass: Free Password Manager"))
        #expect(!PasswordManagerExtensionOffer.isPasswordManager("uBlock Origin Lite"))
    }

    // MARK: - The channel's checks

    /// Only what the manifest asks for, and the extension is the one WebKit
    /// gives (the context), never one the message names.
    @Test func theChannelChecksTheSendersManifest() async throws {
        guard #available(macOS 15.4, *) else { return }
        let setting = Setting()
        let complements = try makeComplements(setting)
        let without = try await context(manifest: #"{"manifest_version":3,"name":"A","version":"1"}"#)
        let call: [String: Any] = [
            "api": "privacy", "method": "set", "extensionID": "other",
            "details": ["setting": "services.passwordSavingEnabled", "details": ["value": false]]
        ]
        await #expect(throws: ExtensionComplementFailure.notAllowed("privacy")) {
            try await complements.handle(call, from: without)
        }
        #expect(setting.passwordSavePromptsEnabled)
        // Not an API Ombre adds: nothing reached through the channel.
        await #expect(throws: ExtensionComplementFailure.self) {
            try await complements.handle(["api": "tabs", "method": "query", "details": [:]], from: without)
        }

        let with = try await context(
            manifest: #"{"manifest_version":3,"name":"B","version":"1","permissions":["privacy"]}"#
        )
        _ = try await complements.handle(call, from: with)
        #expect(!setting.passwordSavePromptsEnabled)
        #expect(complements.privacy.passwordSavingController == with.uniqueIdentifier)
        // Turned off: the setting as it was, as in Chrome.
        complements.extensionDisabled(id: with.uniqueIdentifier)
        #expect(setting.passwordSavePromptsEnabled && complements.privacy.passwordSavingController == nil)
    }

    /// Optional: only once the user allowed it (`permissions.request`, Ombre's
    /// dialog), as in Chrome; a refusal isn't asked again.
    @Test func optionalPermissionsOnceRequested() async throws {
        guard #available(macOS 15.4, *) else { return }
        let complements = try makeComplements(Setting())
        var asked: [[String]] = []
        var allow = false
        complements.askUser = { names, _, answer in
            asked.append(names)
            answer(allow)
        }
        let optional = try await context(
            manifest: #"{"manifest_version":3,"name":"C","version":"1","optional_permissions":["privacy"]}"#
        )
        #expect(!complements.allows("privacy", for: optional))
        let request: [String: Any] = [
            "api": "permissions",
            "method": "request",
            "details": ["permissions": ["privacy"]]
        ]
        #expect(try await complements.handle(request, from: optional) as? Bool == false)
        allow = true
        #expect(try await complements.handle(request, from: optional) as? Bool == false)
        #expect(asked == [["privacy"]])
        let another = try await context(
            manifest: #"{"manifest_version":3,"name":"D","version":"1","optional_permissions":["privacy"]}"#
        )
        #expect(try await complements.handle(request, from: another) as? Bool == true)
        #expect(complements.allows("privacy", for: another))
        // Not in its manifest: never.
        let other: [String: Any] = [
            "api": "permissions",
            "method": "request",
            "details": ["permissions": ["offscreen"]]
        ]
        await #expect(throws: ExtensionComplementFailure.self) { try await complements.handle(other, from: optional) }
    }

    @available(macOS 15.4, *)
    private func context(manifest: String) async throws -> WKWebExtensionContext {
        let folder = try Self.makeExtension(["manifest.json": manifest])
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
        context.uniqueIdentifier = UUID().uuidString
        return context
    }

    // MARK: - In real extension pages

    /// A background page (as the Bitwarden of its app): the API is there,
    /// without anything of its package changed, and changes Ombre's setting.
    @Test func privacyInAnExtensionPage() async throws {
        guard #available(macOS 15.4, *) else { return }
        let setting = Setting()
        let messages = try await runPage(setting: setting, files: [
            "manifest.json": #"{"manifest_version":2,"name":"P","version":"1","permissions":["privacy"],"background":{"page":"bg.html","persistent":true}}"#,
            "bg.html": "<script src=bg.js></script>",
            "bg.js": """
            (async () => {
              const saving = chrome.privacy.services.passwordSavingEnabled;
              await saving.set({ value: false });
              const value = await saving.get({});
              const webRTC = await chrome.privacy.network.webRTCIPHandlingPolicy.get({});
              let refused = false;
              try { await chrome.privacy.network.networkPredictionEnabled.set({ value: false }); } catch (e) { refused = true; }
              const granted = await browser.permissions.contains({ permissions: ["privacy"] });
              probe([value.value, value.levelOfControl, webRTC.levelOfControl, refused, granted].join(" "));
            })().catch(error => probe("error " + error.message));
            """
        ])
        #expect(messages == ["false controlled_by_this_extension not_controllable true true"])
        #expect(!setting.passwordSavePromptsEnabled)
    }

    /// Without the permission: no API, and writing to the channel itself is refused.
    @Test func refusedWithoutThePermission() async throws {
        guard #available(macOS 15.4, *) else { return }
        let setting = Setting()
        let messages = try await runPage(setting: setting, files: [
            "manifest.json": #"{"manifest_version":2,"name":"N","version":"1","background":{"page":"bg.html","persistent":true}}"#,
            "bg.html": "<script src=bg.js></script>",
            "bg.js": """
            webkit.messageHandlers.ombreComplement.postMessage({ api: "privacy", method: "set",
              details: { setting: "services.passwordSavingEnabled", details: { value: false } } })
              .then(reply => probe(typeof chrome.privacy + " " + reply.error));
            """
        ])
        #expect(messages.first?.hasPrefix("undefined 'privacy' requires the \"privacy\" permission") == true)
        #expect(setting.passwordSavePromptsEnabled)
    }

    /// `chrome.offscreen`: one hidden page of the extension's own.
    @Test func offscreenDocument() async throws {
        guard #available(macOS 15.4, *) else { return }
        let messages = try await runPage(setting: Setting(), count: 2, files: [
            "manifest.json": #"{"manifest_version":2,"name":"O","version":"1","permissions":["offscreen"],"background":{"page":"bg.html","persistent":true}}"#,
            "bg.html": "<script src=bg.js></script>",
            "off.html": "<script src=off.js></script>",
            "off.js": "probe('offscreen ' + location.pathname);",
            "bg.js": """
            (async () => {
              await chrome.offscreen.createDocument({ url: "off.html", reasons: ["DOM_PARSER"], justification: "test" });
              const has = await chrome.offscreen.hasDocument();
              let again = "";
              try { await chrome.offscreen.createDocument({ url: "off.html", reasons: ["DOM_PARSER"], justification: "x" }); }
              catch (e) { again = "second refused"; }
              const contexts = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"] });
              await chrome.offscreen.closeDocument();
              // Closed while it loads: its creation answers (an error).
              const loading = chrome.offscreen.createDocument({ url: "off.html", reasons: ["DOM_PARSER"], justification: "y" });
              await chrome.offscreen.closeDocument();
              const cancelled = await loading.then(() => "loaded", () => "cancelled");
              probe([has, again, contexts.length, cancelled, await chrome.offscreen.hasDocument()].join(" "));
            })().catch(error => probe("error " + error.message));
            """
        ])
        #expect(messages.contains("true second refused 1 cancelled false"))
        #expect(messages.contains("offscreen /off.html"))
        // Never another site, nor another extension.
        let base = try #require(URL(string: "safari-web-extension://abc/"))
        #expect(OffscreenDocuments.url("off.html", in: base)?.absoluteString == "safari-web-extension://abc/off.html")
        #expect(OffscreenDocuments.url("https://example.com/", in: base) == nil)
        #expect(OffscreenDocuments.url("safari-web-extension://other/off.html", in: base) == nil)
    }

    @available(macOS 15.4, *)
    private func runPage(setting: Setting, count: Int = 1, files: [String: String]) async throws -> [String] {
        let folder = try Self.makeExtension(files)
        defer { try? FileManager.default.removeItem(at: folder) }
        let complements = try makeComplements(setting)
        let probe = Probe()
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        let pages = configuration.webViewConfiguration ?? WKWebViewConfiguration()
        let handler = ExtensionComplementHandler()
        ExtensionComplements.configure(pages, handler: handler)
        pages.userContentController.addUserScript(WKUserScript(
            source: "window.probe = text => webkit.messageHandlers.probe.postMessage(String(text));",
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page
        ))
        pages.userContentController.add(probe, contentWorld: .page, name: "probe")
        configuration.webViewConfiguration = pages
        let controller = WKWebExtensionController(configuration: configuration)
        handler.target = { (complements, controller) }
        ExtensionBaseURL.registerScheme()
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
        let id = UUID().uuidString
        context.uniqueIdentifier = id
        ExtensionBaseURL.apply(to: context, id: id)
        try controller.load(context)
        defer {
            complements.extensionUnloaded(context)
            try? controller.unload(context)
        }
        try await probe.wait(for: count)
        return probe.messages
    }

    // MARK: - Ombre's copies with a service worker

    @Test func onlyWorkersThatAskForAnAddedAPI() throws {
        let worker = #"{"manifest_version":3,"name":"W","version":"1","background":{"service_worker":"sw.js"}"#
        #expect(ExtensionComplementPackage
            .changes(forManifest: Data((worker + #","permissions":["storage"]}"#).utf8)) == nil)
        let page = #"{"manifest_version":2,"name":"P","version":"1","permissions":["privacy"]}"#
        #expect(ExtensionComplementPackage.changes(forManifest: Data(page.utf8)) == nil)

        let module = worker.replacingOccurrences(of: #""sw.js""#, with: #""sw.js","type":"module""#)
        let changes = try #require(ExtensionComplementPackage.changes(
            forManifest: Data((module + #","optional_permissions":["offscreen"]}"#).utf8)
        ))
        #expect(changes.added == .init(apis: ["offscreen"], permissions: ["nativeMessaging"]))
        let manifest = try #require(try JSONSerialization.jsonObject(with: changes.manifest) as? [String: Any])
        #expect((manifest["background"] as? [String: Any])?["service_worker"] as? String
            == ExtensionComplementPackage.wrapperName)
        #expect(manifest["permissions"] as? [String] == ["nativeMessaging"])
        let wrapper = try #require(changes.files[ExtensionComplementPackage.wrapperName])
        #expect(String(decoding: wrapper, as: UTF8.self).contains(#"import "./sw.js";"#))
        // Beside a worker in a folder (its relative addresses stay right).
        let nested = worker.replacingOccurrences(of: #""sw.js""#, with: #""js/sw.js""#) + #","permissions":["privacy"]}"#
        let inFolder = try #require(ExtensionComplementPackage.changes(forManifest: Data(nested.utf8)))
        #expect(inFolder.files["js/" + ExtensionComplementPackage.wrapperName] != nil)
    }

    /// A `.zip` copy: its files as they were (one deflated), Ombre's added.
    @Test func aZipCopyKeepsItsFiles() async throws {
        let manifest = #"{"manifest_version":3,"name":"Z","version":"1","permissions":["privacy","nativeMessaging"],"background":{"service_worker":"sw.js"}}"#
        let worker = String(repeating: "console.log('worker');\n", count: 50)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("complement-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestZip.make(["manifest.json": Data(manifest.utf8), "sw.js": Data(worker.utf8)], deflated: ["sw.js"])
            .write(to: url)

        let added = try #require(ExtensionComplementPackage.add(toZip: url))
        // It asked for native messaging itself: nothing added to its permissions.
        #expect(added == .init(apis: ["privacy"], permissions: []))
        #expect(ExtensionComplementPackage.added(at: url.path) == added)
        let archive = try ZipArchive(Data(contentsOf: url))
        #expect(try archive.contents(of: #require(archive.entry(named: "sw.js"))) == Data(worker.utf8))
        #expect(archive.entry(named: ExtensionComplementPackage.complementFile) != nil)
        // Done once: a second time changes nothing.
        #expect(ExtensionComplementPackage.add(toZip: url) == nil)
        if #available(macOS 15.4, *) {
            let webExtension = try await WKWebExtension(resourceBaseURL: url)
            #expect(webExtension.hasBackgroundContent)
        }
    }

    /// In the service worker of Ombre's copy: the API through Ombre's own
    /// native messaging channel.
    @Test func privacyInAServiceWorker() async throws {
        guard #available(macOS 15.4, *) else { return }
        let folder = try Self.makeExtension([
            "manifest.json": #"{"manifest_version":3,"name":"S","version":"1","permissions":["privacy"],"background":{"service_worker":"sw.js"}}"#,
            "lib.js": "self.fromLib = 'lib';",
            "sw.js": """
            importScripts("lib.js");
            const saving = chrome.privacy.services.passwordSavingEnabled;
            saving.set({ value: false }).then(() => saving.get({}))
              .then(value => browser.permissions.contains({ permissions: ["nativeMessaging"] })
                .then(native => browser.runtime.sendNativeMessage("probe",
                  [self.fromLib, value.value, value.levelOfControl, native].join(" "))))
              .catch(error => browser.runtime.sendNativeMessage("probe", "error " + error.message));
            """
        ])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ExtensionComplementPackage.add(toFolder: folder) != nil)
        let setting = Setting()
        let complements = try makeComplements(setting)
        let delegate = NativeProbe(complements: complements)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = delegate
        ExtensionBaseURL.registerScheme()
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
        let id = UUID().uuidString
        context.uniqueIdentifier = id
        ExtensionBaseURL.apply(to: context, id: id)
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        try controller.load(context)
        defer { try? controller.unload(context) }
        try await delegate.wait()
        // Its own relative addresses still right (beside its worker).
        // Its own relative addresses still right (beside its worker), and
        // native messaging is Ombre's, not the extension's: it doesn't see it.
        #expect(delegate.messages == ["lib false controlled_by_this_extension false"])
        #expect(!setting.passwordSavePromptsEnabled)
    }
}

/// What the test pages say (`probe(text)`).
@MainActor
private final class Probe: NSObject, WKScriptMessageHandler {
    var messages: [String] = []

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append(message.body as? String ?? "")
    }

    func wait(for count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while messages.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if messages.count < count { Issue.record("Pages said \(messages)") }
    }
}

/// The tests' controller delegate: Ombre's channel, and "probe" for what
/// the worker says.
@available(macOS 15.4, *)
@MainActor
private final class NativeProbe: NSObject, WKWebExtensionControllerDelegate {
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

    func wait() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while messages.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if messages.isEmpty { Issue.record("The worker said nothing") }
    }
}

/// A `.zip` made as zip tools do, some files deflated.
private enum TestZip {
    static func make(_ files: [String: Data], deflated: Set<String>) throws -> Data {
        var output = Data()
        var central = Data()
        for (name, content) in files.sorted(by: { $0.key < $1.key }) {
            let stored = deflated.contains(name) ? try deflate(content) : content
            let method: UInt16 = deflated.contains(name) ? 8 : 0
            let crc = CRC32.checksum(content)
            let nameData = Data(name.utf8)
            let offset = UInt32(output.count)
            output.append(contentsOf: le32(0x04034B50) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0x21))
            output.append(contentsOf: le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(content.count)))
            output.append(contentsOf: le16(UInt16(nameData.count)) + le16(0))
            output.append(nameData)
            output.append(stored)
            central.append(contentsOf: le32(0x02014B50) + le16(20) + le16(20) + le16(0) + le16(method) + le16(0))
            central
                .append(contentsOf: le16(0x21) + le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(content.count)))
            central.append(contentsOf: le16(UInt16(nameData.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0))
            central.append(contentsOf: le32(offset))
            central.append(nameData)
        }
        let start = UInt32(output.count)
        output.append(central)
        output.append(contentsOf: le32(0x06054B50) + le16(0) + le16(0) + le16(UInt16(files.count)))
        output.append(contentsOf: le16(UInt16(files.count)) + le32(UInt32(central.count)) + le32(start) + le16(0))
        return output
    }

    private static func deflate(_ data: Data) throws -> Data {
        var output = Data(count: data.count + 64)
        let size = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_encode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, data.count + 64,
                    input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        try #require(size > 0)
        return output.prefix(size)
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        le16(UInt16(value & 0xFFFF)) + le16(UInt16(value >> 16))
    }
}
