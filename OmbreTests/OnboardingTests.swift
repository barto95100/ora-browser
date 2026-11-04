import Foundation
@testable import Ombre
import SwiftData
import Testing

struct OnboardingFlowTests {
    @Test func everyStepWhenZenIsThereAndOmbreIsNotDefault() {
        let flow = OnboardingFlow(zenAvailable: true, isDefaultBrowser: false)
        #expect(flow.steps == [.welcome, .importZen, .spaces, .protection, .defaultBrowser, .ready])
    }

    @Test func stepsWithNothingToOfferAreLeftOut() {
        let flow = OnboardingFlow(zenAvailable: false, isDefaultBrowser: true)
        #expect(flow.steps == [.welcome, .spaces, .protection, .ready])
    }

    @Test func nextAndBackStayWithinTheSteps() {
        var flow = OnboardingFlow(zenAvailable: false, isDefaultBrowser: true)
        flow.back()
        #expect(flow.current == .welcome)
        #expect(!flow.canGoBack)
        for _ in 0 ..< 10 {
            flow.next()
        }
        #expect(flow.current == .ready)
        #expect(flow.isLast)
        flow.back()
        #expect(flow.current == .protection)
    }
}

struct OnboardingPlanTests {
    private let initial = OnboardingChoices(firstSpace: SpaceTemplate.personal.look)

    private func plan(_ choices: OnboardingChoices, others: [String] = []) -> OnboardingPlan {
        OnboardingPlan.make(choices, initial: initial, otherSpaceNames: others)
    }

    @Test func nothingConfirmedKeepsEverythingButTheFirstSpace() {
        var choices = initial
        choices.importedSpaces = [0, 1]
        choices.templates = [.work]
        choices.protection = .off
        choices.appearance = .dark

        let result = plan(choices)

        #expect(result == OnboardingPlan(firstSpace: SpaceTemplate.personal.look))
    }

    @Test func confirmedStepsAreApplied() {
        var choices = initial
        choices.importedSpaces = [2, 0]
        choices.confirm(.importZen)
        choices.firstSpace.name = "  Home  "
        choices.templates = [.work]
        choices.sidebarPosition = .secondary
        choices.appearance = .dark
        choices.confirm(.spaces)
        choices.protection = .strict
        choices.confirm(.protection)

        let result = plan(choices)

        #expect(result.importedSpaces == [0, 2])
        #expect(result.firstSpace.name == "Home")
        #expect(result.newSpaces == [SpaceTemplate.work.look])
        #expect(result.sidebarPosition == .secondary)
        #expect(result.appearance == .dark)
        #expect(result.protection == .strict)
    }

    @Test func skipPutsTheStepBack() {
        var choices = initial
        choices.firstSpace.name = "Changed"
        choices.templates = [.work]
        choices.confirm(.spaces)
        choices.protection = .off
        choices.confirm(.protection)

        choices.skip(.spaces, initial: initial)
        choices.skip(.protection, initial: initial)

        #expect(choices == initial)
        #expect(plan(choices).protection == nil)
    }

    @Test func templatesSkipTakenNamesWhateverTheirCase() {
        var choices = initial
        choices.templates = [.personal, .work]
        choices.confirm(.spaces)

        // "Personal" is the first space; "work" is another space.
        let result = plan(choices, others: ["work "])

        #expect(result.newSpaces.isEmpty)
    }

    @Test func anEmptyNameKeepsTheFirstSpaceName() {
        var choices = initial
        choices.firstSpace.name = "   "
        choices.confirm(.spaces)

        #expect(plan(choices).firstSpace.name == "Personal")
    }

    @Test func templateAvailability() {
        #expect(SpaceTemplate.isAvailable(.work, takenNames: ["Personal"]))
        #expect(!SpaceTemplate.isAvailable(.work, takenNames: ["WORK"]))
    }
}

struct OnboardingStatusTests {
    @Test func neededUntilDone() throws {
        let suite = "onboarding-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OnboardingStatus.isNeeded(in: defaults))
        OnboardingStatus.markDone(in: defaults)
        #expect(!OnboardingStatus.isNeeded(in: defaults))
        // An older version shows it again.
        defaults.set(OnboardingStatus.currentVersion - 1, forKey: OnboardingStatus.key)
        #expect(OnboardingStatus.isNeeded(in: defaults))
    }
}

struct ProtectionLevelTests {
    private func applied(_ level: ProtectionLevel, to settings: SpacePrivacySettings = SpacePrivacySettings())
        -> SpacePrivacySettings
    {
        var settings = settings
        level.apply(to: &settings)
        return settings
    }

    @Test func standardBlocksAdsAndTrackersButNotFingerprintingInNormalWindows() {
        let settings = applied(.standard)
        #expect(settings.adBlock.enabled)
        #expect(settings.blockThirdPartyTrackers)
        #expect(!settings.blockFingerprinting)
        for id in FilterListCatalogService.recommendedProtectionIDs {
            #expect(settings.adBlock.enabledBuiltinListIDs.contains(id))
        }
    }

    @Test func strictAddsFingerprinting() {
        let settings = applied(.strict)
        #expect(settings.adBlock.enabled)
        #expect(settings.blockThirdPartyTrackers)
        #expect(settings.blockFingerprinting)
    }

    @Test func offBlocksNothingAndKeepsTheRest() {
        var start = applied(.strict)
        start.cookiesPolicy = .blockThirdParty
        start.exemptSites = ["example.com"]

        let settings = applied(.off, to: start)

        #expect(!settings.adBlock.enabled)
        #expect(!settings.blockThirdPartyTrackers)
        #expect(!settings.blockFingerprinting)
        #expect(settings.cookiesPolicy == .blockThirdParty)
        #expect(settings.exemptSites == ["example.com"])
    }

