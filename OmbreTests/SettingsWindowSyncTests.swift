import AppKit
@testable import Ombre
import SwiftData
import SwiftUI
import Testing

/// The Settings and Passwords windows read the database through the main
/// context; a browser window saves through its own (lot F).
@MainActor
struct SettingsWindowSyncTests {
    final class Seen {
        var names: [String] = []
        var draws = 0
    }

    private struct SpacesList: View {
        @Query(sort: TabContainer.displayOrder) var spaces: [TabContainer]
        let seen: Seen

        var body: some View {
            let names = spaces.map(\.name)
            seen.names = names
            seen.draws += 1
            return Text(names.joined(separator: ","))
        }
    }

    private func showSpaces(of container: ModelContainer, seen: Seen) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SpacesList(seen: seen).modelContainer(container))
        return window
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func aSpaceChangedInABrowserWindowShowsInSettings() async throws {
        let container = DatabaseRecovery.inMemoryContainer()
        let seen = Seen()
        let window = showSpaces(of: container, seen: seen)
        defer { window.close() }
        try await waitUntil { seen.draws > 0 }
        #expect(seen.draws > 0)

        let browser = ModelContext(container)
        let space = TabContainer(name: "Work")
        browser.insert(space)
        try browser.save()
        try await waitUntil { seen.names.contains("Work") }
        #expect(seen.names.contains("Work"))

        space.name = "Home"
        try browser.save()
        try await waitUntil { seen.names.contains("Home") }
        #expect(seen.names.contains("Home"))

        // Deleted there: gone here, never read as a deleted object.
        browser.delete(space)
        try browser.save()
        try await waitUntil { !seen.names.contains("Home") }
        #expect(!seen.names.contains("Home"))
    }
}
