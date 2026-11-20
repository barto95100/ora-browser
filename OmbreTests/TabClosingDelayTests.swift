import Foundation
@testable import Ombre
import Testing

/// The delays before closing tabs not shown, and how a site's permissions show.
@MainActor
struct TabClosingDelayTests {
    private let hour = TabClosingDelay.hour
    private let day = TabClosingDelay.day

    @Test func theDelaysOfferedAreLikeArcs() {
        #expect(TabClosingDelay.presets == [12 * hour, day, 2 * day, 7 * day, 30 * day])
        #expect(TabClosingDelay.presets.map(TabClosingDelay.title)
            == [
                String(localized: "\(12) hours"),
                String(localized: "\(1) days"),
                String(localized: "\(2) days"),
                String(localized: "\(1) weeks"),
                String(localized: "1 month")
            ])
        #expect(TabClosingDelay.title(TabClosingDelay.never) == String(localized: "Never"))
    }

    @Test func aCustomDelayIsANumberOfHoursDaysOrWeeks() {
        #expect(TabClosingDelay.custom(5, .hours) == 5 * hour)
        #expect(TabClosingDelay.custom(3, .days) == 3 * day)
        #expect(TabClosingDelay.custom(2, .weeks) == 14 * day)
        #expect(TabClosingDelay.custom(0, .days) == nil)
        #expect(TabClosingDelay.custom(-2, .hours) == nil)
        // A year at most.
        #expect(TabClosingDelay.custom(900, .weeks) == TabClosingDelay.longest)
    }

    /// Shown and edited again in its largest whole unit.
    @Test func aDelayIsReadInItsLargestWholeUnit() {
        #expect(TabClosingDelay.parts(of: 36 * hour) == (36, .hours))
        #expect(TabClosingDelay.parts(of: 3 * day) == (3, .days))
        #expect(TabClosingDelay.parts(of: 14 * day) == (2, .weeks))
        #expect(TabClosingDelay.parts(of: 6 * hour) == (6, .hours))
    }

    @Test func aSavedDelayIsKeptAsChosen() {
        // None saved: the current default (1 day).
        #expect(TabClosingDelay.normalized(0) == day)
        // The old choices and custom ones stay as they are.
        for kept in [hour, 6 * hour, 12 * hour, day, 2 * day, 3 * day, 7 * day, 30 * day] {
            #expect(TabClosingDelay.normalized(kept) == kept)
        }
        #expect(TabClosingDelay.normalized(60) == hour)
        #expect(TabClosingDelay.normalized(TabClosingDelay.never) == TabClosingDelay.never)
        #expect(TabClosingDelay.normalized(2 * TabClosingDelay.never) == TabClosingDelay.never)
    }

    /// A space's choice made before keeps its delay; none follows the general one.
    @Test func aSpacesEarlierChoiceIsKept() {
        #expect(TabClosingDelay.spaceDelay(fromLegacy: "1 Hour") == hour)
        #expect(TabClosingDelay.spaceDelay(fromLegacy: "1 Day") == day)
        #expect(TabClosingDelay.spaceDelay(fromLegacy: "1 Week") == 7 * day)
        #expect(TabClosingDelay.spaceDelay(fromLegacy: "Never") == nil)
    }

    @Test func aSpacesDelayIsSavedAndReplacesTheEarlierChoice() {
        let space = UUID()
        let settings = SettingsStore.shared
        defer { settings.removeContainerSettings(for: space) }
        #expect(settings.spaceClosingDelay(for: space) == nil)
        UserDefaults.standard.set("1 Week", forKey: "settings.container.\(space.uuidString).autoClearTabsAfter")
        #expect(settings.spaceClosingDelay(for: space) == 7 * day)
        settings.setSpaceClosingDelay(3 * day, for: space)
        #expect(settings.spaceClosingDelay(for: space) == 3 * day)
        settings.setSpaceClosingDelay(nil, for: space)
        #expect(settings.spaceClosingDelay(for: space) == nil)
    }

    // MARK: - A site's permissions on one line

    @Test func eachStateShowsDifferently() {
        #expect(SitePermissionBadge.tone(.allow) == .allowed)
        #expect(SitePermissionBadge.tone(.deny) == .refused)
        #expect(SitePermissionBadge.tone(.ask) == .asks)
        #expect(SitePermissionBadge.tone(nil) == .general)
        for type in SitePermissionType.allCases {
            #expect(SitePermissionBadge.symbol(type, refused: true) != SitePermissionBadge.symbol(type, refused: false))
        }
    }

    /// Downloads without a choice of their own show the general one.
    @Test func downloadsWithoutAChoiceShowTheGeneralOne() {
        let permissions = SitePermissions(camera: .allow, microphone: .deny)
        #expect(SitePermissionBadge.state(of: .camera, in: permissions) == .allow)
        #expect(SitePermissionBadge.state(of: .microphone, in: permissions) == .deny)
        #expect(SitePermissionBadge.state(of: .notifications, in: permissions) == .ask)
        #expect(SitePermissionBadge.state(of: .downloads, in: permissions) == nil)
        #expect(SitePermissionBadge.state(of: .downloads, in: SitePermissions(downloads: .allow)) == .allow)
    }
}
