import Foundation
@testable import Ombre
import Testing
import WebKit

/// "Allow User Scripts" (Settings › Extensions), as in Chrome.
extension ExtensionUserScriptsTests {
    /// "Allow User Scripts" off: refused as in Chrome, and its scripts stop.
    @Test func refusedWhileTheUserDidntAllowThem() async throws {
        guard #available(macOS 15.4, *) else { return }
        let (complements, folder) = try complements()
        defer { try? FileManager.default.removeItem(at: folder) }
        let with = try await context(permissions: ["userScripts"])
        let call: [String: Any] = [
            "api": "userScripts",
            "method": "register",
            "details": ["scripts": [Self.script("a")]]
        ]
        _ = try await complements.handle(call, from: with)
        #expect(complements.runsUserScripts(with))
        complements.userScriptsAllowed = { _ in false }
        #expect(!complements.runsUserScripts(with))
        await #expect(throws: ExtensionComplementFailure.userScriptsOff) {
            try await complements.handle(call, from: with)
        }
        // The permission itself is still the extension's, as in Chrome.
        let contains: [String: Any] = [
            "api": "permissions", "method": "contains", "details": ["permissions": ["userScripts"]]
        ]
        #expect(try await complements.handle(contains, from: with) as? Bool == true)
        // Its scripts' messages are refused.
        complements.loadedContext = { $0 == Self.extensionID ? with : nil }
        let messages = complements.userScriptMessages
        #expect(throws: ExtensionComplementFailure.notAllowed("userScripts")) {
            try messages.check(.init(
                world: .init(
                    extensionID: Self.extensionID,
                    worldId: nil,
                    name: ExtensionUserScriptInjector
                        .worldName(extensionID: Self.extensionID, worldId: nil)
                ),
                worldName: ExtensionUserScriptInjector.worldName(extensionID: Self.extensionID, worldId: nil),
                frameURL: URL(string: "https://example.com/"),
                isMainFrame: true,
                isPrivate: false
            ))
        }
        complements.userScripts.forget(id: Self.extensionID)
    }

    /// The setting in the copy's manifest, read by the complement at once.
    @Test func theSettingIsInTheCopysManifest() throws {
        let key = ExtensionComplementPackage.userScriptsAllowedKey
        let manifest = Data(#"{"manifest_version":3,"name":"U"}"#.utf8)
        let allowed = try #require(ExtensionComplementPackage.manifest(manifest, allowingUserScripts: true))
        let object = try #require(JSONSerialization.jsonObject(with: allowed) as? [String: Any])
        #expect(object[key] as? Bool == true && object["name"] as? String == "U")
        #expect(ExtensionComplementPackage.manifest(allowed, allowingUserScripts: true) == nil)
        let off = try #require(ExtensionComplementPackage.manifest(allowed, allowingUserScripts: false))
        #expect(try (JSONSerialization.jsonObject(with: off) as? [String: Any])?[key] == nil)
        #expect(ExtensionComplementPackage.manifest(manifest, allowingUserScripts: false) == nil)
    }

    /// Not allowed: no `chrome.userScripts` in its worker, as in Chrome,
    /// for the extension to say how to allow them.
    @Test func undefinedInTheWorkerUntilAllowed() async throws {
        guard #available(macOS 15.4, *) else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("userscripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = [
            "manifest.json": #"{"manifest_version":3,"name":"U","version":"1","permissions":["userScripts"],"background":{"service_worker":"sw.js"}}"#,
            "sw.js": """
            let available;
            try { chrome.userScripts.getScripts(); available = true; } catch (e) { available = false; }
            browser.runtime.sendNativeMessage("probe", [typeof chrome.userScripts,
              typeof chrome.runtime.onUserScriptMessage, available].join(" "));
            """
        ]
        for (path, content) in files {
            try content.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        #expect(ExtensionComplementPackage.add(toFolder: folder) != nil)
        let (complements, storeFolder) = try complements()
        defer { try? FileManager.default.removeItem(at: storeFolder) }
        for allowed in [false, true] {
            #expect(ExtensionComplementPackage.setUserScriptsAllowed(allowed, at: folder.path) == allowed)
            let delegate = WorkerProbe(complements: complements)
            let controller = WKWebExtensionController(configuration: .nonPersistent())
            controller.delegate = delegate
            ExtensionBaseURL.registerScheme()
            let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: folder))
            context.uniqueIdentifier = Self.extensionID
            ExtensionBaseURL.apply(to: context, id: Self.extensionID)
            context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
            context.setPermissionStatus(.grantedExplicitly, for: .userScripts)
            try controller.load(context)
            try await delegate.wait()
            try? controller.unload(context)
            #expect(delegate.messages == [allowed ? "object object true" : "undefined undefined false"])
        }
    }
}
