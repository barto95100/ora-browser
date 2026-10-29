import AppKit
import SwiftUI

/// An area of a page asked for a note: the image and the tab it shows.
struct AreaCaptureRequest: Identifiable {
    let id = UUID()
    /// The tab whose note asked: the overlay covers its page (and its split).
    let tabID: UUID
    /// The image, its tab, and the page's address leading to the area.
    let completion: (Data, Tab, URL) -> Void
}

/// Over the pages shown: the user traces a rectangle, the page under it is
/// snapshotted there. Escape or a simple click cancels.
struct AreaCaptureOverlay: View {
    let tabs: [Tab]
    let request: AreaCaptureRequest
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            AreaSelectionView(onSelect: capture, onCancel: { appState.areaCapture = nil })
            Text("Drag over the page to capture an area · Esc to cancel")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 12)
                .allowsHitTesting(false)
        }
        // The page keeps setting its own cursor under the overlay: it is
        // asked for the crosshair too.
        .onAppear { tabs.forEach { $0.evaluateJavaScript(Self.addCursorShield) } }
        .onDisappear { tabs.forEach { $0.evaluateJavaScript(Self.removeCursorShield) } }
    }

    private static let addCursorShield = """
    (() => {
        document.getElementById('ora-capture-shield')?.remove();
        const d = document.createElement('div');
        d.id = 'ora-capture-shield';
        d.style.cssText = 'position:fixed;inset:0;z-index:2147483647;cursor:crosshair;';
        document.documentElement.appendChild(d);
    })();
    """

    private static let removeCursorShield = "document.getElementById('ora-capture-shield')?.remove();"

    /// `rect` in `view`'s coordinates: the page under its center gives it.
    private func capture(_ rect: NSRect, in view: NSView) {
        appState.areaCapture = nil
        for tab in tabs {
            guard let webView = tab.browserPage?.webView, webView.window === view.window else { continue }
            let rectInPage = webView.convert(rect, from: view)
            guard webView.bounds.contains(NSPoint(x: rectInPage.midX, y: rectInPage.midY)) else { continue }
            let clipped = rectInPage.intersection(webView.bounds)
            guard clipped.width >= 4, clipped.height >= 4 else { return }
            let configuration = BrowserSnapshotConfiguration(rect: clipped, afterScreenUpdates: false)
            // The words at the top of the area (in CSS pixels): the page opens there.
            let zoom = max(webView.pageZoom, 0.1)
            let anchor = CGPoint(x: clipped.midX / zoom, y: (clipped.minY + min(clipped.height / 2, 40)) / zoom)
            let page = tab.url
            tab.evaluateJavaScript(PageAnchor.wordsScript(at: anchor)) { result, _ in
                let link = PageAnchor.url(page, scrolledTo: result as? String ?? "")
                tab.takeSnapshot(configuration: configuration) { image, _ in
                    guard let png = image.flatMap(NoteImageImport.pngData(fromSnapshot:)) else { return }
                    request.completion(png, tab, link)
                }
            }
            return
        }
    }
}

private struct AreaSelectionView: NSViewRepresentable {
    let onSelect: (NSRect, NSView) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> AreaSelectionNSView {
        let view = AreaSelectionNSView()
        view.onSelect = onSelect
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: AreaSelectionNSView, context: Context) {
        view.onSelect = onSelect
        view.onCancel = onCancel
    }
}

final class AreaSelectionNSView: NSView {
    var onSelect: ((NSRect, NSView) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var selection: NSRect?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            window.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        ).intersection(bounds)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            start = nil
            needsDisplay = true
        }
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            onCancel?()
            return
        }
        onSelect?(selection, self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        guard let selection else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.setLineDash([4, 3], count: 2, phase: 0)
        border.stroke()
    }
}
