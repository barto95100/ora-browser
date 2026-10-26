import AppKit
import CryptoKit
import Foundation

/// Downloads page icons and keeps them on disk, one file per icon URL.
///
/// Requests go without cookies and with Safari's user agent. Icons of private
/// tabs go to a temporary folder emptied at the next launch, so browsing in
/// private leaves no lasting trace.
actor FaviconStore {
    static let shared = FaviconStore()

    private let session: URLSession
    private let directory = FileManager.default.faviconDirectory
    private let privateDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("OraPrivateFavicons", isDirectory: true)
    private var downloads: [URL: Task<URL?, Never>] = [:]

    /// Safari's full user agent (WebKit's prefix + `SafariUserAgent.current`).
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + SafariUserAgent.current

    /// Larger files are not icons.
    static let maximumSize = 1_000_000

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
        // Icons of the previous run's private tabs.
        try? FileManager.default.removeItem(at: privateDirectory)
    }

    /// The first of the icons that can be downloaded, with its local file.
    func firstAvailableIcon(among iconURLs: [URL], isPrivate: Bool) async -> (icon: URL, file: URL)? {
        for iconURL in iconURLs {
            if let file = await localFile(for: iconURL, isPrivate: isPrivate) {
                return (iconURL, file)
            }
        }
        return nil
    }

    func localFile(for iconURL: URL, isPrivate: Bool) async -> URL? {
        let file = (isPrivate ? privateDirectory : directory)
            .appendingPathComponent(Self.fileName(for: iconURL))
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }
        // Several tabs on the same site share one download.
        if let download = downloads[file] {
            return await download.value
        }
        let download = Task { await self.download(iconURL, to: file) }
        downloads[file] = download
        let result = await download.value
        downloads[file] = nil
        return result
    }

    private func download(_ iconURL: URL, to file: URL) async -> URL? {
        do {
            let (data, response) = try await session.data(from: iconURL)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty, data.count <= Self.maximumSize, NSImage(data: data) != nil else {
                return nil
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    static func fileName(for iconURL: URL) -> String {
        SHA256.hash(data: Data(iconURL.absoluteString.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
