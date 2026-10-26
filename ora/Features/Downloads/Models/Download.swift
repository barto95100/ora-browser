import Foundation
import SwiftData

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
    case cancelled
}

@Model
class Download: ObservableObject, Identifiable {
    var id: UUID
    var originalURL: URL
    var originalURLString: String
    var fileName: String
    var fileSize: Int64
    var downloadedBytes: Int64
    var status: DownloadStatus
    var progress: Double
    var destinationURL: URL?
    var createdAt: Date
    var completedAt: Date?
    var error: String?

    @Transient @Published var isActive: Bool = false
    @Transient @Published var displayProgress: Double = 0.0
    @Transient @Published var displayDownloadedBytes: Int64 = 0
    @Transient @Published var displayFileSize: Int64 = 0

    init(
        id: UUID = UUID(),
        originalURL: URL,
        fileName: String,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.originalURL = originalURL
        self.originalURLString = originalURL.absoluteString
        self.fileName = fileName
        self.fileSize = fileSize
        self.downloadedBytes = 0
        self.status = .pending
        self.progress = 0.0
        self.createdAt = Date()

        // Initialize published properties
        self.displayFileSize = fileSize
        self.displayDownloadedBytes = 0
        self.displayProgress = 0.0
    }

    func updateProgress(downloadedBytes: Int64, totalBytes: Int64) {
        self.downloadedBytes = downloadedBytes
        self.fileSize = totalBytes
        self.progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0.0

        // Update published properties for UI
        DispatchQueue.main.async {
            self.displayDownloadedBytes = downloadedBytes
            self.displayFileSize = totalBytes > 0 ? totalBytes : self.fileSize
            self.displayProgress = self.progress
        }
    }

    func markCompleted(destinationURL: URL) {
        self.status = .completed
        self.progress = 1.0
        self.destinationURL = destinationURL
        self.completedAt = Date()
        self.isActive = false
        refreshFileSizeFromDisk()
    }

    /// Takes the size from the downloaded file when the server did not announce
    /// it (e.g. HTML pages), which displayed "-1 byte".
    func refreshFileSizeFromDisk() {
        guard let destinationURL, let size = Self.fileSize(at: destinationURL) else { return }
        fileSize = size
        displayFileSize = size
    }

    static func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    func markFailed(error: String) {
        self.status = .failed
        self.error = error
        self.isActive = false
    }

    func markCancelled() {
        self.status = .cancelled
        self.isActive = false
    }

    var formattedFileSize: String {
        Self.formattedSize(displayFileSize > 0 ? displayFileSize : fileSize)
    }

    /// A size, or a dash while it is unknown (servers may announce -1).
    static func formattedSize(_ bytes: Int64) -> String {
        bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "—"
    }

    var formattedDownloadedSize: String {
        return ByteCountFormatter.string(fromByteCount: displayDownloadedBytes, countStyle: .file)
    }
}
