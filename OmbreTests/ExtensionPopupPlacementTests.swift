import AppKit
@testable import Ombre
import Testing

/// Where an extension's popup and its own windows show.
@MainActor
struct ExtensionPopupPlacementTests {
    private static let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)

    /// A window with a view per anchor (off screen, never shown).
    private static func window(with ids: [String]) -> (NSWindow, [(view: NSView, id: String)]) {
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let anchors = ids.enumerated().map { index, id in
            let view = NSView(frame: NSRect(x: CGFloat(index) * 30, y: 0, width: 30, height: 30))
            window.contentView?.addSubview(view)
            return (view: view, id: id)
        }
        return (window, anchors)
    }

    @Test func popupShowsUnderItsButton() {
        guard #available(macOS 15.4, *) else { return }
        let (window, anchors) = Self.window(with: ["other", "bitwarden", WebExtensionsManager.menuAnchorKey])
        let anchor = WebExtensionsManager.popupAnchor(for: "bitwarden", in: window, among: anchors)
        #expect(anchor === anchors[1].view)
    }

    /// Its button not shown (in the extensions menu, hidden): the menu.
    @Test func popupShowsUnderTheMenuWithoutItsButton() {
        guard #available(macOS 15.4, *) else { return }
        let (window, anchors) = Self.window(with: ["bitwarden", WebExtensionsManager.menuAnchorKey])
        anchors[0].view.isHidden = true
        let anchor = WebExtensionsManager.popupAnchor(for: "bitwarden", in: window, among: anchors)
        #expect(anchor === anchors[1].view)
    }

    /// Only the front window's buttons count; none: centered (nil).
    @Test func popupIsCenteredWithoutAnchorInTheWindow() {
        guard #available(macOS 15.4, *) else { return }
        let (front, _) = Self.window(with: [])
        let (_, otherAnchors) = Self.window(with: ["bitwarden", WebExtensionsManager.menuAnchorKey])
        #expect(WebExtensionsManager.popupAnchor(for: "bitwarden", in: front, among: otherAnchors) == nil)
        #expect(WebExtensionsManager.popupAnchor(for: "bitwarden", in: nil, among: otherAnchors) == nil)
    }

    @Test func extensionWindowGetsTheFrameAsked() {
        guard #available(macOS 15.4, *) else { return }
        let frame = WebExtensionsManager.extensionWindowFrame(
            requested: CGRect(x: 900, y: 200, width: 380, height: 630),
            around: nil,
            visible: Self.visible
        )
        #expect(frame == NSRect(x: 900, y: 200, width: 380, height: 630))
    }

    /// Nothing asked: 400 × 600 centered on the browser window.
    @Test func extensionWindowIsCenteredWithoutFrame() {
        guard #available(macOS 15.4, *) else { return }
        let frame = WebExtensionsManager.extensionWindowFrame(
            requested: CGRect(x: CGFloat.nan, y: .nan, width: .nan, height: .nan),
            around: NSRect(x: 100, y: 100, width: 1000, height: 700),
            visible: Self.visible
        )
        #expect(frame == NSRect(x: 400, y: 150, width: 400, height: 600))
    }

    /// Never off the screen.
    @Test func extensionWindowStaysOnScreen() {
        guard #available(macOS 15.4, *) else { return }
        let frame = WebExtensionsManager.extensionWindowFrame(
            requested: CGRect(x: 1300, y: -50, width: 380, height: 2000),
            around: nil,
            visible: Self.visible
        )
        #expect(frame == NSRect(x: 1060, y: 0, width: 380, height: 900))
    }
}
