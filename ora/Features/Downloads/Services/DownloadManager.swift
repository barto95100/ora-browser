import Foundation
import SwiftData
import SwiftUI

@MainActor
class DownloadManager: ObservableObject {
    /// Active downloads live in memory only: they are added when WebKit starts one
    /// and removed when it finishes, fails or is cancelled.
    @Published var activeDownloads: [Download] = []
    @Published var recentDownloads: [Download] = []
    @Published var isShowingDownloadsHistory = false

    static let recentLimit = 50

    let modelContainer: ModelContainer
    let modelContext: ModelContext
    private var activeDownloadTasks: [UUID: BrowserDownloadTask] = [:]
    private var transfers: [UUID: Transfer] = [:]
    private lazy var progressThrottle = DownloadProgressThrottle { [weak self] in
        self?.refreshDisplayedProgress()
    }

    weak var toastManager: ToastManager?

    /// What a running WebKit download needs, keyed by its task ID.
    private struct Transfer {
        let task: BrowserDownloadTask
        let download: Download
        let destinationURL: URL
        let expectedSize: Int64
        let observation: NSKeyValueObservation
    }

    init(
        modelContainer: ModelContainer,
        modelContext: ModelContext
    ) {
        self.modelContainer = modelContainer
        self.modelContext = modelContext
        markInterruptedDownloads()
        loadRecentDownloads()
    }

