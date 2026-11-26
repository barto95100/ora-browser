import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

/// The element picker asked for a tab (⇧⌘H), see `ElementPickerOverlay`.
struct ElementPickerRequest: Identifiable {
    let id = UUID()
    /// The tab shown: the overlay covers its page (and its split).
    let tabID: UUID
}

/// A block of the page as the picker's script gives it, in CSS pixels of
/// the viewport.
struct PickedBlock: Equatable {
    let rect: CGRect
    let label: String
    let canWiden: Bool
    let canNarrow: Bool

    init?(_ value: Any?) {
        guard let value = value as? [String: Any],
              let left = (value["x"] as? NSNumber)?.doubleValue,
              let top = (value["y"] as? NSNumber)?.doubleValue,
              let width = (value["width"] as? NSNumber)?.doubleValue,
              let height = (value["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        rect = CGRect(x: left, y: top, width: width, height: height)
        label = value["label"] as? String ?? ""
        canWiden = value["canWiden"] as? Bool ?? false
        canNarrow = value["canNarrow"] as? Bool ?? false
    }
}

/// The picker's calls into a page (see `ElementPickerScript`).
@MainActor
enum ElementPicker {
    /// Runs `body` in the picker's world, the picker installed first.
    static func call(
        _ body: String,
        arguments: [String: Any] = [:],
        in tab: Tab,
        completion: @escaping @MainActor (Any?) -> Void
    ) {
        guard let webView = tab.browserPage?.webView else { return completion(nil) }
        webView.callAsyncJavaScript(
            ElementPickerScript.source + "\nconst picker = window.__ombrePicker;\n" + body, // not shown
            arguments: arguments,
            in: nil,
            in: ElementPickerScript.world
        ) { result in
            completion(try? result.get())
        }
    }

    /// A CSS rectangle of the viewport in the web view's points.
    nonisolated static func viewRect(_ rect: CGRect, zoom: CGFloat) -> CGRect {
        CGRect(x: rect.minX * zoom, y: rect.minY * zoom, width: rect.width * zoom, height: rect.height * zoom)
    }

    // MARK: - Hiding

    /// Hidden at once on the page; in a regular window, also on the site's
    /// next visits in this space, if WebKit accepts its rule. Nothing is
    /// recorded in a private window. `completion`: whether it is kept.
    static func hide(_ element: HiddenElement, in tab: Tab, completion: @escaping @MainActor (Bool) -> Void) {
        call("return picker.hide(selector);", arguments: ["selector": element.selector], in: tab) { _ in } // not shown
        guard !tab.isPrivate, let site = WebSite.registrableDomain(of: tab.url) else { return completion(false) }
        let spaceID = tab.container.id
        HiddenElementRuleLists.shared.accepts(element, onSite: site) { accepted in
            guard accepted else { return completion(false) }
            if HiddenElementsStore.shared.hide(element, onSite: site, in: spaceID) {
                HiddenElementRuleLists.shared.update(spaceID)
            }
            completion(true)
        }
    }

    /// Shown again: from the next load, now when `reloading` is given.
    static func show(_ selector: String?, onSite site: String, in spaceID: UUID, reloading tab: Tab? = nil) {
        if let selector {
            HiddenElementsStore.shared.show(selector, onSite: site, in: spaceID)
        } else {
            HiddenElementsStore.shared.showAll(onSite: site, in: spaceID)
        }
        // Now on the page, then shown by a reload.
        HiddenElementRuleLists.shared.update(spaceID) { list in
            guard let page = tab?.browserPage else { return }
            page.setHiddenElements(list)
            page.reload()
        }
    }

    // MARK: - Capturing

    enum Destination {
        case clipboard, file, tabNote
    }

    /// The chosen block, brought into view, as a PNG; and the page's address
    /// leading to it (for a note).
    static func capture(in tab: Tab, completion: @escaping @MainActor (Data?, URL) -> Void) {
        let page = tab.url
        call("return picker.reveal();", in: tab) { value in // not shown
            guard let block = PickedBlock(value), let webView = tab.browserPage?.webView else {
                return completion(nil, page)
            }
            let zoom = max(webView.pageZoom, 0.1)
            let rect = viewRect(block.rect, zoom: zoom).intersection(webView.bounds)
            guard rect.width >= 2, rect.height >= 2 else { return completion(nil, page) }
            let anchor = CGPoint(x: rect.midX / zoom, y: (rect.minY + min(rect.height / 2, 40)) / zoom)
            tab.evaluateJavaScript(PageAnchor.wordsScript(at: anchor)) { words, _ in
                let link = PageAnchor.url(page, scrolledTo: words as? String ?? "")
                let configuration = BrowserSnapshotConfiguration(rect: rect, afterScreenUpdates: true)
                tab.takeSnapshot(configuration: configuration) { image, _ in
                    completion(image.flatMap(NoteImageImport.pngData(fromSnapshot:)), link)
                }
            }
        }
    }

    static func copy(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    /// A save panel over the window, named after the site.
    static func save(_ png: Data, from tab: Tab, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let site = WebSite.registrableDomain(of: tab.url) ?? String(localized: "Page")
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "\(site) \(date).png" // not shown
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            try? png.write(to: url, options: .atomic)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }
}
