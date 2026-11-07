import AppKit
@testable import Ombre
import SwiftData
import SwiftUI
import Testing

extension TabManagerTests {
    /// Files dragged from the Finder onto a real browser window: AppKit's
    /// drop messages sent to the view under each point, like a real drag.
    @MainActor
    @Suite(.serialized)
    struct FileDropTests {
        @Test
        func filesOpenWhereverTheyAreDropped() async throws {
            try await TabManagerTestWindow.run { managers in
                let space = try managers.activeSpace
                for index in 0 ..< 3 {
                    managers.addUnloadedTab("/normal\(index)", order: index, in: space)
                }
                managers.addUnloadedTab("/pinned", type: .pinned, order: 0, in: space)
                let window = try await BrowserTestWindow.open(managers)
                defer { window.close() }
                let file = try DropTestFile()
                defer { file.remove() }

                let sidebar = try #require(window.sidebarFrame)
                let places: [(String, NSPoint)] = [
                    ("sidebar header", NSPoint(x: sidebar.midX, y: sidebar.maxY + 12)),
                    ("top of the tab list", NSPoint(x: sidebar.midX, y: sidebar.maxY - 20)),
                    ("tab list", NSPoint(x: sidebar.midX, y: sidebar.maxY - 160)),
                    ("empty space under the tabs", NSPoint(x: sidebar.midX, y: sidebar.minY + 80)),
                    ("address bar", NSPoint(x: sidebar.maxX + 200, y: window.contentHeight - 20)),
                    ("empty page", NSPoint(x: sidebar.maxX + 300, y: window.contentHeight / 2))
                ]
                for (place, point) in places {
                    let opened = await window.drop(file.url, at: point)
                    #expect(opened == [file.url], "dropped on the \(place)")
                }
            }
        }

        /// No tab: the empty home page, and several files at once, in order.
        @Test
        func severalFilesOpenOnTheHomePage() async throws {
            try await TabManagerTestWindow.run { managers in
                let window = try await BrowserTestWindow.open(managers)
                defer { window.close() }
                let files = try ["html", "pdf", "txt"].map { try DropTestFile(extension: $0) }
                defer { files.forEach { $0.remove() } }
                let sidebar = try #require(window.sidebarFrame)
                let opened = await window.drop(
                    files.map(\.url),
                    at: NSPoint(x: sidebar.maxX + 300, y: window.contentHeight / 2)
                )
                #expect(opened == files.map(\.url))
            }
        }

        @Test
        func otherFilesAreRefused() async throws {
            try await TabManagerTestWindow.run { managers in
                let space = try managers.activeSpace
                managers.addUnloadedTab("/normal", order: 0, in: space)
                let window = try await BrowserTestWindow.open(managers)
                defer { window.close() }
                let file = try DropTestFile(extension: "zip")
                defer { file.remove() }
                let sidebar = try #require(window.sidebarFrame)
                let opened = await window.drop(file.url, at: NSPoint(x: sidebar.midX, y: sidebar.minY + 80))
                #expect(opened.isEmpty)
            }
        }
    }
}

/// A file to drop, in a folder of its own.
private struct DropTestFile {
    let url: URL

    init(extension pathExtension: String = "html") throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("dropped.\(pathExtension)")
        try Data("<p>dropped</p>".utf8).write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// A browser window as the app shows it (`BrowserView` and its managers).
@MainActor
private final class BrowserTestWindow {
    let window: NSWindow
    private let host: NSView
    private static var sequenceNumber = 4000
    private let managers: TabManagerTestWindow

    private init(window: NSWindow, host: NSView, managers: TabManagerTestWindow) {
        self.window = window
        self.host = host
        self.managers = managers
    }

    static func open(_ managers: TabManagerTestWindow) async throws -> BrowserTestWindow {
        let sidebarManager = SidebarManager()
        let toolbarManager = ToolbarManager()
        let root = BrowserView()
            .environmentObject(AppState())
            .environmentObject(managers.tabManager)
            .environmentObject(managers.historyManager)
            .environmentObject(managers.mediaController)
            .environmentObject(KeyModifierListener())
            .environmentObject(CustomKeyboardShortcutManager.shared)
            .environmentObject(AppearanceManager.shared)
            .environmentObject(managers.downloadManager)
            .environmentObject(UpdateService.shared)
            .environmentObject(PrivacyMode(isPrivate: false))
            .environmentObject(sidebarManager)
            .environmentObject(toolbarManager)
            .environmentObject(DialogManager())
            .environmentObject(ToastManager.shared)
            .modelContext(managers.modelContext)
            .withTheme()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root.environment(\.window, window))
        window.contentView = host
        window.orderBack(nil)
        let browser = BrowserTestWindow(window: window, host: host, managers: managers)
        await managers.waitUntil("sidebar shown", timeout: .seconds(5)) {
            host.layoutSubtreeIfNeeded()
            return browser.sidebarFrame != nil
        }
        return browser
    }

