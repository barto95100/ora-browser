import Foundation

/// The screens of the first-launch assistant, in order.
enum OnboardingStep: CaseIterable, Hashable {
    case welcome
    case importZen
    case spaces
    case protection
    case defaultBrowser
    case ready
}

/// Which screens are shown and which one is on screen. A screen that has
/// nothing to offer is left out: the import when Zen has no profile, the
/// default browser when Ombre already is.
struct OnboardingFlow: Equatable {
    let steps: [OnboardingStep]
    private(set) var index = 0

    init(zenAvailable: Bool, isDefaultBrowser: Bool) {
        steps = OnboardingStep.allCases.filter { step in
            switch step {
            case .importZen: zenAvailable
            case .defaultBrowser: !isDefaultBrowser
            default: true
            }
        }
    }

    var current: OnboardingStep {
        steps[index]
    }

    var canGoBack: Bool {
        index > 0
    }

    var isLast: Bool {
        index == steps.count - 1
    }

    mutating func next() {
        if !isLast { index += 1 }
    }

    mutating func back() {
        if canGoBack { index -= 1 }
    }
}

/// A ready-made space offered by the assistant.
enum SpaceTemplate: String, CaseIterable, Identifiable {
    case personal
    case work

    var id: String {
        rawValue
    }

    var look: SpaceLook {
        switch self {
        case .personal: SpaceLook(name: "Personal", iconSymbol: "house", color: .green)
        case .work: SpaceLook(name: "Work", iconSymbol: "briefcase", color: .blue)
        }
    }

    /// A template can be added when no other space has its name.
    static func isAvailable(_ template: SpaceTemplate, takenNames: [String]) -> Bool {
        !takenNames.contains { $0.trimmed.caseInsensitiveCompare(template.look.name) == .orderedSame }
    }
}

/// What the person chose. A screen counts only once confirmed (Continue);
/// Skip puts the screen back as it was, so skipping or closing the window
/// changes nothing that the person did not confirm.
struct OnboardingChoices: Equatable {
    /// The spaces of the Zen preview to import, by position.
    var importedSpaces: Set<Int> = []
    var sidebarPosition: SidebarPosition = .primary
    var appearance: AppAppearance = .system
    /// The space that opens first: the most recent one, or the one a new
    /// database starts with.
    var firstSpace: SpaceLook
    var templates: Set<SpaceTemplate> = []
    var protection: ProtectionLevel = .standard
    private(set) var confirmed: Set<OnboardingStep> = []

    init(firstSpace: SpaceLook, sidebarPosition: SidebarPosition = .primary, appearance: AppAppearance = .system) {
        self.firstSpace = firstSpace
        self.sidebarPosition = sidebarPosition
        self.appearance = appearance
    }

    mutating func confirm(_ step: OnboardingStep) {
        confirmed.insert(step)
    }

    /// The screen goes back to what `initial` has for it.
    mutating func skip(_ step: OnboardingStep, initial: OnboardingChoices) {
        confirmed.remove(step)
        switch step {
        case .importZen:
            importedSpaces = initial.importedSpaces
        case .spaces:
            sidebarPosition = initial.sidebarPosition
            appearance = initial.appearance
            firstSpace = initial.firstSpace
            templates = initial.templates
        case .protection:
            protection = initial.protection
        case .welcome, .defaultBrowser, .ready:
            break
        }
    }
}

/// What finishing the assistant does, worked out from the choices.
struct OnboardingPlan: Equatable {
    /// Positions in the Zen preview, in order.
    var importedSpaces: [Int] = []
    /// Applied to the space that opens first.
    var firstSpace: SpaceLook
    var newSpaces: [SpaceLook] = []
    /// Nil: left as they are.
    var sidebarPosition: SidebarPosition?
    var appearance: AppAppearance?
    /// Nil: the spaces keep their protections, new ones get the current level.
    var protection: ProtectionLevel?

    /// `otherSpaceNames`: the spaces other than the first one.
    static func make(_ choices: OnboardingChoices, initial: OnboardingChoices, otherSpaceNames: [String]) -> Self {
        let confirmed = choices.confirmed
        let spaces = confirmed.contains(.spaces)
        var firstSpace = spaces ? choices.firstSpace : initial.firstSpace
        let name = firstSpace.trimmedName
        firstSpace.name = name.isEmpty ? initial.firstSpace.trimmedName : name

        var taken = otherSpaceNames + [firstSpace.name]
        var newSpaces: [SpaceLook] = []
        if spaces {
            for template in SpaceTemplate.allCases where choices.templates.contains(template) {
                guard SpaceTemplate.isAvailable(template, takenNames: taken) else { continue }
                newSpaces.append(template.look)
                taken.append(template.look.name)
            }
        }

        return OnboardingPlan(
            importedSpaces: confirmed.contains(.importZen) ? choices.importedSpaces.sorted() : [],
            firstSpace: firstSpace,
            newSpaces: newSpaces,
            sidebarPosition: spaces ? choices.sidebarPosition : nil,
            appearance: spaces ? choices.appearance : nil,
            protection: confirmed.contains(.protection) ? choices.protection : nil
        )
    }
}

/// Whether the assistant was done, in the app's defaults. A new version
/// number would show it again after a large change.
enum OnboardingStatus {
    static let key = "onboarding.completedVersion"
    static let currentVersion = 1

    static func isNeeded(in defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key) < currentVersion
    }

    static func markDone(in defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: key)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
