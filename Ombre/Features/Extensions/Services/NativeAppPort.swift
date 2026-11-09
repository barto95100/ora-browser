import WebKit

/// What an extension gets when it asks for its app (`runtime.connectNative`):
/// only Safari can reach the app part of a Safari extension.
///
/// A refusal is a runtime error, and Bitwarden asks again every 10 s (two
/// timers, whatever the answer): one error in the console each time. The
/// port is accepted, then closed without an error, which the extension sees
/// as its app going away: the same state as a refusal, without the error.
@available(macOS 15.4, *)
@MainActor
enum NativeAppPort {
    /// Closed right after the answer, the page side doesn't see it yet: the
    /// close would be lost and the port would stay open. Measured: 100 ms is
    /// enough, a single main-queue turn is not; 1 s leaves room on a busy Mac
    /// (Bitwarden gives up on its own after 5 s).
    static let closeDelay: Duration = .seconds(1)

    static func decline(
        _ port: WKWebExtension.MessagePort,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        // A message means the page side is there: closed at once.
        port.messageHandler = { [weak port] _, _ in
            port?.disconnect()
        }
        completionHandler(nil)
        // Kept until then (WebKit may let go of an unused port).
        Task { @MainActor in
            try? await Task.sleep(for: closeDelay)
            if !port.isDisconnected { port.disconnect() }
        }
    }
}
