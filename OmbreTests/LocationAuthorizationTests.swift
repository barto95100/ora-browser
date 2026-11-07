import CoreLocation
@testable import Ombre
import Testing

/// macOS's Location Services permission, asked by Ombre when a site the user
/// allowed wants the position (WebKit never asks: the page waited forever).
@MainActor
struct LocationAuthorizationTests {
    private final class FakeManager: LocationManaging {
        var authorizationStatus: CLAuthorizationStatus
        var onAuthorizationChange: (() -> Void)?
        var requests = 0
        var locationRequests: [(Error?) -> Void] = []

        init(_ status: CLAuthorizationStatus) {
            authorizationStatus = status
        }

        func requestAuthorization() {
            requests += 1
        }

        func requestOneLocation(_ completion: @escaping (Error?) -> Void) {
            locationRequests.append(completion)
        }

        /// macOS's answer to its prompt.
        func answer(_ status: CLAuthorizationStatus) {
            authorizationStatus = status
            onAuthorizationChange?()
        }
    }

    @Test(arguments: [
        (CLAuthorizationStatus.authorizedAlways, LocationAuthorization.Outcome.authorized),
        (.denied, .denied),
        (.restricted, .denied)
    ])
    func aDecidedStatusAnswersAtOnce(status: CLAuthorizationStatus, outcome: LocationAuthorization.Outcome) {
        let manager = FakeManager(status)
        let authorization = LocationAuthorization(manager: manager)
        var outcomes: [LocationAuthorization.Outcome] = []
        authorization.ensureAuthorized { outcomes.append($0) }
        #expect(outcomes == [outcome])
        #expect(manager.requests == 0)
    }

    /// Not decided yet: macOS is asked once, and every site waiting gets its answer.
    @Test(arguments: [CLAuthorizationStatus.authorizedAlways, .denied])
    func macOSIsAskedOnce(answer: CLAuthorizationStatus) {
        let manager = FakeManager(.notDetermined)
        let authorization = LocationAuthorization(manager: manager)
        var outcomes: [LocationAuthorization.Outcome] = []
        authorization.ensureAuthorized { outcomes.append($0) }
        authorization.ensureAuthorized { outcomes.append($0) }
        #expect(manager.requests == 1)
        #expect(outcomes.isEmpty)
        // A change that is no answer yet.
        manager.answer(.notDetermined)
        #expect(outcomes.isEmpty)
        manager.answer(answer)
        let expected = LocationAuthorization.outcome(of: answer)
        #expect(outcomes == [expected, expected].compactMap { $0 })
    }

    @Test
    func noAnswerFromMacOSEnds() async {
        let manager = FakeManager(.notDetermined)
        let authorization = LocationAuthorization(manager: manager)
        authorization.timeout = .milliseconds(50)
        var outcomes: [LocationAuthorization.Outcome] = []
        authorization.ensureAuthorized { outcomes.append($0) }
        for _ in 0 ..< 100 where outcomes.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(outcomes == [.noAnswer])
        // A late answer changes nothing.
        manager.answer(.authorizedAlways)
        #expect(outcomes == [.noAnswer])
    }

    @Test
    func aPositionFoundTellsNothing() async {
        let manager = FakeManager(.authorizedAlways)
        let authorization = LocationAuthorization(manager: manager)
        var told = 0
        authorization.onNoPosition = { told += 1 }
        authorization.positionTimeout = .milliseconds(50)
        authorization.checkPosition()
        #expect(manager.locationRequests.count == 1)
        manager.locationRequests.first?(nil)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(told == 0)
    }

    @Test
    func noPositionIsTold() {
        let manager = FakeManager(.authorizedAlways)
        let authorization = LocationAuthorization(manager: manager)
        var told = 0
        authorization.onNoPosition = { told += 1 }
        authorization.positionTimeout = .seconds(5)
        authorization.checkPosition()
        manager.locationRequests.first?(CLError(.locationUnknown))
        #expect(told == 1)
    }

    @Test
    func aPositionThatNeverComesIsTold() async {
        let manager = FakeManager(.authorizedAlways)
        let authorization = LocationAuthorization(manager: manager)
        var told = 0
        authorization.onNoPosition = { told += 1 }
        authorization.positionTimeout = .milliseconds(50)
        authorization.checkPosition()
        for _ in 0 ..< 100 where told == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(told == 1)
        // The late answer is ignored.
        manager.locationRequests.first?(nil)
        #expect(told == 1)
    }

    // MARK: - The site's answer

    /// What WebKit is told, and what the user is told.
    private final class Answers {
        var decisions: [BrowserPermissionDecision] = []
        var told: [LocationAuthorization.Outcome] = []
    }

    private func answering(
        _ decision: BrowserPermissionDecision,
        with manager: FakeManager
    ) -> (LocationAuthorization, Answers) {
        let authorization = LocationAuthorization(manager: manager)
        let answers = Answers()
        authorization.onRefusal = { answers.told.append($0) }
        authorization.onNoPosition = {}
        authorization.answer(decision) { answers.decisions.append($0) }
        return (authorization, answers)
    }

    @Test
    func aRefusedSiteNeverAsksMacOS() {
        let manager = FakeManager(.notDetermined)
        let (_, answers) = answering(.deny, with: manager)
        #expect(answers.decisions == [.deny])
        #expect(manager.requests == 0)
        #expect(answers.told.isEmpty)
    }

    /// The bug: the site was allowed, macOS never asked, the page waited.
    @Test
    func anAllowedSiteWaitsForMacOS() {
        let manager = FakeManager(.notDetermined)
        let (_, answers) = answering(.grant, with: manager)
        #expect(manager.requests == 1)
        #expect(answers.decisions.isEmpty)
        manager.answer(.authorizedAlways)
        #expect(answers.decisions == [.grant])
        #expect(answers.told.isEmpty)
        // Then a position is looked for.
        #expect(manager.locationRequests.count == 1)
    }

    @Test
    func macOSRefusingRefusesTheSiteAndTellsOnce() {
        let manager = FakeManager(.denied)
        let (authorization, answers) = answering(.grant, with: manager)
        authorization.answer(.grant) { answers.decisions.append($0) }
        #expect(answers.decisions == [.deny, .deny])
        #expect(answers.told == [.denied])
        #expect(manager.locationRequests.isEmpty)
    }

    @Test
    func noAnswerFromMacOSRefusesTheSiteAndAsksAgainLater() async {
        let manager = FakeManager(.notDetermined)
        let authorization = LocationAuthorization(manager: manager)
        authorization.timeout = .milliseconds(50)
        let answers = Answers()
        authorization.onRefusal = { answers.told.append($0) }
        authorization.answer(.grant) { answers.decisions.append($0) }
        for _ in 0 ..< 100 where answers.decisions.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(answers.decisions == [.deny])
        #expect(answers.told == [.noAnswer])
        authorization.answer(.grant) { answers.decisions.append($0) }
        #expect(manager.requests == 2)
    }

    @Test
    func positionRefusedLaterSaysLocationIsOff() {
        let manager = FakeManager(.authorizedAlways)
        let (authorization, answers) = answering(.grant, with: manager)
        manager.locationRequests.first?(CLError(.denied))
        #expect(answers.told == [.denied])
        withExtendedLifetime(authorization) {}
    }
}
