import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads page icons and keeps them on disk, one file per icon URL.
///
/// Requests go without cookies and with Safari's user agent. Icons of private
/// tabs stay in memory only, behind an `ombre-private-favicon:` address, and
/// are forgotten when the last private window closes: browsing in private
/// leaves nothing on the disk.
actor FaviconStore {
    static let shared = FaviconStore()

    /// The scheme of private icons' addresses (see `privateIconData(for:)`).
    static let privateScheme = "ombre-private-favicon"

    private let session: URLSession
    private let directory: URL
    private var privateIcons: [String: Data] = [:]
    /// Changes when private icons are forgotten: a download started before
    /// is not kept.
    private var privateGeneration = 0
    private var downloads: [URL: Task<URL?, Never>] = [:]

    /// Safari's full user agent (WebKit's prefix + `SafariUserAgent.current`).
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + SafariUserAgent.current

    /// Larger files are not icons.
    static let maximumSize = 1_000_000

    init(directory: URL = FileManager.default.faviconDirectory) {
        self.directory = directory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
        // Where earlier versions wrote private icons.
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("OmbrePrivateFavicons")
        )
    }

    /// The first of the icons that can be downloaded, with its local address.
    func firstAvailableIcon(among iconURLs: [URL], isPrivate: Bool) async -> (icon: URL, file: URL)? {
        for iconURL in iconURLs {
            if let file = await localFile(for: iconURL, isPrivate: isPrivate) {
                return (iconURL, file)
            }
        }
        return nil
    }

    /// A file for a regular tab, an `ombre-private-favicon:` address for a
    /// private one.
    func localFile(for iconURL: URL, isPrivate: Bool) async -> URL? {
        let name = Self.fileName(for: iconURL)
        let file = isPrivate ? Self.privateAddress(name) : directory.appendingPathComponent(name)
        if isPrivate ? privateIcons[name] != nil : FileManager.default.fileExists(atPath: file.path) {
            return file
        }
        // Several tabs on the same site share one download.
        if let download = downloads[file] {
            return await download.value
        }
        let generation = privateGeneration
        let download = Task { () -> URL? in
            guard let data = await self.fetch(iconURL) else { return nil }
            if isPrivate, generation != self.privateGeneration { return nil }
            return self.keep(data, named: name, at: file, isPrivate: isPrivate)
        }
        downloads[file] = download
        let result = await download.value
        downloads[file] = nil
        return result
    }

    /// The image of a private icon address, while a private window is open.
    func privateIconData(for address: URL) -> Data? {
        guard address.scheme == Self.privateScheme else { return nil }
        return privateIcons[address.absoluteString.replacingOccurrences(of: Self.privateScheme + ":", with: "")]
    }

    /// When the last private window closes.
    func forgetPrivateIcons() {
        privateIcons = [:]
        privateGeneration += 1
    }

    private func fetch(_ iconURL: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: iconURL)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty, data.count <= Self.maximumSize, Self.isIconImage(data),
                  NSImage(data: data) != nil
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func keep(_ data: Data, named name: String, at file: URL, isPrivate: Bool) -> URL? {
        if isPrivate {
            privateIcons[name] = data
            return file
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    private static func privateAddress(_ name: String) -> URL {
        var components = URLComponents()
        components.scheme = privateScheme
        components.path = name
        return components.url ?? URL(fileURLWithPath: "/dev/null")
    }

    /// Only the image types sites use for icons are decoded (in the app's
    /// process): PNG, ICO, JPEG, GIF, WebP and SVG.
    static func isIconImage(_ data: Data) -> Bool {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as String?,
           acceptedImageTypes.contains(type)
        {
            return true
        }
        return looksLikeSVG(data)
    }

    private static let acceptedImageTypes: Set<String> = [
        UTType.png.identifier,
        // Some old sites serve a bitmap as favicon.ico.
        UTType.bmp.identifier,
        UTType.ico.identifier,
        UTType.jpeg.identifier,
        UTType.gif.identifier,
        UTType.webP.identifier
    ]

    /// The `<svg` tag can come after a long prolog (comments, a DOCTYPE with
    /// entities, as some editors write).
    private static func looksLikeSVG(_ data: Data) -> Bool {
        String(decoding: data.prefix(4096), as: UTF8.self).lowercased().contains("<svg")
    }

    static func fileName(for iconURL: URL) -> String {
        SHA256.hash(data: Data(iconURL.absoluteString.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
