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

@MainActor
struct OnboardingNightfallTests {
    private static let order = OnboardingStep.allCases

    /// Relative luminance of a `#RRGGBB` color.
    private func luminance(_ hex: String) -> Double {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { channel -> Double in
            let srgb = Double(channel) / 255
            return srgb <= 0.039_28 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private func meanLuminance(_ step: OnboardingStep) -> Double {
        let colors = OnboardingNightfall.sky(for: step).colors
        return colors.map(luminance).reduce(0, +) / Double(colors.count)
    }

    @Test func theSkiesDarkenFromStepToStep() {
        let values = Self.order.map(meanLuminance)
        for (earlier, later) in zip(values, values.dropFirst()) {
            #expect(later < earlier)
        }
    }

    /// Never a light sky (the text is light on every step), nor an almost
    /// black night.
    @Test(arguments: OnboardingStep.allCases)
    func aSkyIsNeverLightNorAlmostBlack(step: OnboardingStep) {
        let sky = OnboardingNightfall.sky(for: step)
        #expect(sky.colors.count == sky.locations.count)
        #expect(sky.locations.first == 0)
        #expect(sky.locations.last == 1)
        for color in sky.colors {
            #expect(luminance(color) > 0.015)
            #expect(luminance(color) < 0.5)
        }
    }

    /// The first and last skies stay in the same violet-pink family (the
    /// golden-to-black evening they replace was about 100 times apart).
    @Test func theFirstAndLastSkiesStayClose() {
        let first = meanLuminance(.welcome)
        let last = meanLuminance(.ready)
        #expect(first / last < 12)
    }

    @Test func starsComeOutAndTheShadowRises() {
        let stars = Self.order.map(OnboardingNightfall.starCount)
        let shadows = Self.order.map(OnboardingNightfall.shadow)
        #expect(stars.first == 0)
        #expect(stars.last == OnboardingNightfall.starField.count)
        #expect(zip(stars, stars.dropFirst()).allSatisfy { $0 < $1 })
        #expect(shadows.first == 0)
        // The planet ends exactly like the icon.
        #expect(shadows.last == 1)
        #expect(zip(shadows, shadows.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func inFullSunNoShadowShowsAndAtTheEndItIsTheIcons() {
        // The shadow's highest point is 0.45 of the globe down: pushed below it.
        #expect(0.45 + OmbrePlanet.shadowOffset(0) > 1)
        #expect(OmbrePlanet.shadowOffset(1) == 0)
        #expect(OmbrePlanet.shadowOffset(1.6) < 0)
    }

    @Test func starsAppearOneAfterTheOther() {
        #expect(OnboardingNightfall.visibility(ofStar: 0, shown: 0) == 0)
        #expect(OnboardingNightfall.visibility(ofStar: 5, shown: 5.5) == 0.5)
        #expect(OnboardingNightfall.visibility(ofStar: 5, shown: 12) == 1)
        #expect(OnboardingNightfall.visibility(ofStar: 12, shown: 12) == 0)
    }

    @Test func starsTwinkleBetweenFaintAndBright() {
        let star = OnboardingNightfall.starField[0]
        let values = stride(from: 0.0, to: 3.4, by: 0.1).map { OnboardingNightfall.twinkle(star, at: $0) }
        #expect(values.allSatisfy { $0 >= 0.2 - 1e-9 && $0 <= 1 + 1e-9 })
        #expect((values.max() ?? 0) - (values.min() ?? 0) > 0.7)
    }

    @Test func theStarsStayPutAndInTheWindow() {
        #expect(OnboardingNightfall.starField.count == 80)
        for star in OnboardingNightfall.starField {
            #expect((0 ..< 1).contains(star.left))
            #expect((0 ..< 1).contains(star.top))
        }
        var first = SeededRandom(seed: 3)
        var second = SeededRandom(seed: 3)
        #expect(first.next() == second.next())
    }
}

@MainActor
struct OnboardingWordsTests {
    @Test func shadeLevelsKeepTheirSettingsNames() {
        #expect(OnboardingProtectionStep.levels == [.off, .standard, .strict])
        #expect(OnboardingProtectionStep.levels.map(\.shadeTitle) == ["Sunny", "Ombre", "Deep shade"])
        #expect(OnboardingProtectionStep.levels.map(\.title) == ["Off", "Standard", "Strict"])
        #expect(OnboardingProtectionStep.levels.map(\.shadeShadow) == [0, 1, 1.6])
    }

    @Test func theImportButtonCountsTheSpaces() {
        #expect(OnboardingView.importLabel(count: 0) == "Continue")
        #expect(OnboardingView.importLabel(count: 1) == "Bring 1 space")
        #expect(OnboardingView.importLabel(count: 2) == "Bring 2 spaces")
    }

    @Test func theOfferedLooksExist() {
        #expect(OnboardingSpacesStep.symbols.allSatisfy(SpaceIcon.symbols.contains))
        #expect(OnboardingSpacesStep.symbols.allSatisfy { OnboardingSpacesStep.symbolNames[$0] != nil })
        #expect(OnboardingSpacesStep.symbols.count <= OnboardingSpacesStep.rowLength)
        #expect(Set(OnboardingSpacesStep.colors).count == 6)
    }

    @Test func theSpacesOwnLookStaysOfferedInOneRow() {
        let symbols = OnboardingSpacesStep.symbols
        // Already offered, or none: the list as it is.
        #expect(OnboardingSpacesStep.choices(symbols, keeping: "house") == symbols)
        #expect(OnboardingSpacesStep.choices(symbols, keeping: nil) == symbols)
        // A full row: the space's own takes the last place.
        let withLeaf = OnboardingSpacesStep.choices(symbols, keeping: "leaf")
        #expect(withLeaf.count == OnboardingSpacesStep.rowLength)
        #expect(withLeaf.last == "leaf")
        // Room left: added at the end.
        let colors = OnboardingSpacesStep.choices(OnboardingSpacesStep.colors, keeping: SpaceColor.teal)
        #expect(colors == OnboardingSpacesStep.colors + [.teal])
    }
}
