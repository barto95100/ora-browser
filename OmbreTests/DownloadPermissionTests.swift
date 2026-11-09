import Foundation
@testable import Ombre
import Testing

/// Downloads asked like Safari's "Allow downloads on…" (MOT-04 c).
@MainActor
struct DownloadPermissionTests {
    private final class FakeDownload: PermissionGatedDownload {
        var isRequestedByUser = false
        var onDestinationRequest: ((URLResponse, String, @escaping @MainActor @Sendable (URL?) -> Void) -> Void)?
        var isCancelled = false
        func cancel() {
            isCancelled = true
        }
    }

    /// The outcome of one check.
    private final class Run {
        var started = false
        var done = false
        var request: SitePermissionRequest?
    }

    private let space = UUID()
    private let site = URL(string: "https://files.example/page")

    private func check(_ download: FakeDownload, site: URL? = nil, useDefaultSite: Bool = true) -> Run {
        let run = Run()
        DownloadPermission.check(
            download,
            site: useDefaultSite ? self.site : site,
            spaceID: space,
            isPrivate: false,
            present: { run.request = $0 },
            start: { run.started = true },
            done: { run.done = true }
        )
        return run
    }

    private func save(_ state: SitePermissionState) throws {
        let origin = try #require(site.flatMap(SiteOrigin.init(url:)))
        SitePermissionStore.shared.setState(state, for: [.downloads], origin: origin, in: space, isPrivate: false)
    }

    @Test func allowedSiteDownloadsAtOnce() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        try save(.allow)
        let download = FakeDownload()
        let run = check(download)
        #expect(run.started && run.done && run.request == nil && !download.isCancelled)
    }

    @Test func refusedSiteIsCancelled() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        try save(.deny)
        let download = FakeDownload()
        let run = check(download)
        #expect(!run.started && run.done && run.request == nil && download.isCancelled)
    }

    /// The first time, the user is asked; the download waits, and WebKit's
    /// question of where to save it gets its answer once allowed.
    @Test func undecidedSiteIsAskedAndTheDownloadWaits() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        let download = FakeDownload()
        let run = check(download)
        let request = try #require(run.request)
        #expect(request.types == [.downloads])
        #expect(!run.started && !run.done)

        var asked = false
        download.onDestinationRequest?(URLResponse(), "file.zip") { _ in asked = true }
        #expect(!asked)

        // Allowed and remembered, as the prompt does.
        SitePermissionGate.answer(request, granted: true, remember: true, spaceID: space, isPrivate: false)
        #expect(run.started && run.done)
        let origin = try #require(site.flatMap(SiteOrigin.init(url:)))
        #expect(SitePermissionStore.shared.permissions(for: origin, in: space, isPrivate: false).downloads == .allow)
    }

    @Test func heldQuestionGoesToTheManagerOnceAllowed() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        let download = FakeDownload()
        let destination = URL(fileURLWithPath: "/tmp/file.zip")
        var request: SitePermissionRequest?
        DownloadPermission.check(
            download,
            site: site,
            spaceID: space,
            isPrivate: false,
            present: { request = $0 },
            start: {
                // What `DownloadManager.handleDownload` does.
                download.onDestinationRequest = { _, _, completion in completion(destination) }
            }
        )
        var saved: URL?
        download.onDestinationRequest?(URLResponse(), "file.zip") { saved = $0 }

        try #require(request).resolve(granted: true)

        #expect(saved == destination)
    }

    /// Two files from the site while it is asked: one question, both wait.
    @Test func secondDownloadWaitsForTheSameQuestion() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        let first = FakeDownload()
        let second = FakeDownload()
        let firstRun = check(first)
        let secondRun = check(second)
        #expect(firstRun.request != nil)
        #expect(secondRun.request == nil)

        try #require(firstRun.request).resolve(granted: true)

        #expect(firstRun.started && secondRun.started && !first.isCancelled && !second.isCancelled)
    }

    @Test func refusalCancelsAndAnswersTheHeldQuestion() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        let download = FakeDownload()
        let run = check(download)
        var answered = false
        download.onDestinationRequest?(URLResponse(), "file.zip") { url in answered = url == nil }

        try #require(run.request).resolve(granted: false)

        #expect(answered && download.isCancelled && !run.started && run.done)
        // A later question from WebKit is no longer held.
        #expect(download.onDestinationRequest == nil)
    }

    /// "Download Linked File" from the menu, or a page with no site (a local
    /// file): nothing to ask, even for a refused site.
    @Test func menuDownloadsAndLocalPagesAreNotAsked() throws {
        defer { SitePermissionStore.shared.removeAll(in: space) }
        try save(.deny)
        let fromMenu = FakeDownload()
        fromMenu.isRequestedByUser = true
        #expect(check(fromMenu).started)

        let local = FakeDownload()
        let run = check(local, site: URL(fileURLWithPath: "/tmp/page.html"), useDefaultSite: false)
        #expect(run.started && run.request == nil)
    }

    @Test func savedChoicesWithoutDownloadsDecodeAsAsk() throws {
        let json = Data(#"{"camera":"allow"}"#.utf8)
        let permissions = try JSONDecoder().decode(SitePermissions.self, from: json)
        #expect(permissions.downloads == .ask)
        #expect(permissions.camera == .allow)
    }
}
