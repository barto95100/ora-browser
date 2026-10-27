import AppKit

/// Opens the files Finder sends (Open With, double-click, drop on the Dock
/// icon) as tabs of the frontmost browser window, like links from other apps.
/// Left to SwiftUI, each file opened a new window: it routes document openings
/// itself, without the `handlesExternalEvents` preferences used for links.
@MainActor
final class ExternalFileOpener: NSObject {
    static let shared = ExternalFileOpener()

    /// Regular (non-private) browser windows, which may receive files.
    private let browserWindows = NSHashTable<NSWindow>.weakObjects()
    /// Files received before any browser window existed (Ora launched by them).
    private var pendingFiles: [URL] = []
    private var didFinishLaunching = false

    /// Call from `applicationWillFinishLaunching`, so the file that launches
    /// Ora is handled too.
    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    func applicationDidFinishLaunching() {
        didFinishLaunching = true
    }

    /// Adds a regular browser window and returns the files waiting for one.
    func register(_ window: NSWindow) -> [URL] {
        browserWindows.add(window)
        defer { pendingFiles = [] }
        return pendingFiles
    }

    @objc private func handleOpenDocuments(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        let files = Self.fileURLs(in: event)
        guard !files.isEmpty else { return }

        if let window = NSApp.orderedWindows.first(where: { browserWindows.contains($0) }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            for file in files {
                NotificationCenter.default.post(name: .openURL, object: window, userInfo: ["url": file])
            }
        } else if didFinishLaunching, let delegate = NSApp.delegate,
                  delegate.responds(to: #selector(NSApplicationDelegate.application(_:open:)))
        {
            // No browser window open: SwiftUI opens one and passes the files
            // to its `onOpenURL`.
            delegate.application?(NSApp, open: files)
        } else {
            // Launching: the first browser window opens them (`register`).
            pendingFiles += files
        }
    }

    private static func fileURLs(in event: NSAppleEventDescriptor) -> [URL] {
        guard let files = event.paramDescriptor(forKeyword: keyDirectObject) else { return [] }
        let items = files.numberOfItems > 0
            ? (1 ... files.numberOfItems).compactMap { files.atIndex($0) }
            : [files]
        return items.compactMap { $0.coerce(toDescriptorType: typeFileURL)?.fileURLValue }
    }
}
