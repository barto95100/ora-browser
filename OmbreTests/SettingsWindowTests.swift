import AppKit
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

    @Test func anUnknownSectionShowsGeneral() throws {
        let defaults = try defaults()
        defaults.set("gone", forKey: SettingsWindow.selectionKey)
        #expect(SettingsWindow.selection(in: defaults) == .general)
    }
}
