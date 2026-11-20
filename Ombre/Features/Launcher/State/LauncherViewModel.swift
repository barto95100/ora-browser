import SwiftUI

@MainActor
class LauncherViewModel: ObservableObject {
    /// Open tabs and history entries shown together, at most.
    static let maxSuggestions = 5

    let searchEngineService = SearchEngineService()

    @Published var suggestions: [LauncherSuggestion] = []
    @Published var focusedElement: UUID = .init()

    /// Kept in sync with the view's text binding so closures can read current input.
    var currentText: String = ""

    private let debouncer = Debouncer(delay: 0.2)
    private var autoSuggestionRequestID = 0

    // Dependencies injected from the view layer
    private(set) var tabManager: TabManager?
    private(set) var historyManager: HistoryManager?
    private(set) var downloadManager: DownloadManager?
    private(set) var appState: AppState?
    private(set) var privacyMode: PrivacyMode?
    private(set) var onSubmit: ((String?) -> Void)?
    private(set) var onDismiss: (() -> Void)?
    var navigateInCurrentTab: Bool = false
    /// The view's way to take an engine for the search (its capsule), with
    /// the keyword typed, set by the launcher and the address bar.
    var onChooseEngine: ((SearchEngine, String) -> Void)?
    /// An engine is already taken (its capsule shows): no engine is offered
    /// for what is typed, and Tab changes engine only on an exact keyword.
    var hasChosenEngine = false

    func configure(
        tabManager: TabManager,
        historyManager: HistoryManager,
        downloadManager: DownloadManager,
        appState: AppState,
        privacyMode: PrivacyMode,
        onSubmit: @escaping (String?) -> Void,
        onDismiss: (() -> Void)? = nil,
        navigateInCurrentTab: Bool = false
    ) {
        self.tabManager = tabManager
        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.appState = appState
        self.privacyMode = privacyMode
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        self.navigateInCurrentTab = navigateInCurrentTab
    }

    // MARK: - Search Logic

    func searchHandler(_ text: String) {
        guard let tabManager, let historyManager else { return }

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            invalidateAutoSuggestionRequests()
            suggestions = defaultSuggestions()
            focusedElement = suggestions.first?.id ?? UUID()
            return
        }

        let requestID = nextAutoSuggestionRequestID()

        let histories = historyManager.search(
            text,
            activeContainerId: tabManager.activeContainer?.id ?? UUID(),
            // The launcher shows at most this many suggestions in all.
            limit: Self.maxSuggestions
        )
        // Switching to the tab the user is already on is a no-op, so never
        // offer it (it used to swallow Enter in the URL bar).
        let activeTabId = tabManager.activeTab?.id
        let tabs = tabManager.search(text).filter { $0.id != activeTabId }

        suggestions = []
        // First, but not chosen: ↩ still does what it did; Tab takes it.
        appendKeywordSuggestions(text)

        var itemsCount = 0
        // A URL typed or pasted by the user is the most likely intent, so it
        // goes first and is what Enter opens (as in Safari or Chrome).
        if explicitURL(from: text) != nil {
            appendOpenURLSuggestionIfNeeded(text)
            appendOpenTabs(tabs, itemsCount: &itemsCount)
        } else {
            appendOpenTabs(tabs, itemsCount: &itemsCount)
            appendOpenURLSuggestionIfNeeded(text)
        }
        appendSearchWithDefaultEngineSuggestion(text)

        let insertIndex = suggestions.count
        requestAutoSuggestions(text, insertAt: insertIndex, requestID: requestID)

        appendHistorySuggestions(histories, itemsCount: &itemsCount)
        appendAISuggestionsIfNeeded(text)

