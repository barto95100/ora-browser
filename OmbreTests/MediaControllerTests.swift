import Foundation
@testable import Ombre
import Testing

@MainActor
struct MediaControllerTests {
    private let pageURL = URL(string: "https://www.youtube.com/watch?v=1")!

    private func event(
        _ type: String,
        state: String? = nil,
        wasPlayed: Bool? = nil,
        volume: Double? = nil
    ) -> MediaEventPayload {
        MediaEventPayload(
            type: type,
            wasPlayed: wasPlayed,
            state: state,
            volume: volume,
            title: nil,
            hasNext: nil,
            hasPrevious: nil
        )
    }

    private func play(_ tabID: UUID, in controller: MediaController, title: String = "Video") {
        controller.receive(
            event: event("state", state: "playing", wasPlayed: true),
            tabID: tabID,
            title: title,
            pageURL: pageURL,
            favicon: nil
        )
    }

    @Test func playingCreatesAVisibleSession() {
        let controller = MediaController()
        let tabID = UUID()

        play(tabID, in: controller)

        #expect(controller.sessions.map(\.tabID) == [tabID])
        #expect(controller.sessions.first?.isPlaying == true)
        #expect(controller.primary?.tabID == tabID)
        #expect(controller.isVisible)
    }

    @Test func aSessionNeverPlayedStaysHidden() {
        let controller = MediaController()

        controller.receive(
            event: event("state", state: "paused", wasPlayed: false),
            tabID: UUID(),
            title: "Video",
            pageURL: pageURL,
            favicon: nil
        )

        #expect(controller.sessions.count == 1)
        #expect(controller.primary == nil)
        #expect(!controller.isVisible)
    }

    @Test func aTitleChangeUpdatesOnlyItsTabSession() {
        let controller = MediaController()
        let first = UUID()
        let second = UUID()
        play(first, in: controller, title: "First")
        play(second, in: controller, title: "Second")

        controller.syncTitleForTab(first, newTitle: "Next track")

        #expect(controller.sessions.first { $0.tabID == first }?.title == "Next track")
        #expect(controller.sessions.first { $0.tabID == second }?.title == "Second")
    }

    @Test func theTabThatStartsPlayingComesFirst() {
        let controller = MediaController()
        let first = UUID()
        let second = UUID()
        play(first, in: controller)
        play(second, in: controller)
        #expect(controller.primary?.tabID == second)

        play(first, in: controller)

        #expect(controller.sessions.map(\.tabID) == [first, second])
    }

    @Test func pausingKeepsTheSession() {
        let controller = MediaController()
        let tabID = UUID()
        play(tabID, in: controller)

        controller.receive(
            event: event("state", state: "paused", wasPlayed: true),
            tabID: tabID,
            title: "Video",
            pageURL: pageURL,
            favicon: nil
        )

        #expect(controller.sessions.first?.isPlaying == false)
        #expect(controller.isVisible)
    }

    @Test func removingAPageSessionKeepsTheOthers() {
        let controller = MediaController()
        let first = UUID()
        let second = UUID()
        play(first, in: controller)
        play(second, in: controller)

        // Navigation to a new document, page unloaded, tab closed or crashed.
        controller.removeSession(for: second)

        #expect(controller.sessions.map(\.tabID) == [first])
        #expect(controller.isVisible)
    }

    @Test func removingTheLastSessionHidesThePlayer() {
        let controller = MediaController()
        let tabID = UUID()
        play(tabID, in: controller)

        controller.removeSession(for: tabID)

        #expect(controller.sessions.isEmpty)
        #expect(!controller.isVisible)
    }

    @Test func aRemovedMediaElementEndsTheSession() {
        let controller = MediaController()
        let tabID = UUID()
        play(tabID, in: controller)

        controller.receive(event: event("removed"), tabID: tabID, title: "Video", pageURL: pageURL, favicon: nil)

        #expect(controller.sessions.isEmpty)
        #expect(!controller.isVisible)
    }
}
