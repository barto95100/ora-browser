import Foundation
@testable import Ombre
import SwiftData
import Testing

extension TabManagerTests {
    /// A window's managers share one context, made once per window
    /// (`WindowSession`); normal windows share the app's one container.
    @MainActor
    struct WindowSessionTests {
        /// Closes the session's window and removes its spaces' settings.
        private func cleanUp(_ session: WindowSession) {
            session.tabManager.tearDown()
            let spaces = (try? session.modelContext.fetch(FetchDescriptor<TabContainer>())) ?? []
            for space in spaces {
                SettingsStore.shared.removeContainerSettings(for: space.id)
            }
        }

        @Test func managersShareTheSessionContext() {
            let session = WindowSession(isPrivate: true)
            defer { cleanUp(session) }

            #expect(session.tabManager.modelContext === session.modelContext)
            #expect(session.historyManager.modelContext === session.modelContext)
            #expect(session.downloadManager.modelContext === session.modelContext)
            #expect(session.tabManager.modelContainer === session.modelContainer)
            #expect(session.mediaController.tabManager === session.tabManager)
            #expect(session.privacyMode.isPrivate)
        }

        /// Each private window keeps its data in memory, apart from the others
        /// and from the main database.
        @Test func privateWindowsHaveTheirOwnContainer() {
            let first = WindowSession(isPrivate: true)
            let second = WindowSession(isPrivate: true)
            defer {
                cleanUp(first)
                cleanUp(second)
            }

            #expect(first.modelContainer !== second.modelContainer)
            #expect(first.modelContainer !== DatabaseRecovery.mainContainer)
        }

        @Test func normalWindowUsesTheContainerItIsGiven() {
            let container = DatabaseRecovery.inMemoryContainer()
            let session = WindowSession(isPrivate: false, container: container)
            defer { cleanUp(session) }

            #expect(session.modelContainer === container)
            #expect(!session.privacyMode.isPrivate)
        }
    }
}
