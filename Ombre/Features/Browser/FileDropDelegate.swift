import AppKit
import SwiftUI

/// Files dropped on a browser window (its sidebar, address bar, empty page)
/// open as tabs of that window, in the order they were picked, like Finder's
/// Open With; files a browser doesn't show are refused at once (no "+").
///
/// The sidebar's tab lists have their own drop targets (to move tabs): a drop
/// target takes the whole drag under it, so they open files through
/// `FileDrop` too instead of refusing them.
struct FileDropDelegate: DropDelegate {
    let window: NSWindow?

    func validateDrop(info: DropInfo) -> Bool {
        FileDrop.hasOpenableFiles()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        FileDrop.open(info, in: window)
    }
}

/// Opening the files of a drop as tabs, for every drop target of a window.
@MainActor
enum FileDrop {
    /// The drag's pasteboard (a pasteboard of their own in tests).
    static var pasteboard = NSPasteboard(name: .drag)

    /// Whether the drag in progress carries a file a browser shows.
    static func hasOpenableFiles() -> Bool {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.contains(where: DroppedFiles.isOpenable)
    }

    /// Opens the dropped files a browser shows as tabs of `window`, or of the
    /// window under the pointer (a sidebar page doesn't always know its
    /// window, and the drop comes from another app: no window is key).
    @discardableResult
    static func open(_ info: DropInfo, in window: NSWindow?) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let window = window ?? windowUnderPointer()
        var urls = [URL?](repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    urls[index] = url
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                open(urls.compactMap { $0 }, in: window)
            }
        }
        return true
    }

    static func open(_ urls: [URL], in window: NSWindow?) {
        for url in urls where DroppedFiles.isOpenable(url) {
            NotificationCenter.default.post(name: .openURL, object: window, userInfo: ["url": url])
        }
    }

    /// Where the pointer is, in screen coordinates (set in tests).
    static var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    /// The front window of this app under the pointer, where a drop lands
    /// (not the drag image's, a tooltip's or another app's window).
    static func windowUnderPointer() -> NSWindow? {
        let location = pointerLocation()
        return NSApp.orderedWindows.first { $0.isVisible && $0.frame.contains(location) }
    }
}
