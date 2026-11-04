import SwiftData
import SwiftUI

/// Carries out the assistant's plan in a browser window: it needs the
/// window's `TabManager` to create spaces and import tabs.
@MainActor
enum OnboardingApplier {
    static func apply(_ result: OnboardingResult, tabManager: TabManager) {
        let plan = result.plan
        if let appearance = plan.appearance {
            AppearanceManager.shared.appearance = appearance
        }
        if let sidebarPosition = plan.sidebarPosition {
            UserDefaults.standard.set(sidebarPosition.rawValue, forKey: SidebarPosition.defaultsKey)
        }
        // Before the new spaces: they take the chosen level.
        if let protection = plan.protection {
            PrivacyDefaults.newSpaceLevel = protection
        }

        // The space the assistant showed, or the one a new database was just given.
        let shown = result.firstSpaceID.flatMap { id in
            try? tabManager.modelContext.fetch(FetchDescriptor<TabContainer>(predicate: #Predicate { $0.id == id }))
                .first
        }
        let first = shown ?? tabManager.activeContainer ?? tabManager.createContainer()
        tabManager.updateSpace(first, look: plan.firstSpace)
        for look in plan.newSpaces {
            tabManager.addSpace(look: look)
        }
        if let zenSpaces = result.zenSpaces, !zenSpaces.spaces.isEmpty {
            tabManager.importSpaces(zenSpaces, from: "Zen")
        }

        // The chosen level for every space, those that were there included.
        if let protection = plan.protection {
            let ids = (try? tabManager.modelContext.fetch(FetchDescriptor<TabContainer>()))?.map(\.id) ?? []
            PrivacyDefaults.apply(protection, to: ids)
        }
    }
}
