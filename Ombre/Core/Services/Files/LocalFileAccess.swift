import AppKit
import os

/// Local files typed in the address bar. The sandbox only lets Ombre read a
/// file the user picked (Finder, open panel, drop): a typed path gets the same
/// access through an open panel showing that file, which the user confirms
/// once. The tab then keeps it (`Tab+LocalFile`). Only for what the user
/// typed or picked in the address bar, never for what a page or an extension
/// opens.
@MainActor
enum LocalFileAccess {
    private static let logger = Logger(category: "LocalFiles")

    /// Asks the user for access to a file, calls back with the file granted
    /// (the one picked, which may differ) or nil. Replaced in tests.
    static var requestAccess: (URL, @escaping (URL?) -> Void) -> Void = showOpenPanel

    /// Whether Ombre may read the file now (picked this session, or in a
    /// folder the user allowed).
    nonisolated static func canRead(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        if LocalFolderAccess.shared.folder(containing: url) != nil { return true }
        // Only a regular file, opened without waiting (a named pipe would
        // block until something writes to it).
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return false }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return false }
        Darwin.close(descriptor)
        return true
    }

    /// Calls `open` with the file once Ombre may read it, asking the user
    /// first when needed; nothing happens if they decline.
    static func whenReadable(_ url: URL, open: @escaping (URL) -> Void) {
        guard url.isFileURL, !canRead(url) else {
            open(url)
            return
        }
        logger.info("Asking for access to a typed local file")
        requestAccess(url) { granted in
            guard let granted else {
                logger.info("Access to the local file declined")
                return
            }
            guard canRead(granted) else {
                logger.error("The local file stays unreadable after the user picked it")
                return
            }
            open(granted)
        }
    }

    private static func showOpenPanel(for url: URL, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        // A file URL as the folder selects that file in the panel.
        panel.directoryURL = url
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Allow Ombre to open “\(url.lastPathComponent)”."
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }
}