    var contentHeight: CGFloat {
        host.bounds.height
    }

    /// The sidebar, in window coordinates: the spaces' pager.
    var sidebarFrame: NSRect? {
        guard let pager = Self.find(NSPageController.self, in: host)?.view, pager.window != nil else { return nil }
        let frame = pager.convert(pager.bounds, to: nil)
        return frame.width > 50 ? frame : nil
    }

    /// Drags `file` from another app to `point` (window coordinates) and drops
    /// it there; returns the addresses the window was asked to open.
    func drop(_ file: URL, at point: NSPoint) async -> [URL] {
        await drop([file], at: point)
    }

    func drop(_ files: [URL], at point: NSPoint) async -> [URL] {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects(files.map { $0 as NSURL })
        let previous = FileDrop.pasteboard
        FileDrop.pasteboard = pasteboard
        defer { FileDrop.pasteboard = previous }

        // The pointer is over the drop (the sidebar's targets open files in
        // the window under it).
        let previousPointer = FileDrop.pointerLocation
        let screenPoint = window.convertPoint(toScreen: point)
        FileDrop.pointerLocation = { screenPoint }
        defer { FileDrop.pointerLocation = previousPointer }

        var opened: [URL] = []
        let window = window
        let observer = NotificationCenter.default.addObserver(forName: .openURL, object: nil, queue: nil) { note in
            // Asked of this window only: the others ignore it.
            guard note.object as? NSWindow === window else { return }
            if let url = note.userInfo?["url"] as? URL { opened.append(url) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        Self.sequenceNumber += 1
        let drag = FakeDraggingInfo(
            window: window,
            location: point,
            pasteboard: pasteboard,
            sequenceNumber: Self.sequenceNumber
        )
        drag.numberOfValidItemsForDrop = files.count
        guard let target = dropTarget(at: point, for: pasteboard) else { return [] }
        _ = target.draggingEntered(drag)
        let operation = target.draggingUpdated(drag)
        guard !operation.isEmpty, target.prepareForDragOperation(drag), target.performDragOperation(drag) else {
            target.draggingExited(drag)
            return []
        }
        target.concludeDragOperation(drag)
        await managers.waitUntil("files opened", timeout: .seconds(2)) { opened.count >= files.count }
        return opened
    }

    /// The view AppKit would send the drag to: the frontmost, deepest view
    /// under the point that is registered for drags (SwiftUI's drop targets
    /// are views of their own, beside the content they cover).
    private func dropTarget(at point: NSPoint, for pasteboard: NSPasteboard) -> NSView? {
        guard let frame = window.contentView?.superview else { return nil }
        // Registered for one of the drag's types ("public.item" takes all).
        var types = Set(pasteboard.types ?? [])
        types.formUnion([.init("public.item"), .init("public.data")])
        return Self.dropTarget(in: frame, at: point, types: types)
    }

    private static func dropTarget(
        in view: NSView,
        at point: NSPoint,
        types: Set<NSPasteboard.PasteboardType>
    ) -> NSView? {
        guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0,
              view.bounds.contains(view.convert(point, from: nil))
        else { return nil }
        for subview in view.subviews.reversed() {
            if let target = dropTarget(in: subview, at: point, types: types) { return target }
        }
        return types.isDisjoint(with: view.registeredDraggedTypes) ? nil : view
    }

    func close() {
        window.close()
    }

    private static func find<T>(_ type: T.Type, in view: NSView) -> T? {
        var controller: NSResponder? = view.nextResponder
        while let current = controller {
            if let match = current as? T { return match }
            controller = current.nextResponder
        }
        for subview in view.subviews {
            if let match = subview.nextResponder as? T { return match }
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }
}

/// A drag from another app, as AppKit describes it to a drop target.
private final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint
    let draggingPasteboard: NSPasteboard
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    let draggingSequenceNumber: Int

    init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard, sequenceNumber: Int) {
        draggingDestinationWindow = window
        draggingLocation = location
        draggingPasteboard = pasteboard
        draggingSequenceNumber = sequenceNumber
    }

    var draggingSourceOperationMask: NSDragOperation {
        [.copy, .link, .generic]
    }
    var draggedImageLocation: NSPoint {
        draggingLocation
    }
    var draggedImage: NSImage? {
        nil
    }
    var draggingSource: Any? {
        nil
    }
    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions,
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
