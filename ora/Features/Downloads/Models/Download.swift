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
    @Attribute(.unique) var id: UUID
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
        let storedURL = Self.storableURL(for: originalURL)
        self.originalURL = storedURL
        self.originalURLString = storedURL.absoluteString
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

    /// Updates what the UI shows while bytes arrive. Persisted fields stay untouched,
    /// so progress never dirties the database; they are written on start, finish,
    /// failure and cancel. Returns whether anything visible changed.
    @discardableResult
    func updateDisplayProgress(downloadedBytes: Int64, totalBytes: Int64) -> Bool {
        let size = totalBytes > 0 ? totalBytes : displayFileSize
        let fraction = size > 0 ? min(Double(downloadedBytes) / Double(size), 1) : 0
        guard downloadedBytes != displayDownloadedBytes || size != displayFileSize || fraction != displayProgress
        else { return false }
        displayDownloadedBytes = downloadedBytes
        displayFileSize = size
        displayProgress = fraction
        return true
    }

    /// Copies the displayed progress into the persisted fields.
    private func persistDisplayedProgress() {
        downloadedBytes = displayDownloadedBytes
        progress = displayProgress
        if displayFileSize > 0 { fileSize = displayFileSize }
    }

    func markCompleted(destinationURL: URL) {
        persistDisplayedProgress()
        self.status = .completed
        self.progress = 1.0
        self.destinationURL = destinationURL
        self.completedAt = Date()
        self.isActive = false
        refreshFileSizeFromDisk()
        if fileSize > 0 { downloadedBytes = fileSize }
        displayProgress = 1.0
        displayDownloadedBytes = downloadedBytes
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
        persistDisplayedProgress()
        self.status = .failed
        self.error = error
        self.isActive = false
    }

    func markCancelled() {
        persistDisplayedProgress()
        self.status = .cancelled
        self.isActive = false
    }

    static let interruptedError = "Interrupted"

    /// A download still "downloading" from a previous session has no task behind it anymore.
    func markInterrupted() {
        status = .failed
        error = Self.interruptedError
        isActive = false
    }

    /// `data:` and `blob:` URLs only make sense inside the page that made them,
    /// so the download cannot be retried from history.
    var canRetry: Bool {
        !Self.pageLocalSchemes.contains(originalURL.scheme?.lowercased() ?? "")
    }

    private static let pageLocalSchemes: Set<String> = ["data", "blob"]

    /// Short form kept in the database: a `data:` URL can weigh megabytes, so only its
    /// media type is kept (`data:image/png`); a `blob:` URL keeps its origin
    /// (`blob:https://example.com`). Other URLs are kept as is.
    static func storableURL(for url: URL) -> URL {
        let string = url.absoluteString
        switch url.scheme?.lowercased() {
        case "data":
            let mediaType = string.dropFirst("data:".count).prefix { $0 != "," && $0 != ";" }
            return URL(string: "data:\(mediaType)") ?? URL(string: "data:") ?? url
        case "blob":
            let inner = URL(string: String(string.dropFirst("blob:".count)))
            guard let inner, let scheme = inner.scheme, let host = inner.host else {
                return URL(string: "blob:") ?? url
            }
            let port = inner.port.map { ":\($0)" } ?? ""
            return URL(string: "blob:\(scheme)://\(host)\(port)") ?? url
        default:
            return url
        }
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
