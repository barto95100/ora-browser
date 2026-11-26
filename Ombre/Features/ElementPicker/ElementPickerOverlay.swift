import AppKit
import SwiftUI
import WebKit

/// Where the picker is: the block under the mouse, then the one chosen.
@MainActor
@Observable
final class ElementPickerSession {
    /// The tab under the mouse, and its block (in the overlay's coordinates).
    var tab: Tab?
    var highlight: CGRect?
    var label = ""
    /// The block clicked: the action bar shows for it.
    var choice: Choice?

    struct Choice {
        let tab: Tab
        /// As it would be kept, with its words and kind (see `HiddenElement.title`).
        let element: HiddenElement
        let rect: CGRect
    }
}

/// Over the pages shown (⇧⌘H): each block under the mouse is outlined,
/// ↑ and ↓ widen or narrow it, a click chooses it, Esc cancels. The page
/// gets no mouse event meanwhile. Then a bar: hide it, or capture it.
struct ElementPickerOverlay: View {
    let tabs: [Tab]
    let request: ElementPickerRequest
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var toastManager: ToastManager
    @Environment(\.window) private var window
    @State private var session = ElementPickerSession()
    @State private var barSize = CGSize(width: 300, height: 36)
    @State private var isCapturing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ElementPickerSurface(tabs: tabs, session: session, onCancel: close)
                if let choice = session.choice {
                    actionBar(for: choice)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { barSize = $0 }
                        .offset(barOffset(for: choice.rect, in: geometry.size))
                } else {
                    Text("Choose a block · ↑ ↓ to widen or narrow · Esc to cancel")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
        }
        .onDisappear { stopPicking() }
        // Reader mode over the page (its button, its menu): nothing left to pick.
        .onChange(of: tabs.contains { $0.browserPage?.reader.isShown == true }) { _, reading in
            if reading { close() }
        }
    }

    private func actionBar(for choice: ElementPickerSession.Choice) -> some View {
        HStack(spacing: 8) {
            Text(choice.element.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(choice.element.selector)
                .frame(maxWidth: 160, alignment: .leading)
            Button {
                hide(choice)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            .help(choice.tab.isPrivate
                ? String(localized: "Hides it on this page only: a private window records nothing")
                : String(localized: "Hides it on this site, now and on your next visits"))
            Menu {
                Button("Copy Image") { capture(choice, to: .clipboard) }
                Button("Save Image…") { capture(choice, to: .file) }
                Button("Add to Tab Note") { capture(choice, to: .tabNote) }
                    .disabled(choice.tab.isPrivate)
            } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isCapturing)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Cancel")
            .accessibilityLabel(String(localized: "Cancel"))
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func hide(_ choice: ElementPickerSession.Choice) {
        let tab = choice.tab
        ElementPicker.hide(choice.element, in: tab) { kept in
            guard !tab.isPrivate else { return }
            guard let site = WebSite.registrableDomain(of: tab.url) else { return }
            if kept {
                toastManager.show(String(localized: "Hidden on \(site)"), icon: .system("eye.slash"))
            } else {
                toastManager.show(
                    String(localized: "Hidden on this page only: this element can't be found again"),
                    icon: .system("exclamationmark.triangle")
                )
            }
        }
        close()
    }

    /// Below the block, else above it, else inside its top; always in view.
    private func barOffset(for rect: CGRect, in size: CGSize) -> CGSize {
        let gap: CGFloat = 8
        var top = rect.maxY + gap
        if top + barSize.height > size.height - gap {
            top = rect.minY - gap - barSize.height
        }
        if top < gap { top = max(gap, rect.minY + gap) }
        let left = min(max(gap, rect.minX), max(gap, size.width - barSize.width - gap))
        return CGSize(width: left, height: min(top, max(gap, size.height - barSize.height - gap)))
    }

    private func capture(_ choice: ElementPickerSession.Choice, to destination: ElementPicker.Destination) {
        let tab = choice.tab
        guard !isCapturing else { return }
        isCapturing = true
        // Brought into view and taken first, then the picker goes.
        ElementPicker.capture(in: tab) { png, link in
            isCapturing = false
            close()
            guard let png else {
                toastManager.show(
                    String(localized: "The block could not be captured"),
                    icon: .system("exclamationmark.triangle")
                )
                return
            }
            switch destination {
            case .clipboard:
                ElementPicker.copy(png)
                toastManager.show(String(localized: "Image copied"), icon: .system("doc.on.clipboard"))
            case .file:
                ElementPicker.save(png, from: tab, in: window)
            case .tabNote:
                guard TabNoteImages.add(png, from: tab, link: link) else { return }
                appState.showTabNote = true
            }
        }
    }

    /// The keyboard goes back to the page.
    private func close() {
        // Only this picker: a new one may have started meanwhile.
        guard appState.elementPicker?.id == request.id else { return }
        appState.elementPicker = nil
        if let webView = (session.choice?.tab ?? session.tab ?? tabs.first)?.browserPage?.webView {
            webView.window?.makeFirstResponder(webView)
        }
    }

    private func stopPicking() {
        for tab in tabs {
            ElementPicker.call("picker.stop();", in: tab) { _ in }
        }
    }
}

private struct ElementPickerSurface: NSViewRepresentable {
    let tabs: [Tab]
    let session: ElementPickerSession
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ElementPickerNSView {
        let view = ElementPickerNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ElementPickerNSView, context: Context) {
        view.tabs = tabs
        view.session = session
        view.onCancel = onCancel
    }
}

/// Takes the mouse and the keyboard from the pages, asks the page under the
/// mouse for its block (one request at a time, the latest point next) and
/// outlines it.
final class ElementPickerNSView: NSView {
    var tabs: [Tab] = []
    var session: ElementPickerSession?
    var onCancel: (() -> Void)?
    private var isAsking = false
    private var nextPoint: NSPoint?
    private var lastPoint: NSPoint?
    private var block: PickedBlock?

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.ask(at: self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
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
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard session?.choice == nil else { return }
        ask(at: convert(event.locationInWindow, from: nil))
    }

    /// The page scrolls under the overlay; the block under the mouse follows.
    override func scrollWheel(with event: NSEvent) {
        guard session?.choice == nil, let (_, webView) = page(at: convert(event.locationInWindow, from: nil))
        else { return }
        webView.scrollWheel(with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, let point = self.lastPoint else { return }
            self.ask(at: point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if session?.choice != nil {
            // A click beside the bar: chosen again where it is.
            session?.choice = nil
            ask(at: convert(event.locationInWindow, from: nil))
            return
        }
        choose()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?() // Esc
        case 126: move("picker.widen()") // ↑
        case 125: move("picker.narrow()") // ↓
        case 36, 76: if session?.choice == nil { choose() } // Return, Enter
        default: super.keyDown(with: event)
        }
    }

    private func page(at point: NSPoint) -> (Tab, WKWebView)? {
        for tab in tabs {
            guard let webView = tab.browserPage?.webView, webView.window === window else { continue }
            let local = webView.convert(point, from: self)
            if webView.bounds.contains(local) { return (tab, webView) }
        }
        return nil
    }

    private func ask(at point: NSPoint) {
        lastPoint = point
        guard !isAsking else {
            nextPoint = point
            return
        }
        guard let (tab, webView) = page(at: point) else {
            show(nil, in: nil, of: nil)
            return
        }
        let zoom = max(webView.pageZoom, 0.1)
        let local = webView.convert(point, from: self)
        isAsking = true
        ElementPicker.call(
            "return picker.hit(x, y);", // not shown
            arguments: ["x": Double(local.x / zoom), "y": Double(local.y / zoom)],
            in: tab
        ) { [weak self] value in
            guard let self else { return }
            isAsking = false
            show(PickedBlock(value), in: tab, of: webView)
            if let next = nextPoint {
                nextPoint = nil
                ask(at: next)
            }
        }
    }

    private func move(_ call: String) {
        guard session?.choice == nil, let tab = session?.tab, let webView = tab.browserPage?.webView else { return }
        ElementPicker.call("return \(call);", in: tab) { [weak self] value in // not shown
            self?.show(PickedBlock(value), in: tab, of: webView)
        }
    }

    private func choose() {
        guard let tab = session?.tab, let highlight = session?.highlight else { return }
        ElementPicker.call("return picker.choose();", in: tab) { [weak self] value in // not shown
            guard let self, let value = value as? [String: Any], let selector = value["selector"] as? String,
                  !selector.isEmpty
            else { return }
            session?.choice = ElementPickerSession.Choice(
                tab: tab,
                element: HiddenElement(
                    selector: selector,
                    label: value["label"] as? String ?? "",
                    date: Date(),
                    name: value["name"] as? String,
                    kind: value["kind"] as? String
                ),
                rect: highlight
            )
            needsDisplay = true
        }
    }

    private func show(_ block: PickedBlock?, in tab: Tab?, of webView: WKWebView?) {
        self.block = block
        guard let block, let tab, let webView else {
            session?.highlight = nil
            session?.tab = nil
            needsDisplay = true
            return
        }
        let zoom = max(webView.pageZoom, 0.1)
        let rect = convert(ElementPicker.viewRect(block.rect, zoom: zoom), from: webView)
            .intersection(convert(webView.bounds, from: webView))
        session?.tab = tab
        session?.highlight = rect.isNull ? nil : rect
        session?.label = block.label
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = session?.highlight else { return }
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.12).setFill()
        rect.fill()
        accent.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()
        guard session?.choice == nil, let block else { return }
        drawTag("\(block.label)  \(Int(block.rect.width)) × \(Int(block.rect.height))", above: rect)
    }

    /// The block's name and size, small, at its top left.
    private func drawTag(_ text: String, above rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var origin = NSPoint(x: rect.minX, y: rect.minY - size.height - 4)
        if origin.y < bounds.minY { origin.y = rect.minY + 2 }
        origin.x = min(max(bounds.minX, origin.x), bounds.maxX - size.width - 8)
        let background = NSRect(x: origin.x, y: origin.y, width: size.width + 8, height: size.height + 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        string.draw(at: NSPoint(x: origin.x + 4, y: origin.y + 1))
    }
}
