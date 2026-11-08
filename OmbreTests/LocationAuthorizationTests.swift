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

        init(_ status: CLAuthorizationStatus) {
            authorizationStatus = status
        }

        func requestAuthorization() {
            requests += 1
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

    // MARK: - The site's answer

    /// What WebKit is told, and what the user is told.
    private final class Answers {
        var decisions: [BrowserPermissionDecision] = []
        var told: [LocationAuthorization.Outcome] = []
    }

    private func answering(
        _ decision: BrowserPermissionDecision,
        with manager: FakeManager,
        isProviderAvailable: Bool = true
    ) -> (LocationAuthorization, Answers) {
        let authorization = LocationAuthorization(manager: manager)
        let answers = Answers()
        authorization.onRefusal = { answers.told.append($0) }
        authorization.isProviderAvailable = { isProviderAvailable }
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
    }

    @Test
    func macOSRefusingRefusesTheSiteAndTellsOnce() {
        let manager = FakeManager(.denied)
        let (authorization, answers) = answering(.grant, with: manager)
        authorization.answer(.grant) { answers.decisions.append($0) }
        #expect(answers.decisions == [.deny, .deny])
        #expect(answers.told == [.denied])
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

    /// A WebKit without the provider's functions: every site refused,
    /// macOS never asked, the user told once.
    @Test
    func withoutTheProviderSitesAreRefusedAndToldOnce() {
        let manager = FakeManager(.notDetermined)
        let (authorization, answers) = answering(.grant, with: manager, isProviderAvailable: false)
        authorization.answer(.grant) { answers.decisions.append($0) }
        #expect(answers.decisions == [.deny, .deny])
        #expect(answers.told == [.unavailable])
        #expect(manager.requests == 0)
    }

    @Test
    func positionRefusedLaterSaysLocationIsOff() {
        let manager = FakeManager(.authorizedAlways)
        let (authorization, answers) = answering(.grant, with: manager)
        authorization.positionRefused()
        authorization.positionRefused()
        #expect(answers.told == [.denied])
    }
}
