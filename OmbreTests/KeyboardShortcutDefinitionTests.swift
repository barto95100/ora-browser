import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// The shortcuts shown in the settings (INT-10).
struct KeyboardShortcutDefinitionTests {
    /// Two shortcuts on one chord: one of them never works.
    @Test func defaultChordsAreUnique() {
        var seen: [(chord: KeyChord, id: String)] = []
        var duplicates: [String] = []
        for shortcut in KeyboardShortcuts.allShortcuts {
            if let other = seen.first(where: { $0.chord == shortcut.defaultChord }) {
                duplicates.append("\(other.id) / \(shortcut.id)")
            }
            seen.append((shortcut.defaultChord, shortcut.id))
        }
        #expect(duplicates.isEmpty, "\(duplicates)")
    }

    @Test func identifiersAreUnique() {
        let ids = KeyboardShortcuts.allShortcuts.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Nothing listed that the app doesn't do (developer tools have no
    /// public API; tabs aren't moved by keyboard).
    @Test func noShortcutForMissingFeatures() {
        let ids = Set(KeyboardShortcuts.allShortcuts.map(\.id))
        for missing in [
            "developer.toggleDevTools",
            "developer.reloadIgnoringCache",
            "tabs.moveRight",
            "tabs.moveLeft"
        ] {
            #expect(!ids.contains(missing))
        }
    }

    @Test func conflictNamesTheShortcutAlreadyUsingTheChord() {
        let reload = KeyboardShortcuts.Navigation.reload
        let conflict = KeyboardShortcuts.conflict(
            for: reload.defaultChord, excluding: KeyboardShortcuts.Tabs.new.id, chord: \.defaultChord
        )
        #expect(conflict?.id == reload.id)
        // Its own chord again is not a conflict.
        #expect(KeyboardShortcuts
            .conflict(for: reload.defaultChord, excluding: reload.id, chord: \.defaultChord) == nil)
        let unused = KeyChord(keyEquivalent: .init("j"), modifiers: [.command, .option, .control, .shift])
        #expect(KeyboardShortcuts.conflict(for: unused, excluding: reload.id, chord: \.defaultChord) == nil)
    }

    /// A letter typed with ⇧ is captured uppercase: still the same keys.
    @Test func conflictSeesLettersTypedWithShift() {
        let typed = KeyChord(keyEquivalent: .init("R"), modifiers: [.command, .shift])
        let conflict = KeyboardShortcuts.conflict(
            for: typed,
            excluding: KeyboardShortcuts.Tabs.new.id,
            chord: \.defaultChord
        )
        #expect(conflict?.id == KeyboardShortcuts.Navigation.hardReload.id)
    }

    @Test func zoomFollowsSafarisSteps() {
        #expect(PageZoom.level(after: 1, step: 1) == 1.15)
        #expect(PageZoom.level(after: 1, step: -1) == 0.85)
        #expect(PageZoom.level(after: 3, step: 1) == 3)
        #expect(PageZoom.level(after: 0.5, step: -1) == 0.5)
        #expect(PageZoom.level(after: 1.6, step: -1) == 1.5)
        #expect(PageZoom.level(after: 2.5, step: 0) == 1)
    }

    /// Next Tab starts on the tab used just before; Previous Tab on the oldest.
    @Test func tabSwitcherStartsAccordingToDirection() {
        #expect(TabSwitcherStart.index(count: 5, backward: false) == 1)
        #expect(TabSwitcherStart.index(count: 5, backward: true) == 4)
        #expect(TabSwitcherStart.index(count: 1, backward: true) == 0)
    }
}
