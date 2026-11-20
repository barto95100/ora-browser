import AppKit
import SwiftUI
@testable import Ombre
import Testing

/// The settings have one window: asked again, it comes to the front at the
/// section asked for, and no other is made.
@MainActor
struct SettingsWindowTests {
    private func defaults() throws -> UserDefaults {
        let name = "SettingsWindowTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func withoutAWindowItIsMade() throws {
        let defaults = try defaults()
        var opened = 0
        SettingsWindow.show(.extensions, existing: nil, defaults: defaults) { opened += 1 }
        #expect(opened == 1)
        #expect(SettingsWindow.selection(in: defaults) == .extensions)
    }

    /// A window closed (not freed yet) is not reused: the scene makes it again.
    @Test func aClosedWindowIsMadeAgain() throws {
        let defaults = try defaults()
        let window = makeWindow()
        var opened = 0
        SettingsWindow.show(nil, existing: window, defaults: defaults) { opened += 1 }
        #expect(opened == 1)
    }

    /// Never shown on the screen: the window is taken as open, and what
    /// brings it to the front is recorded.
    @Test func anOpenWindowComesToTheFrontAtTheSection() throws {
        let defaults = try defaults()
        let window = makeWindow()
        var opened = 0
        var revealed: [NSWindow] = []
        for section in [SettingsTab.general, .searchEngines] {
            SettingsWindow.show(
                section,
                existing: window,
                defaults: defaults,
                isOpen: { _ in true },
                reveal: { revealed.append($0) },
                open: { opened += 1 }
            )
        }
        #expect(opened == 0)
        #expect(revealed.count == 2 && revealed.allSatisfy { $0 === window })
        #expect(SettingsWindow.selection(in: defaults) == .searchEngines)
    }

    /// Without a section, the last one shown stays.
    @Test func withoutASectionTheLastOneStays() throws {
        let defaults = try defaults()
        SettingsWindow.show(.shortcuts, existing: nil, defaults: defaults) {}
        SettingsWindow.show(nil, existing: nil, defaults: defaults) {}
        #expect(SettingsWindow.selection(in: defaults) == .shortcuts)
    }

    /// A folded list kept by the old split view is forgotten; nothing else.
    @Test func aFoldedListKeptBeforeIsForgotten() throws {
        let defaults = try defaults()
        let folded = "NSSplitView Subview Frames settings, SidebarNavigationSplitView"
        let restored = "NSSplitView Subview Frames settings-AppWindow-1, SidebarNavigationSplitView"
        let browser = "NSSplitView Subview Frames normal-AppWindow-1, SidebarNavigationSplitView"
        for key in [folded, restored, browser] {
            defaults.set(["0.000000, 0.000000, 148.000000, 680.000000, YES, NO"], forKey: key)
        }
        defaults.set("searchEngines", forKey: SettingsWindow.selectionKey)
        SettingsWindow.forgetFoldedSections(in: defaults)
        #expect(defaults.object(forKey: folded) == nil)
        #expect(defaults.object(forKey: restored) == nil)
        #expect(defaults.object(forKey: browser) != nil)
        #expect(SettingsWindow.selection(in: defaults) == .searchEngines)
    }

    @Test func anUnknownSectionShowsGeneral() throws {
        let defaults = try defaults()
        defaults.set("gone", forKey: SettingsWindow.selectionKey)
        #expect(SettingsWindow.selection(in: defaults) == .general)
    }
}

/// The list of sections is always there: nothing can fold it (a folded
/// split view was kept between launches, with no way back), even at the
/// window's smallest size.
@MainActor
struct SettingsSectionsListTests {
    /// The window's content at a size, never shown on the screen.
    private func layOut(width: CGFloat, height: CGFloat) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SettingsContentView()
            .environmentObject(ToastManager.shared)
            .environmentObject(AppearanceManager.shared)
            .environmentObject(UpdateService.shared)
            .environmentObject(DefaultBrowserManager.shared)
            .modelContainer(DatabaseRecovery.mainContainer))
        window.contentView = host
        host.frame = window.contentRect(forFrameRect: window.frame)
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(views(in:))
    }

    private func sectionsList(in host: NSView) -> NSScrollView? {
        let scrolls = views(in: host).compactMap { $0 as? NSScrollView }
        if #available(macOS 26, *) {
            return scrolls.first { $0.convert($0.bounds, to: host).minX < SettingsWindow.sidebarInset + 1 }
        }
        return views(in: host).compactMap { $0 as? NSTableView }.first?.enclosingScrollView
    }

    @Test(arguments: [false, true])
    func theSectionsListIsAlwaysThere(atMinimumSize: Bool) async throws {
        let size = atMinimumSize ? SettingsWindow.minimumSize : CGSize(width: 1100, height: 760)
        let (width, height) = (size.width, size.height)
        let (window, host) = layOut(width: width, height: height)
        defer {
            window.contentView = nil
            window.close()
        }
        // A list appears after its first layout passes: on macOS 26, the
        // glass list (a scroll view at the window's left); before, a table.
        var list: NSScrollView?
        for _ in 0 ..< 50 where list == nil {
            try await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
            list = sectionsList(in: host)
        }
        // No split view: nothing to fold, nothing remembered folded.
        #expect(!views(in: host).contains { $0 is NSSplitView })
        let scroll = try #require(list)
        if let table = scroll.documentView as? NSTableView {
            #expect(table.numberOfRows == SettingsTab.allCases.count)
        }
        let frame = scroll.convert(scroll.bounds, to: host)
        #expect(frame.width >= SettingsWindow.sidebarWidth - 1, "\(frame)")
        #expect(frame.minX < SettingsWindow.sidebarInset + 1)
        // The content cannot be narrower than the list plus the page's room.
        #expect(host.fittingSize.width >= SettingsWindow.sidebarWidth + SettingsWindow.minimumDetailWidth)
    }
}
