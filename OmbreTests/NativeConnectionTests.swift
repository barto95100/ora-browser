import Foundation
@testable import Ombre
import Testing
import WebKit

/// An extension asking for its Safari app (`runtime.connectNative`) gets a
/// port that closes at once, without an error: Bitwarden asks again every
/// 10 s, and each refusal was a runtime error in the console.
@MainActor
struct NativeConnectionTests {
    /// Bitwarden writes to the port at once (the Safari app is always there).
    @available(macOS 15.4, *)
    @Test(arguments: [false, true])
    func aDeclinedConnectionClosesWithoutAnError(writes: Bool) async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let manifest = """
        {"manifest_version": 3, "name": "Native test", "version": "1.0", "permissions": ["nativeMessaging"],
         "background": {"service_worker": "background.js"}}
        """
        try Data(manifest.utf8).write(to: source.appendingPathComponent("manifest.json"))
        let script = """
        const port = chrome.runtime.connectNative("com.example.app");
        port.onDisconnect.addListener((closed) => {
            const error = chrome.runtime.lastError?.message ?? closed.error?.message ?? "none";
            chrome.runtime.sendNativeMessage("com.example.app", { command: "result", error });
        });
        \(writes ? "port.postMessage({ command: \"hello\" });" : "")
        """
        try Data(script.utf8).write(to: source.appendingPathComponent("background.js"))

        let store = UUID()
        let controller = WKWebExtensionController(configuration: .init(identifier: store))
        let delegate = Recorder()
        controller.delegate = delegate
        let library = try #require(ExtensionDataFolder.library)
        let storeFolder = library.appendingPathComponent("WebKit/WebExtensions/\(store.uuidString)")
        defer { try? FileManager.default.removeItem(at: storeFolder) }
        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: source))
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        try controller.load(context)
        defer { try? controller.unload(context) }

        for _ in 0 ..< 200 where delegate.result == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(delegate.connections == 1)
        #expect(delegate.result == "none")
    }
}

@available(macOS 15.4, *)
@MainActor
private final class Recorder: NSObject, WKWebExtensionControllerDelegate {
    var connections = 0
    var result: String?

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        connections += 1
        NativeAppPort.decline(port, completionHandler: completionHandler)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        result = (message as? [String: Any])?["error"] as? String
        replyHandler(nil, nil)
    }
}
