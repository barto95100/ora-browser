import AppKit
import SwiftData
import SwiftUI

/// What the assistant hands to the first browser window: the plan, and the
/// Zen spaces to import. The Zen session (it holds sites' session keys) is
/// never written anywhere: it stays in memory until the import is done.
struct OnboardingResult {
    let plan: OnboardingPlan
    /// The space the plan's first space applies to; nil for the one a new
    /// database is given.
    var firstSpaceID: UUID?
    let zenSpaces: ImportedBrowserData?
}

/// The assistant's state, for one showing of its window.
@MainActor
final class OnboardingModel: ObservableObject {
    static let zenBundleIdentifier = "app.zen-browser.zen"

    @Published var flow: OnboardingFlow
    @Published var choices: OnboardingChoices
    let initial: OnboardingChoices
    /// The spaces other than the first one (when the database already has
    /// spaces: an earlier version's data, or the Debug menu's relaunch).
    let otherSpaceNames: [String]
    /// The space the assistant edits, when the database has one.
    let firstSpaceID: UUID?

    var editsExistingSpace: Bool {
        firstSpaceID != nil
    }

    let zenProfiles: [URL]
    /// Each profile's name and when it was last used, read once.
    let zenProfileTitles: [URL: String]
    @Published private(set) var zenProfile: URL?
    @Published private(set) var zenSpaces: ImportedBrowserData?
    @Published private(set) var zenFailure: String?
    @Published private(set) var isZenRunning = false

    private(set) var isFinished = false
    /// Quitting closes the window too: that must not count as done.
    private var isTerminating = false
    private var terminationObserver: NSObjectProtocol?

    init(
        modelContext: ModelContext,
        isDefaultBrowser: Bool,
        zenProfiles: [URL] = ZenImporter.profiles()
    ) {
        let descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
        let spaces = (try? modelContext.fetch(descriptor)) ?? []
        let firstSpace = spaces.first.map(SpaceLook.init(of:)) ?? SpaceTemplate.personal.look
        let sidebarPosition = UserDefaults.standard.string(forKey: SidebarPosition.defaultsKey)
            .flatMap(SidebarPosition.init(rawValue:)) ?? .primary
        let initial = OnboardingChoices(
            firstSpace: firstSpace,
            sidebarPosition: sidebarPosition,
            appearance: AppearanceManager.shared.appearance
        )
        self.initial = initial
        choices = initial
        otherSpaceNames = spaces.dropFirst().map(\.name)
        firstSpaceID = spaces.first?.id
        self.zenProfiles = zenProfiles
        zenProfileTitles = Dictionary(uniqueKeysWithValues: zenProfiles.map { ($0, Self.profileTitle($0)) })
        flow = OnboardingFlow(zenAvailable: !zenProfiles.isEmpty, isDefaultBrowser: isDefaultBrowser)
        if let profile = zenProfiles.first {
            selectZenProfile(profile)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isTerminating = true }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: - Navigation

    func goOn() {
        choices.confirm(flow.current)
        flow.next()
    }

    func skip() {
        choices.skip(flow.current, initial: initial)
        flow.next()
    }

    func back() {
        flow.back()
    }

    /// The plan, once: from the choices, or the defaults when the window was
    /// closed (`asConfirmed` false). Nil when already finished.
    func finish(asConfirmed: Bool) -> OnboardingResult? {
        guard !isFinished, !isTerminating else { return nil }
        isFinished = true
        let finalChoices = asConfirmed ? choices : initial
        let plan = OnboardingPlan.make(finalChoices, initial: initial, otherSpaceNames: otherSpaceNames)
        let zen = plan.importedSpaces.isEmpty ? nil : zenSpaces?.selecting(plan.importedSpaces)
        zenSpaces = nil
        return OnboardingResult(plan: plan, firstSpaceID: firstSpaceID, zenSpaces: zen)
    }

    // MARK: - Zen

    func selectZenProfile(_ profile: URL) {
        zenProfile = profile
        reloadZen()
    }

    /// Reads the profile again (after quitting Zen, for its latest changes).
    func reloadZen() {
        isZenRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.zenBundleIdentifier)
            .isEmpty
        guard let zenProfile else { return }
        do {
            let spaces = try ZenImporter.read(profile: zenProfile)
            zenSpaces = spaces
            zenFailure = nil
            choices.importedSpaces = Set(spaces.spaces.indices)
        } catch {
            zenSpaces = nil
            zenFailure = "This profile couldn't be read."
            choices.importedSpaces = []
        }
    }

    static func profileTitle(_ profile: URL) -> String {
        let name = ZenImporter.profileName(profile)
        guard let date = ZenImporter.lastUsed(profile) else { return name }
        return "\(name) — last used \(date.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Spaces

    /// Names a template can't take: the other spaces and the first one.
    var takenNames: [String] {
        otherSpaceNames + [choices.firstSpace.trimmedName]
    }
}

/// Hands the assistant's result to the first browser window that opens.
@MainActor
enum OnboardingHandoff {
    private static var pending: OnboardingResult?

    static func hand(_ result: OnboardingResult) {
        pending = result
    }

    static func take() -> OnboardingResult? {
        defer { pending = nil }
        return pending
    }
}