    /// Downloads left "downloading" by a previous session (quit, crash) have no
    /// WebKit task anymore: they become failed ("Interrupted").
    private func markInterruptedDownloads() {
        // Enum comparisons are unreliable in SwiftData predicates: narrow on
        // `completedAt` (never set while downloading), then filter the status.
        let descriptor = FetchDescriptor<Download>(predicate: #Predicate<Download> { $0.completedAt == nil })
        guard let unfinished = try? modelContext.fetch(descriptor) else { return }
        let stale = unfinished.filter { $0.status == .downloading || $0.status == .pending }
        guard !stale.isEmpty else { return }
        stale.forEach { $0.markInterrupted() }
        try? modelContext.save()
    }

    private func loadRecentDownloads() {
        var descriptor = FetchDescriptor<Download>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.recentLimit

        guard let downloads = try? modelContext.fetch(descriptor) else { return }
        repairUnknownFileSizes(in: downloads)
        recentDownloads = downloads
    }

    /// Downloads completed before sizes were read from disk kept "-1 byte".
    private func repairUnknownFileSizes(in downloads: [Download]) {
        let unknown = downloads.filter { $0.status == .completed && $0.fileSize <= 0 }
        guard !unknown.isEmpty else { return }
        unknown.forEach { $0.refreshFileSizeFromDisk() }
        try? modelContext.save()
    }

    func startDownload(
        from downloadTask: BrowserDownloadTask,
        originalURL: URL,
        suggestedFilename: String,
        expectedSize: Int64 = 0
    ) -> Download {
        let download = Download(
            originalURL: originalURL,
            fileName: suggestedFilename,
            fileSize: expectedSize
        )

        download.status = .downloading
        download.isActive = true

        modelContext.insert(download)
        try? modelContext.save()

        activeDownloadTasks[download.id] = downloadTask
        activeDownloads.append(download)
        refreshRecentDownloads()

        toastManager?.show("Downloading \(suggestedFilename)", type: .info, icon: .system("arrow.down.circle"))

        return download
    }

    /// Shows new progress without touching the database (see `Download.updateDisplayProgress`).
    func updateDownloadProgress(_ download: Download, downloadedBytes: Int64, totalBytes: Int64) {
        if download.updateDisplayProgress(downloadedBytes: downloadedBytes, totalBytes: totalBytes) {
            objectWillChange.send()
        }
    }

    func completeDownload(_ download: Download, destinationURL: URL) {
        download.markCompleted(destinationURL: destinationURL)

        try? modelContext.save()

        activeDownloadTasks.removeValue(forKey: download.id)
        activeDownloads.removeAll { $0.id == download.id }
        refreshRecentDownloads()

        toastManager?.show("Downloaded \(download.fileName)", icon: .system("checkmark.circle"))
    }

    func failDownload(_ download: Download, error: String) {
        download.markFailed(error: error)

        try? modelContext.save()

        activeDownloadTasks.removeValue(forKey: download.id)
        activeDownloads.removeAll { $0.id == download.id }
        refreshRecentDownloads()

        toastManager?.show("Download failed \(download.fileName)", type: .error)
    }

    func cancelDownload(_ download: Download) {
        let fileName = download.fileName
        if let downloadTask = activeDownloadTasks[download.id] {
            // Read the last bytes received before forgetting the task.
            refreshDisplayedProgress(of: downloadTask.id)
            cleanupTask(downloadTask.id)
            downloadTask.cancel()
        }

        download.markCancelled()

        try? modelContext.save()

        activeDownloadTasks.removeValue(forKey: download.id)
        activeDownloads.removeAll { $0.id == download.id }
        refreshRecentDownloads()

        toastManager?.show("Download cancelled \(fileName)", type: .info, icon: .system("xmark.circle"))
    }

    func handleDownload(_ task: BrowserDownloadTask) {
        task.onDestinationRequest = { [weak self] response, suggestedFilename, completion in
            guard let self else {
                completion(nil)
                return
            }

            let downloadsDir = self.getDownloadsDirectory()
            let destinationURL = downloadsDir.appendingPathComponent(suggestedFilename)
            let finalURL = self.createUniqueFilename(for: destinationURL)
            let expectedSize = response.expectedContentLength
            let download = self.startDownload(
                from: task,
                originalURL: task.originalURL,
                suggestedFilename: suggestedFilename,
                expectedSize: expectedSize
            )

            self.observeProgress(of: task, download: download, destinationURL: finalURL, expectedSize: expectedSize)
            completion(finalURL)
        }

        task.onRedirect = { [weak self] newURL in
            guard let self, let download = self.transfers[task.id]?.download else { return }
            // Saved with the next start/finish/failure, not on every redirect.
            let storedURL = Download.storableURL(for: newURL)
            download.originalURL = storedURL
            download.originalURLString = storedURL.absoluteString
        }

        task.onFinish = { [weak self] in
            guard let self, let transfer = self.transfers[task.id] else { return }
            self.cleanupTask(task.id)
            self.completeDownload(transfer.download, destinationURL: transfer.destinationURL)
        }

        task.onFail = { [weak self] error in
            guard let self, let transfer = self.transfers[task.id] else { return }
            self.refreshDisplayedProgress(of: task.id)
            self.cleanupTask(task.id)
            self.failDownload(transfer.download, error: error.localizedDescription)
        }
    }

    func clearCompletedDownloads() {
        let completedDownloads = recentDownloads.filter { $0.status == .completed }
        for download in completedDownloads {
            modelContext.delete(download)
        }

        try? modelContext.save()
        refreshRecentDownloads()
    }

    func clearNonActiveDownloads() {
        let nonActive = recentDownloads.filter {
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled
        }
        for download in nonActive {
            modelContext.delete(download)
        }

        try? modelContext.save()
        refreshRecentDownloads()
    }

    func deleteDownload(_ download: Download) {
        // If it's an active download, cancel it first
        if download.status == .downloading {
            cancelDownload(download)
        }

        modelContext.delete(download)
        try? modelContext.save()
        refreshRecentDownloads()
    }

    func openDownloadInFinder(_ download: Download) {
        guard let destinationURL = download.destinationURL else { return }
        NSWorkspace.shared.selectFile(destinationURL.path, inFileViewerRootedAtPath: "")
    }

    func openFile(_ download: Download) {
        guard let url = download.destinationURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Moves the downloaded file to Trash and removes the entry from history
    func moveToTrash(_ download: Download) {
        if let url = download.destinationURL {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        deleteDownload(download)
    }

    /// Re-opens the original URL in the browser to re-trigger the download
    func retryDownload(_ download: Download) {
        guard download.canRetry, let url = URL(string: download.originalURLString) else { return }
        deleteDownload(download)
        if let window = NSApp.keyWindow {
            NotificationCenter.default.post(name: .openURL, object: window, userInfo: ["url": url])
        }
    }

    private func refreshRecentDownloads() {
        loadRecentDownloads()
    }

    /// Helper to get default downloads directory
    func getDownloadsDirectory() -> URL {
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    /// Helper to create unique filename if file already exists
    func createUniqueFilename(for url: URL) -> URL {
        var finalURL = url
        var counter = 1

        while FileManager.default.fileExists(atPath: finalURL.path) {
            let filename = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let directory = url.deletingLastPathComponent()

            let newFilename = ext.isEmpty ? "\(filename) (\(counter))" : "\(filename) (\(counter)).\(ext)"
            finalURL = directory.appendingPathComponent(newFilename)
            counter += 1
        }

        return finalURL
    }

    /// Observes the byte count (not `fractionCompleted`, which stays at 0 when the
    /// server announces no size). The KVO callback only signals the throttle.
    private func observeProgress(
        of task: BrowserDownloadTask,
        download: Download,
        destinationURL: URL,
        expectedSize: Int64
    ) {
        let throttle = progressThrottle
        let observation = task.progress.observe(\.completedUnitCount) { _, _ in
            throttle.signal()
        }
        transfers[task.id] = Transfer(
            task: task,
            download: download,
            destinationURL: destinationURL,
            expectedSize: expectedSize,
            observation: observation
        )
    }

    /// One UI refresh for all running downloads, at most ~4 times per second.
    private func refreshDisplayedProgress() {
        transfers.keys.forEach(refreshDisplayedProgress(of:))
    }

    private func refreshDisplayedProgress(of taskID: UUID) {
        guard let transfer = transfers[taskID] else { return }
        let progress = transfer.task.progress
        let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : transfer.expectedSize
        updateDownloadProgress(
            transfer.download,
            downloadedBytes: progress.completedUnitCount,
            totalBytes: totalBytes
        )
    }

    private func cleanupTask(_ taskID: UUID) {
        transfers.removeValue(forKey: taskID)?.observation.invalidate()
    }
}
