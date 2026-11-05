import AppKit
import SwiftUI

/// Files dropped on a browser window (its sidebar, address bar, empty page)
/// open as tabs of that window, in the order they were picked, like Finder's
/// Open With; files a browser doesn't show are refused at once (no "+").
struct FileDropDelegate: DropDelegate {
    let window: NSWindow?

    func validateDrop(info: DropInfo) -> Bool {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.contains(where: DroppedFiles.isOpenable)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
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
        // A sidebar page doesn't always know its window: the drop's does.
        let window = window ?? NSApp.currentEvent?.window
        group.notify(queue: .main) {
            for url in urls.compactMap({ $0 }) where DroppedFiles.isOpenable(url) {
                NotificationCenter.default.post(name: .openURL, object: window, userInfo: ["url": url])
            }
        }
        return true
    }
}