        focusedElement = (suggestions.first { $0.type != .keywordEngine } ?? suggestions.first)?.id ?? UUID()
    }

    /// « Search on YouTube » when what is typed begins one of its keywords
    /// (two engines at most, the best first). Nothing is replaced until
    /// Tab, or ↩ on it: « you » may also begin a search.
    private func appendKeywordSuggestions(_ text: String) {
        guard !hasChosenEngine else { return }
        let typed = text.trimmingCharacters(in: .whitespaces)
        for match in searchEngineService.rules.keywordMatches(for: typed) {
            let engine = match.engine
            suggestions.append(LauncherSuggestion(
                type: .keywordEngine,
                title: engine.isAIChat
                    ? String(localized: "Ask \(engine.name)")
                    : String(localized: "Search on \(engine.name)"),
                name: engine.name,
                icon: engine.icon.isEmpty ? nil : engine.icon,
                color: engine.color,
                engineForegroundColor: engine.foregroundColor,
                dismisses: false,
                action: { [weak self] in self?.onChooseEngine?(engine, typed) }
            ))
        }
    }

    /// Tab: the keyword suggestion chosen, else the first one; else what is
    /// typed if it is a keyword. True when an engine was taken.
    @discardableResult
    func takeKeyword() -> Bool {
        let offered = hasChosenEngine ? [] : suggestions.filter { $0.type == .keywordEngine }
        if let chosen = offered.first(where: { $0.id == focusedElement }) ?? offered.first {
            chosen.action()
            return true
        }
        let typed = currentText.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, let engine = searchEngineService.findSearchEngine(for: typed) else { return false }
        onChooseEngine?(engine, typed)
        return true
    }

    func reset() {
        invalidateAutoSuggestionRequests()
        suggestions = []
        focusedElement = UUID()
        currentText = ""
    }

    func defaultSuggestions() -> [LauncherSuggestion] {
        guard let tabManager else { return [] }
        let containerId = tabManager.activeContainer?.id
        let searchEngine = searchEngineService.getDefaultSearchEngine(for: containerId)
        let engineName = searchEngine?.name ?? "Google" // no translation
        return [
            LauncherSuggestion(
                type: .suggestedQuery, title: String(localized: "Search on \(engineName)"),
                action: { [weak self] in self?.onSubmit?(nil) }
            )
        ] + startingAISuggestions()
    }

    /// The space's AI first, then the other AIs shown, a few at most.
    private func startingAISuggestions() -> [LauncherSuggestion] {
        let spaceAI = spaceAIEngine
        let others = searchEngineService.shownEngines.filter { $0.isAIChat && $0.name != spaceAI?.name }
        return ([spaceAI].compactMap(\.self) + others)
            .prefix(Self.maxStartingAIs)
            .map { createAISuggestion(engine: $0) }
    }

    static let maxStartingAIs = 4

    /// The AI of the active space (see `SearchEngineService.getDefaultAIChat`).
    var spaceAIEngine: SearchEngine? {
        searchEngineService.getDefaultAIChat(for: tabManager?.activeContainer?.id)
    }

    /// The space's AI asked when `event` is its shortcut (⌘↩ by default).
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(fromEvent: event),
              chord.isSameKeys(as: KeyboardShortcuts.Address.askAI.currentChord)
        else { return false }
        return askSpaceAI()
    }

    /// Sends what is typed to the space's AI (⌘↩ by default, see
    /// `KeyboardShortcuts.Address.askAI`). Nothing typed: nothing sent.
    @discardableResult
    func askSpaceAI() -> Bool {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        // The address bar opens with the page's address: not a question.
        let isPageAddress = navigateInCurrentTab && text == tabManager?.activeTab?.url.absoluteString
        guard !text.isEmpty, !isPageAddress, let engine = spaceAIEngine else { return false }
        open(engine, query: text)
        onDismiss?()
        return true
    }

    func executeCommand() {
        if let suggestion = suggestions.first(where: { $0.id == focusedElement }) {
            suggestion.action()
            if suggestion.dismisses { onDismiss?() }
        }
    }

    func moveFocusedElement(_ dir: MoveDirection) {
        guard let idx = suggestions.firstIndex(where: { $0.id == focusedElement }) else { return }
        let offset = dir == .up ? -1 : 1
        let newIndex = (idx + offset + suggestions.count) % suggestions.count
        focusedElement = suggestions[newIndex].id
    }

    // MARK: - Private Helpers

    private func createAISuggestion(engine: SearchEngine, query: String? = nil, isSpaceAI: Bool = false)
        -> LauncherSuggestion
    {
        LauncherSuggestion(
            type: .aiChat,
            title: query ?? engine.name,
            name: engine.name,
            icon: engine.icon.isEmpty ? nil : engine.icon,
            color: engine.color,
            engineForegroundColor: engine.foregroundColor,
            isSpaceAI: isSpaceAI,
            action: { [weak self] in
                guard let self else { return }
                self.open(engine, query: query ?? self.currentText)
            }
        )
    }

    /// `query` asked to an engine: in the tab whose address is edited, or
    /// in a new tab of the active space (with its cookies).
    private func open(_ engine: SearchEngine, query: String) {
        guard let tabManager, let historyManager, let privacyMode,
              let url = searchEngineService.createSearchURL(for: engine, query: query)
        else { return }
        if navigateInCurrentTab, let tab = tabManager.activeTab {
            tab.loadURL(url.absoluteString)
        } else {
            tabManager.openTab(url: url, historyManager: historyManager, isPrivate: privacyMode.isPrivate)
        }
    }

    private func appendOpenTabs(_ tabs: [Tab], itemsCount: inout Int) {
        guard let tabManager, let historyManager, let downloadManager, let privacyMode else {
            return
        }
        for tab in tabs {
            if itemsCount >= 2 { break }
            suggestions.append(
                LauncherSuggestion(
                    type: .openedTab,
                    title: tab.title,
                    url: tab.url,
                    faviconURL: tab.favicon,
                    faviconLocalFile: tab.faviconLocalFile,
                    action: {
                        if !tab.isWebViewReady {
                            tab.restoreTransientState(
                                historyManager: historyManager,
                                downloadManager: downloadManager,
                                tabManager: tabManager,
                                isPrivate: privacyMode.isPrivate
                            )
                        }
                        tabManager.activateTab(tab)
                    }
                )
            )
            itemsCount += 1
        }
    }

    /// The URL the user is explicitly entering, if the text is one
    /// (`https://example.com/page` or a bare `example.com`).
    private func explicitURL(from text: String) -> URL? {
        if let candidateURL = URL(string: text), candidateURL.scheme != nil, candidateURL.host != nil {
            return candidateURL
        }
        if isValidURL(text) {
            return constructURL(from: text)
        }
        return nil
    }

    private func appendOpenURLSuggestionIfNeeded(_ text: String) {
        guard let tabManager, let historyManager, let privacyMode else {
            return
        }
        guard let url = explicitURL(from: text) else { return }
        let navigateCurrent = self.navigateInCurrentTab
        suggestions.append(
            LauncherSuggestion(
                type: .suggestedLink,
                title: text,
                url: url,
                action: {
                    if navigateCurrent {
                        tabManager.activeTab?.loadURL(url.absoluteString)
                    } else {
                        // A local file: once Ombre may read it (asks the user).
                        LocalFileAccess.whenReadable(url) { url in
                            tabManager.openTab(
                                url: url,
                                historyManager: historyManager,
                                isPrivate: privacyMode.isPrivate
                            )
                        }
                    }
                }
            )
        )
    }

    private func appendSearchWithDefaultEngineSuggestion(_ text: String) {
        guard let tabManager else { return }
        let containerId = tabManager.activeContainer?.id
        let searchEngine = searchEngineService.getDefaultSearchEngine(for: containerId)
        let engineName = searchEngine?.name ?? "Google" // no translation
        suggestions.append(
            LauncherSuggestion(
                type: .suggestedQuery,
                title: "\(text) - \(engineName)",
                action: { [weak self] in self?.onSubmit?(nil) }
            )
        )
    }

    private func requestAutoSuggestions(_ text: String, insertAt: Int, requestID: Int) {
        guard let tabManager else { return }
        let containerId = tabManager.activeContainer?.id
        debouncer.run { [weak self] in
            guard let self else { return }
            let isCurrentRequest = await MainActor.run {
                requestID == self.autoSuggestionRequestID && self.currentText == text
            }
            guard isCurrentRequest else { return }

            let searchEngine = await self.searchEngineService.getDefaultSearchEngine(
                for: containerId
            )
            if let autoSuggestions = searchEngine?.autoSuggestions {
                let searchSuggestions = await autoSuggestions(text)
                await MainActor.run {
                    guard requestID == self.autoSuggestionRequestID, self.currentText == text else {
                        return
                    }

                    var localCount = 0
                    var existingTitles = Set(self.suggestions.map(\.title))
                    for searchSuggestion in searchSuggestions {
                        if localCount == 3 { break }
                        if existingTitles.contains(searchSuggestion) { continue }

                        let insertIndex = insertAt + localCount
                        let suggestion = LauncherSuggestion(
                            type: .suggestedQuery,
                            title: searchSuggestion,
                            action: { [weak self] in self?.onSubmit?(searchSuggestion) }
                        )
                        if insertIndex <= self.suggestions.count {
                            self.suggestions.insert(suggestion, at: insertIndex)
                        } else {
                            self.suggestions.append(suggestion)
                        }
                        existingTitles.insert(searchSuggestion)
                        localCount += 1
                    }
                }
            }
        }
    }

    private func nextAutoSuggestionRequestID() -> Int {
        autoSuggestionRequestID += 1
        debouncer.cancel()
        return autoSuggestionRequestID
    }

    private func invalidateAutoSuggestionRequests() {
        autoSuggestionRequestID += 1
        debouncer.cancel()
    }

    private func appendHistorySuggestions(_ histories: [History], itemsCount: inout Int) {
        guard let tabManager, let historyManager, let privacyMode else { return }
        let navigateCurrent = self.navigateInCurrentTab
        for history in histories {
            if itemsCount >= Self.maxSuggestions { break }
            suggestions.append(
                LauncherSuggestion(
                    type: .suggestedLink,
                    title: history.title,
                    url: history.url,
                    faviconURL: history.faviconURL,
                    faviconLocalFile: history.faviconLocalFile,
                    action: {
                        if navigateCurrent {
                            tabManager.activeTab?.loadURL(history.url.absoluteString)
                        } else {
                            // A local file: once Ombre may read it (asks the user).
                            LocalFileAccess.whenReadable(history.url) { url in
                                tabManager.openTab(
                                    url: url,
                                    historyManager: historyManager,
                                    isPrivate: privacyMode.isPrivate
                                )
                            }
                        }
                    }
                )
            )
            itemsCount += 1
        }
    }

    /// A question: « Ask <the space's AI> ».
    private func appendAISuggestionsIfNeeded(_ text: String) {
        guard Self.isAISuitableQuery(text), let engine = spaceAIEngine else { return }
        suggestions.append(createAISuggestion(engine: engine, query: text, isSpaceAI: true))
    }

    /// Text that reads like a question or a request to an AI, in English
    /// or French.
    nonisolated static func isAISuitableQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let words = lowercased.split(separator: " ")

        // Negative signals: single words and URLs are not AI queries
        if words.count <= 1 { return false }
        if isValidURL(trimmed) { return false }

        // Starts with a question word
        let questionPrefixes = [
            "who ", "what ", "where ", "when ", "how ", "why ", "which ", // no translation
            "is ", "are ", "can ", "does ", "do ", "should ", "would ", // no translation
            "could ", "will ", "was ", "were ", "has ", "have ", // no translation
            "comment ", "pourquoi ", "quand ", "où ", "qui ", "quel ", "quelle ", // no translation
            "quels ", "quelles ", "combien ", "est-ce ", "peux-tu ", "pouvez-vous ", // no translation
            "que ", "qu'", "qu’" // no translation
        ]
        if questionPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }

        // Ends with a question mark
        if trimmed.hasSuffix("?") {
            return true
        }

        // Imperative / command phrases
        let imperativePhrases = [
            "write me", "help me", "create a", "give me", "list of", // no translation
            "make a", "tell me", "show me", "find me", "build a", // no translation
            "design a", "plan a", "write a", "make me", "help with", // no translation
            "écris", "rédige", "explique", "résume", "traduis", "aide-moi", // no translation
            "donne-moi", "dis-moi", "propose", "compare", "corrige", "reformule" // no translation
        ]
        if imperativePhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Action keywords
        let actionKeywords = [
            "summarize", "rewrite", "explain", "generate", "how to", // no translation
            "translate", "compare", "alternatives", "improve", "suggest",
            "recommend", "analyze", "convert", "calculate", "define",
            "describe", "simplify", "debug", "optimize", "refactor",
            "review", "draft", "code", "idea", "opinion", "story",
            "joke", "email"
        ]
        if actionKeywords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Natural language heuristic: 4+ words likely conversational
        if words.count >= 4 {
            return true
        }

        return false
    }
}

private class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func run(_ block: @escaping @Sendable () async -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem {
            Task { await block() }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