    @Test func privateWindowsAlwaysGetTheFingerprintingProtection() {
        let standard = applied(.standard)
        #expect(BrowserPrivacyService.privacyScripts(for: standard, isPrivate: false).isEmpty)
        #expect(!BrowserPrivacyService.privacyScripts(for: standard, isPrivate: true).isEmpty)
        #expect(!BrowserPrivacyService.privacyScripts(for: applied(.off), isPrivate: true).isEmpty)
        #expect(!BrowserPrivacyService.privacyScripts(for: applied(.strict), isPrivate: false).isEmpty)
    }
}

struct OnboardingImportTests {
    @Test func zenProfileNameDropsTheRandomPrefix() {
        #expect(ZenImporter.profileName(URL(fileURLWithPath: "/p/8kss89t1.Default (release)")) == "Default (release)")
        #expect(ZenImporter.profileName(URL(fileURLWithPath: "/p/Plain")) == "Plain")
    }

    @Test func selectingKeepsTheOrderAndIgnoresUnknownPositions() {
        let data = ImportedBrowserData(spaces: ["A", "B", "C"].map { ImportedSpace(name: $0) })
        #expect(data.selecting([2, 0, 7]).spaces.map(\.name) == ["A", "C"])
    }
}

@MainActor
struct OnboardingApplierTests {
    @Test func planIsAppliedWithoutLeavingTheFirstSpace() async throws {
        let savedLevel = UserDefaults.standard.object(forKey: PrivacyDefaults.newSpaceLevelKey)
        defer { UserDefaults.standard.set(savedLevel, forKey: PrivacyDefaults.newSpaceLevelKey) }

        try await TabManagerTestWindow.run { window in
            let existing = window.createSpace("Existing")
            let first = try #require(window.tabManager.activeContainer)
            let plan = OnboardingPlan(
                firstSpace: SpaceLook(name: "Home", iconSymbol: "house", color: .green),
                newSpaces: [SpaceTemplate.work.look],
                protection: .strict
            )

            OnboardingApplier.apply(OnboardingResult(plan: plan, zenSpaces: nil), tabManager: window.tabManager)

            #expect(window.tabManager.activeContainer?.id == first.id)
            #expect(first.name == "Home")
            #expect(first.iconSymbol == "house")
            let work = try #require(window.spaces().first { $0.name == "Work" })
            #expect(work.order > existing.order)
            #expect(PrivacyDefaults.newSpaceLevel == .strict)
            for space in window.spaces() {
                #expect(SettingsStore.shared.privacySettings(for: space.id).blockFingerprinting, "\(space.name)")
            }
        }
    }

    @Test func aNewDatabaseGetsItsFirstSpaceRenamed() async throws {
        try await TabManagerTestWindow.run { window in
            let first = try #require(window.tabManager.activeContainer)
            let plan = OnboardingPlan(firstSpace: SpaceTemplate.personal.look)

            OnboardingApplier.apply(OnboardingResult(plan: plan, zenSpaces: nil), tabManager: window.tabManager)

            #expect(window.spaces().count == 1)
            #expect(first.name == "Personal")
            #expect(first.iconSymbol == "house")
        }
    }

    @Test func theSpaceShownIsTheOneEditedEvenIfAnotherIsActive() async throws {
        try await TabManagerTestWindow.run { window in
            let shown = try #require(window.tabManager.activeContainer)
            let other = window.createSpace("Other")
            #expect(window.tabManager.activeContainer?.id == other.id)
            let plan = OnboardingPlan(firstSpace: SpaceLook(name: "Shown"))

            OnboardingApplier.apply(
                OnboardingResult(plan: plan, firstSpaceID: shown.id, zenSpaces: nil),
                tabManager: window.tabManager
            )

            #expect(shown.name == "Shown")
            #expect(other.name == "Other")
        }
    }
}

@MainActor
struct OnboardingModelTests {
    private func model() -> OnboardingModel {
        OnboardingModel(
            modelContext: ModelContext(DatabaseRecovery.inMemoryContainer()),
            isDefaultBrowser: true,
            zenProfiles: []
        )
    }

    @Test func finishGivesOneResultOnly() {
        let model = model()
        model.goOn()
        #expect(model.finish(asConfirmed: true) != nil)
        #expect(model.finish(asConfirmed: true) == nil)
        #expect(model.finish(asConfirmed: false) == nil)
    }

    @Test func closingUsesTheDefaults() throws {
        let model = model()
        model.goOn()
        model.choices.firstSpace.name = "Changed"
        model.choices.templates = [.work]
        model.goOn()

        let result = try #require(model.finish(asConfirmed: false))

        #expect(result.plan == OnboardingPlan(firstSpace: SpaceTemplate.personal.look))
        #expect(result.firstSpaceID == nil)
    }

    @Test func aNewDatabaseHasNoZenStepAndNoSpaceToEdit() {
        let model = model()
        #expect(!model.flow.steps.contains(.importZen))
        #expect(!model.editsExistingSpace)
    }

    @Test func theHandoffIsTakenOnce() {
        let plan = OnboardingPlan(firstSpace: SpaceLook(name: "A"))
        OnboardingHandoff.hand(OnboardingResult(plan: plan, zenSpaces: nil))
        #expect(OnboardingHandoff.take()?.plan == plan)
        #expect(OnboardingHandoff.take() == nil)
    }
}
