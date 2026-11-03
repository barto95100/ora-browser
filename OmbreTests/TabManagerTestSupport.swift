import Foundation
@testable import Ombre
import SwiftData
import Testing

/// Characterization tests of `TabManager`: they pin down what it does today,
/// before it is refactored. A test marked "BUG:" documents a wrong behavior
/// as it is; fixing it will change that test on purpose.
///
/// One parent suite, serialized: the suites share `UserDefaults` (creating a
/// space writes its privacy settings there), so they must not interleave.
@MainActor
@Suite(.serialized)
enum TabManagerTests {}

/// A window's managers on an in-memory database, like a private window.
///
/// Tabs that load a page are private (nothing kept on disk) and point at a
/// local port that refuses connections (no network traffic), so their load
/// fails and they keep their address. Not a port WebKit blocks (such as 9):
/// it loads `about:blank` instead, which then becomes the tab's address, at a
/// moment tests can't predict. Pages are real: opening, activating, closing
/// the active tab, ⌘Z and duplicating all create one in the current code.
@MainActor
final class TabManagerTestWindow {
    static let offeredKey = "privacy.recommendedProtections.offered"

    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let mediaController: MediaController
    let downloadManager: DownloadManager
    let historyManager: HistoryManager
    let tabManager: TabManager
    /// Spaces whose settings to remove at the end, deleted ones included.
    private var spaceIDs: Set<UUID> = []
    private let savedOfferedValue: Any?

    init() {
        savedOfferedValue = UserDefaults.standard.object(forKey: Self.offeredKey)
        modelContainer = DatabaseRecovery.inMemoryContainer()
        modelContext = ModelContext(modelContainer)
        mediaController = MediaController()
        downloadManager = DownloadManager(modelContainer: modelContainer, modelContext: modelContext)
        historyManager = HistoryManager(modelContainer: modelContainer, modelContext: modelContext)
        tabManager = TabManager(
            modelContainer: modelContainer,
            modelContext: modelContext,
            mediaController: mediaController,
            downloadManager: downloadManager,
            historyManager: historyManager
        )
    }

    /// Runs `body` with a new window, then tears its pages and settings down.
    static func run(_ body: (TabManagerTestWindow) async throws -> Void) async throws {
        let window = TabManagerTestWindow()
        do {
            try await body(window)
        } catch {
            await window.tearDown()
            throw error
        }
        await window.tearDown()
    }

    // MARK: - Spaces

    var activeSpace: TabContainer {
        get throws { try #require(tabManager.activeContainer) }
    }

    @discardableResult
    func createSpace(_ name: String) -> TabContainer {
        let space = tabManager.createContainer(name: name)
        spaceIDs.insert(space.id)
        return space
    }

    func remember(_ space: TabContainer) {
        spaceIDs.insert(space.id)
    }

    func spaces() -> [TabContainer] {
        (try? modelContext.fetch(FetchDescriptor<TabContainer>())) ?? []
    }

    // MARK: - Tabs

    /// Expected to be closed on the machines running the tests (checked by
    /// `FailedLoad`).
    static let refusingPort = 59999

    static func url(_ path: String) -> URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "http://127.0.0.1:\(refusingPort)/\(path)")!
    }

    /// Opens a tab like the launcher does, in the active space.
    @discardableResult
    func open(_ path: String, focus: Bool = true) throws -> Tab {
        try #require(tabManager.openTab(
            url: Self.url(path),
            historyManager: historyManager,
            focusAfterOpening: focus,
            isPrivate: true
        ))
    }

    /// Opens a tab and waits for its page to be ready (`isWebViewReady`).
    @discardableResult
    func openLoaded(_ path: String) async throws -> Tab {
        let tab = try open(path)
        await waitUntil("page of \(path) ready") { tab.isWebViewReady }
        return tab
    }

    /// A tab restored from the database and never loaded since: no page.
    @discardableResult
    func addUnloadedTab(
        _ path: String,
        type: TabType = .normal,
        order: Int,
        in space: TabContainer,
        lastAccessedAt: Date? = Date()
    ) -> Tab {
        let url = Self.url(path)
        let tab = Tab(
            url: url,
            title: path,
            container: space,
            type: type,
            order: order,
            tabManager: tabManager,
            isPrivate: true
        )
        if type != .normal {
            tab.savedURL = url
        }
        tab.lastAccessedAt = lastAccessedAt
        modelContext.insert(tab)
        space.tabs.append(tab)
        try? modelContext.save()
        return tab
    }

    func tabs(withID id: UUID) -> [Tab] {
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func isDeleted(_ tab: Tab) -> Bool {
        tabs(withID: tab.id).allSatisfy { $0 !== tab }
    }

    /// Closes a tab and waits for the end of its asynchronous closing (media
    /// stopped, then the tab deleted or its page destroyed).
    func close(_ tab: Tab) async {
        tabManager.closeTab(tab: tab)
        await waitUntilClosed(tab)
    }

    func waitUntilClosed(_ tab: Tab) async {
        if tab.type == .normal {
            await waitUntil("tab deleted") { self.isDeleted(tab) }
        } else {
            await waitUntil("page destroyed") { tab.browserPage == nil && !tab.isWebViewReady }
        }
    }

    /// Section of a space in sidebar order (highest order first).
    func section(_ type: TabType, of space: TabContainer) -> [UUID] {
        space.tabs.filter { $0.type == type }.sorted { $0.order > $1.order }.map(\.id)
    }

    // MARK: - Waiting

    /// Lets the main queue run until `condition` holds (5 s at most).
    func waitUntil(
        _ what: String,
        timeout: Duration = .seconds(5),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for: \(what)", sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Teardown

    private func tearDown() async {
        let allTabs = (try? modelContext.fetch(FetchDescriptor<Tab>())) ?? []
        let loading = allTabs.filter { $0.browserPage != nil }
        // Let pending loads (10 ms after a page is created) run first, so none
        // runs on a page already torn down.
        await waitUntil("pending loads", timeout: .seconds(2)) { loading.allSatisfy(\.isWebViewReady) }
        for tab in loading {
            tab.destroyWebView()
        }
        for space in spaces() {
            spaceIDs.insert(space.id)
        }
        for id in spaceIDs {
            SettingsStore.shared.removeContainerSettings(for: id)
        }
        if let savedOfferedValue {
            UserDefaults.standard.set(savedOfferedValue, forKey: Self.offeredKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.offeredKey)
        }
    }
}
