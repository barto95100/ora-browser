import Foundation
@testable import Ora
import SwiftData
import Testing

@MainActor
struct DownloadProgressTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Download.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    private func makeManager() -> DownloadManager {
        DownloadManager(modelContainer: container, modelContext: context)
    }

    private func insertDownloading(size: Int64 = 1000) throws -> Download {
        let download = try Download(
            originalURL: #require(URL(string: "https://example.com/a.zip")),
            fileName: "a.zip",
            fileSize: size
        )
        download.status = .downloading
        context.insert(download)
        try context.save()
        return download
    }

    // MARK: Save rule

    @Test func progressUpdatesDoNotTouchTheDatabase() throws {
        let manager = makeManager()
        let download = try insertDownloading()

        manager.updateDownloadProgress(download, downloadedBytes: 250, totalBytes: 1000)

        #expect(!context.hasChanges)
        #expect(download.displayDownloadedBytes == 250)
        #expect(download.displayProgress == 0.25)
        #expect(download.downloadedBytes == 0)
    }

    @Test func unchangedProgressReportsNoChange() throws {
        let download = try insertDownloading()

        #expect(download.updateDisplayProgress(downloadedBytes: 10, totalBytes: 1000))
        #expect(!download.updateDisplayProgress(downloadedBytes: 10, totalBytes: 1000))
    }

    @Test func unknownSizeStillShowsBytes() throws {
        let download = try insertDownloading(size: -1)

        download.updateDisplayProgress(downloadedBytes: 500, totalBytes: -1)

        #expect(download.displayDownloadedBytes == 500)
        #expect(download.displayProgress == 0)
    }

    @Test func failureSavesTheLastProgress() throws {
        let manager = makeManager()
        let download = try insertDownloading()
        manager.updateDownloadProgress(download, downloadedBytes: 400, totalBytes: 1000)

        manager.failDownload(download, error: "Network")

        #expect(!context.hasChanges)
        #expect(download.status == .failed)
        #expect(download.downloadedBytes == 400)
        #expect(download.progress == 0.4)
    }

    @Test func cancelSavesTheLastProgress() throws {
        let manager = makeManager()
        let download = try insertDownloading()
        manager.updateDownloadProgress(download, downloadedBytes: 100, totalBytes: 1000)

        manager.cancelDownload(download)

        #expect(!context.hasChanges)
        #expect(download.status == .cancelled)
        #expect(download.downloadedBytes == 100)
    }

    @Test func completionSavesTheFinalSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ora-dl-\(UUID().uuidString).bin")
        try Data(count: 1234).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = makeManager()
        let download = try insertDownloading(size: -1)

        manager.completeDownload(download, destinationURL: url)

        #expect(!context.hasChanges)
        #expect(download.status == .completed)
        #expect(download.fileSize == 1234)
        #expect(download.downloadedBytes == 1234)
        #expect(download.displayProgress == 1)
    }

    // MARK: Interrupted downloads

    @Test func downloadsLeftRunningAreMarkedInterruptedAtLaunch() throws {
        let stale = try insertDownloading()
        let done = try Download(originalURL: #require(URL(string: "https://example.com/b.zip")), fileName: "b.zip")
        done.status = .completed
        done.completedAt = Date()
        context.insert(done)
        try context.save()

        let manager = makeManager()

        #expect(stale.status == .failed)
        #expect(stale.error == Download.interruptedError)
        #expect(done.status == .completed)
        #expect(manager.activeDownloads.isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func recentDownloadsAreLimited() throws {
        for index in 0 ..< DownloadManager.recentLimit + 5 {
            let url = try #require(URL(string: "https://example.com/\(index)"))
            let download = Download(originalURL: url, fileName: "\(index)")
            download.status = .completed
            download.completedAt = Date()
            context.insert(download)
        }
        try context.save()

        #expect(makeManager().recentDownloads.count == DownloadManager.recentLimit)
    }

    // MARK: Stored URL

    @Test func dataURLsKeepOnlyTheirMediaType() throws {
        let payload = String(repeating: "A", count: 10000)
        let url = try #require(URL(string: "data:image/png;base64,\(payload)"))

        #expect(Download.storableURL(for: url).absoluteString == "data:image/png")
        let download = Download(originalURL: url, fileName: "image.png")
        #expect(download.originalURLString == "data:image/png")
        #expect(!download.canRetry)
    }

    @Test func dataURLsWithoutMediaTypeKeepTheScheme() throws {
        let url = try #require(URL(string: "data:,Hello%20world"))

        #expect(Download.storableURL(for: url).absoluteString == "data:")
    }

    @Test func blobURLsKeepOnlyTheirOrigin() throws {
        let url = try #require(URL(string: "blob:https://example.com:8443/550e8400-e29b-41d4-a716-446655440000"))

        #expect(Download.storableURL(for: url).absoluteString == "blob:https://example.com:8443")
    }

    @Test func webURLsAreKeptAsIs() throws {
        let url = try #require(URL(string: "https://example.com/file.zip?token=1"))

        #expect(Download.storableURL(for: url) == url)
        #expect(Download(originalURL: url, fileName: "file.zip").canRetry)
    }

    // MARK: Throttle

    @Test func burstsOfNotificationsGiveOneUpdate() {
        var pending: [@MainActor () -> Void] = []
        var updates = 0
        let throttle = DownloadProgressThrottle(schedule: { pending.append($0) }, action: { updates += 1 })

        for _ in 0 ..< 100 {
            throttle.signal()
        }
        #expect(pending.count == 1)

        pending.removeFirst()()
        #expect(updates == 1)

        throttle.signal()
        #expect(pending.count == 1)
    }
}
