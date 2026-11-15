import AppKit
@testable import Ombre
import SwiftUI
import Testing

private struct ProbeKey: EnvironmentKey {
    static let defaultValue = "none"
}

private extension EnvironmentValues {
    var pagerProbe: String {
        get { self[ProbeKey.self] }
        set { self[ProbeKey.self] = newValue }
    }
}

/// What each page saw of its environment, by page.
@MainActor
private final class EnvironmentLog: ObservableObject {
    var seen: [String: Set<String>] = [:]
}

@MainActor
private final class Pages: ObservableObject {
    @Published var ids = ["a"]
    @Published var index = 0
}

private struct ProbePage: View {
    let id: String
    let log: EnvironmentLog
    @Environment(\.pagerProbe) private var probe

    var body: some View {
        log.seen[id, default: []].insert(probe)
        return Color.clear
    }
}

private struct Pager: View {
    @ObservedObject var pages: Pages
    let log: EnvironmentLog
    let injects: Bool
    @Environment(\.pagerProbe) private var probe

    var body: some View {
        SpacePager(pages: pages.ids, selection: pages.index, id: \.self) { id in
            if injects {
                ProbePage(id: id, log: log).environment(\.pagerProbe, probe)
            } else {
                ProbePage(id: id, log: log)
            }
        }
    }
}

/// The spaces' pages in the sidebar (`SpacePager`): a page made while the app
/// runs (a new space) sees the window's environment. With AppKit's page
/// controller, it was first laid out apart, with none of it, and crashed.
@MainActor
struct PagerEnvironmentTests {
    /// A new page, shown as the sidebar's "+" does (added and selected at
    /// once) or as Settings › Spaces does (added, then picked), with or
    /// without animation.
    private func showNewPage(injects: Bool, together: Bool, animated: Bool) async throws -> EnvironmentLog {
        let pages = Pages()
        let log = EnvironmentLog()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: Pager(pages: pages, log: log, injects: injects).environment(\.pagerProbe, "window")
        )
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let change = {
            if together {
                pages.ids.append("b")
                pages.index = 1
            } else {
                pages.index = 1
            }
        }
        if !together {
            pages.ids.append("b")
            try await Task.sleep(for: .milliseconds(100))
        }
        if animated { withAnimation { change() } } else { change() }
        for _ in 0 ..< 40 where log.seen["b"] == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        // The transition's end.
        try await Task.sleep(for: .milliseconds(500))
        return log
    }

    /// Nothing needs to be given: the pages are in the window's views.
    @Test func aNewPageShownAtOnceHasTheWindowsEnvironment() async throws {
        let log = try await showNewPage(injects: false, together: true, animated: true)
        #expect(log.seen["b"] == ["window"])
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func whatIsGivenReachesANewPage(together: Bool, animated: Bool) async throws {
        let log = try await showNewPage(injects: true, together: together, animated: animated)
        #expect(log.seen["a"] == ["window"])
        #expect(log.seen["b"] == ["window"])
    }
}

extension TabManagerTests {
    /// A space's page, hosted alone with only what the sidebar gives it
    /// (`SpacePageEnvironment`): a view of it reading anything else from the
    /// environment crashes this test.
    @MainActor
    struct SpacePageEnvironmentTests {
        @Test(arguments: [false, true])
        func aSpacesPageNeedsNothingElse(toolbarHidden: Bool) async throws {
            try await TabManagerTestWindow.run { managers in
                let space = try managers.activeSpace
                managers.addUnloadedTab("/fav", type: .fav, order: 0, in: space)
                managers.addUnloadedTab("/pinned", type: .pinned, order: 0, in: space)
                managers.addUnloadedTab("/normal", order: 0, in: space)
                let toolbarManager = ToolbarManager()
                let wasHidden = toolbarManager.isToolbarHidden
                // The address shown in the sidebar too.
                toolbarManager.isToolbarHidden = toolbarHidden
                defer { toolbarManager.isToolbarHidden = wasHidden }
                let environment = SpacePageEnvironment(
                    appState: AppState(),
                    downloadManager: managers.downloadManager,
                    historyManager: managers.historyManager,
                    privacyMode: PrivacyMode(isPrivate: false),
                    sidebarManager: SidebarManager(),
                    tabManager: managers.tabManager,
                    toastManager: ToastManager.shared,
                    toolbarManager: toolbarManager,
                    modelContext: managers.modelContext
                )
                let host = NSHostingView(rootView: ContainerView(container: space).modifier(environment))
                host.frame = NSRect(x: 0, y: 0, width: 260, height: 700)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 0)
            }
        }
    }
}
