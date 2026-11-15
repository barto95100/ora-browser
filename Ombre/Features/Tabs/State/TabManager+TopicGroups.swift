import SwiftUI

/// How the subject grouping of a Tidy Tabs Now went.
enum SubjectOutcome: Equatable {
    /// Not asked: no model on this Mac, or too few tabs left.
    case notAsked
    case made(Int)
    case failed(String)
}

/// What Tidy Tabs Now says once it is done, in every case.
@MainActor
enum TidyMessage {
    /// The text shown, and whether it tells a failure.
    static func text(bySite: Int, bySubject: SubjectOutcome) -> (text: String, isFailure: Bool) {
        let bySubjectCount = if case let .made(count) = bySubject { count } else { 0 }
        let total = bySite + bySubjectCount
        if case let .failed(reason) = bySubject {
            if bySite > 0 {
                return (String(localized: "Groups by site: \(bySite); couldn’t group by subject: \(reason)"), true)
            }
            return (String(localized: "Couldn’t group the tabs by subject: \(reason)"), true)
        }
        guard total > 0 else { return (String(localized: "No groups to make"), false) }
        return (String(localized: "\(total) groups made"), false)
    }

    static func show(bySite: Int, bySubject: SubjectOutcome) {
        let message = text(bySite: bySite, bySubject: bySubject)
        if message.isFailure {
            ToastManager.shared.show(message.text, type: .error, duration: 8)
        } else {
            ToastManager.shared.show(message.text, type: .info, icon: .system("rectangle.stack"))
        }
    }
}

/// Ends a subject grouping once: by the model's answer or by its deadline.
@MainActor
private final class TidyRun {
    private(set) var isDone = false

    func claim() -> Bool {
        guard !isDone else { return false }
        isDone = true
        return true
    }
}

extension TabManager {
    /// Who groups tabs by subject: Apple's model on the Mac when it can be
    /// used; none under the tests (they set their own: the model's answers
    /// differ from one run to the next).
    static var topicGrouper: @MainActor () -> (any TopicGrouper)? = {
        TestHost.isActive ? nil : TopicGrouping.onDeviceGrouper
    }

    /// The space's tabs in no group, given to the subject grouping (their
    /// titles and sites only, each with its id); groups made from what it
    /// suggests, if those tabs are still free once it answers. "Tidying
    /// tabs…" is shown meanwhile, then what was done.
    func groupBySubject(in container: TabContainer, bySite: Int) -> Task<Void, Never>? {
        guard let grouper = Self.topicGrouper() else { return nil }
        let grouped = Set(tabGroups(in: container).flatMap(\.tabIDs))
        // The first ones only: the model reads a few thousand words at most.
        let tabs = Array(groupableTabs(in: container).filter { !grouped.contains($0.id) }.prefix(TopicGrouping.maxTabs))
        guard tabs.count >= TopicGrouping.threshold else { return nil }
        let input = TopicGrouping.topicTabs(tabs.map { (title: $0.title, url: $0.url) })
        let tabIDs = Dictionary(uniqueKeysWithValues: zip(input.map(\.id), tabs.map(\.id)))
        // The app's language (the group names sit among its texts).
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let spaceID = container.id
        // Titles in a log: never a private window's.
        let logs = !isPrivateWindow
        if logs { PageLog.debug("tabs by subject: request\n\(TopicGrouping.request(input))") }

        tidyingSpaceIDs.insert(spaceID)
        let progress = ToastManager.shared.show(
            String(localized: "Tidying tabs…"),
            type: .info,
            icon: .view(AnyView(ProgressView().controlSize(.small))),
            duration: 3600
        )
        let run = TidyRun()
        var deadline: Task<Void, Never>?
        // `outcome` nil: the window closed meanwhile, nothing to say.
        let finish: @MainActor (SubjectOutcome?) -> Void = { [weak self] outcome in
            guard run.claim() else { return }
            deadline?.cancel()
            ToastManager.shared.dismiss(id: progress)
            self?.tidyingSpaceIDs.remove(spaceID)
            if let outcome { TidyMessage.show(bySite: bySite, bySubject: outcome) }
        }
        let work = Task { @MainActor [weak self] in
            let reply: TopicReply
            do {
                reply = try await grouper.suggestions(for: input, language: language)
            } catch {
                // Past the deadline: already said.
                guard !run.isDone else { return }
                PageLog.notice("tabs by subject: no answer (\(PageLog.describe(error)))")
                finish(.failed(error.localizedDescription))
                return
            }
            if logs { PageLog.debug("tabs by subject: reply \(reply.raw)") }
            guard !run.isDone else { return }
            guard let self else { return finish(nil) }
            finish(.made(applySubjects(reply.suggestions, tabs: input, tabIDs: tabIDs, spaceID: spaceID)))
        }
        deadline = Task { @MainActor in
            try? await Task.sleep(for: TopicGrouping.deadline)
            guard !Task.isCancelled, !run.isDone else { return }
            PageLog.notice("tabs by subject: no answer in time")
            work.cancel()
            finish(.failed(String(localized: "the model took too long")))
        }
        return work
    }

    /// Makes the groups the model suggests, from tabs still free; returns how
    /// many.
    private func applySubjects(
        _ suggestions: [TopicSuggestion],
        tabs: [TopicTab],
        tabIDs: [String: UUID],
        spaceID: UUID
    ) -> Int {
        guard let container = fetchContainer(id: spaceID) else { return 0 }
        let free = Set(groupableTabs(in: container).map(\.id))
            .subtracting(tabGroups(in: container).flatMap(\.tabIDs))
        // Checked among the tabs still free only: a group that lost some
        // tabs meanwhile follows the same rules.
        let freeTabs = tabs.filter { tabIDs[$0.id].map(free.contains) ?? false }
        var made = 0
        for suggestion in TopicGrouping.validated(suggestions, tabs: freeTabs) {
            let members = suggestion.tabIDs.compactMap { tabIDs[$0] }
            modelContext.insert(TabGroup(spaceID: spaceID, name: suggestion.name, kind: .topic, tabIDs: members))
            made += 1
        }
        PageLog.notice("tabs by subject: \(made) groups")
        guard made > 0 else { return 0 }
        modelContext.saveOrLog("group tabs by subject")
        tabGroupsDidChange()
        return made
    }
}
