import AppKit
@testable import Ombre
import Testing

extension TabManagerTests {
    /// Settings › Spaces › New Space… opens the same editor as the sidebar's
    /// "+", over the front browser window.
    @MainActor
    @Suite(.serialized)
    struct NewSpaceEditorTests {
        @Test
        func theEditorOpensOverTheWindow() async throws {
            try await TabManagerTestWindow.run { managers in
                let dialogs = DialogManager()
                let id = SpaceEditorView.showNewSpace(dialogManager: dialogs, tabManager: managers.tabManager)
                #expect(dialogs.dialogs.map(\.id) == [id])
                dialogs.dismiss(id: id)
            }
        }

        /// From the settings: the space is added, the window stays where it was.
        @Test
        func fromTheSettingsTheWindowStays() async throws {
            try await TabManagerTestWindow.run { managers in
                let space = try managers.activeSpace
                let tab = try managers.open("/page")
                let added = SpaceEditorView.createSpace(
                    SpaceLook(name: "From Settings"),
                    in: managers.tabManager,
                    switchingToIt: false
                )
                managers.remember(added)
                #expect(managers.spaces().contains { $0.id == added.id })
                #expect(managers.tabManager.activeContainer?.id == space.id)
                #expect(managers.tabManager.activeTab?.id == tab.id)
            }
        }

        /// From the sidebar's "+": the window goes to the new space.
        @Test
        func fromTheSidebarTheWindowGoesThere() async throws {
            try await TabManagerTestWindow.run { managers in
                let added = SpaceEditorView.createSpace(
                    SpaceLook(name: "From Sidebar"),
                    in: managers.tabManager,
                    switchingToIt: true
                )
                managers.remember(added)
                #expect(managers.tabManager.activeContainer?.id == added.id)
            }
        }
    }
}
