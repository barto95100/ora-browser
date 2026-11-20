import Foundation
@testable import Ombre
import Testing

/// What is typed begins an engine's keyword: « Search on YouTube » comes
/// first, without being chosen; Tab (or ↩ on it) takes the engine.
@MainActor
struct KeywordSuggestionTests {
    private func launcher(_ window: TabManagerTestWindow) -> (LauncherViewModel, Box) {
        let model = LauncherViewModel()
        let chosen = Box()
        model.configure(
            tabManager: window.tabManager,
            historyManager: window.historyManager,
            downloadManager: window.downloadManager,
            appState: AppState(),
            privacyMode: PrivacyMode(isPrivate: false),
            onSubmit: { _ in },
            onDismiss: { chosen.dismissed += 1 }
        )
        model.onChooseEngine = { engine, typed in chosen.engines.append((engine.name, typed)) }
        return (model, chosen)
    }

    @MainActor
    final class Box {
        var engines: [(String, String)] = []
        var dismissed = 0
    }

    private func type(_ text: String, in model: LauncherViewModel) {
        model.currentText = text
        model.searchHandler(text)
    }

    @Test func theStartOfAKeywordIsOfferedFirstButNotChosen() async throws {
        try await TabManagerTestWindow.run { window in
            let (model, chosen) = launcher(window)
            type("youtu", in: model)
            let first = try #require(model.suggestions.first)
            #expect(first.type == .keywordEngine)
            #expect(first.name == "YouTube")
            #expect(first.title == String(localized: "Search on \("YouTube")"))
            // ↩ still does what it did: the suggestion chosen is another one.
            #expect(model.focusedElement != first.id)
            #expect(chosen.engines.isEmpty)
        }
    }

    @Test func tabTakesTheEngineOffered() async throws {
        try await TabManagerTestWindow.run { window in
            let (model, chosen) = launcher(window)
            type("youtu", in: model)
            #expect(model.takeKeyword())
            #expect(chosen.engines.map(\.0) == ["YouTube"])
            #expect(chosen.engines.map(\.1) == ["youtu"])
        }
    }

    /// ↩ on it takes the engine and keeps the launcher open.
    @Test func returnOnItTakesTheEngineWithoutClosing() async throws {
        try await TabManagerTestWindow.run { window in
            let (model, chosen) = launcher(window)
            type("yt", in: model)
            let first = try #require(model.suggestions.first)
            model.focusedElement = first.id
            model.executeCommand()
            #expect(chosen.engines.map(\.0) == ["YouTube"])
            #expect(chosen.dismissed == 0)
        }
    }

    @Test func nothingIsOfferedForAnOrdinarySearch() async throws {
        try await TabManagerTestWindow.run { window in
            let (model, chosen) = launcher(window)
            type("météo lyon", in: model)
            #expect(!model.suggestions.contains { $0.type == .keywordEngine })
            #expect(!model.takeKeyword())
            #expect(chosen.engines.isEmpty)
        }
    }

    /// Two engines at most.
    @Test func twoEnginesAtMost() async throws {
        try await TabManagerTestWindow.run { window in
            let (model, _) = launcher(window)
            type("g", in: model)
            #expect(model.suggestions.filter { $0.type == .keywordEngine }.count <= 2)
        }
    }
}
