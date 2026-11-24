import AppKit
import CryptoKit
import Foundation
import os.log
import ImageIO
import UniformTypeIdentifiers

/// Downloads page icons and keeps them on disk, one file per icon URL.
///
/// Requests go without cookies and with Safari's user agent; icons of `http`
/// sites through WebKit (`WebContentIconFetcher`), which App Transport
/// Security lets load them, unlike the app's own requests. Icons of private
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
    /// Downloads an icon through WebKit (see `WebContentIconFetcher`): an
    /// `http` one, or an `https` one whose certificate the user accepted
    /// for its host, trusting that certificate only.
    private let webContentFetch: @Sendable (URL, AcceptedCertificate?) async -> Data?

    /// Safari's full user agent (WebKit's prefix + `SafariUserAgent.current`).
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) " // no translation
        + SafariUserAgent.current

    /// Larger files are not icons.
    static let maximumSize = 1_000_000

    init(
        directory: URL = FileManager.default.faviconDirectory,
        webContentFetch: @escaping @Sendable (URL, AcceptedCertificate?) async -> Data? = {
            await WebContentIconFetcher.icon(from: $0, trusting: $1)
        }
    ) {
        self.directory = directory
        self.webContentFetch = webContentFetch
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent] // no translation
        session = URLSession(configuration: configuration)
        // Where earlier versions wrote private icons.
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("OmbrePrivateFavicons") // no translation
        )
    }

    /// The first of the icons that can be downloaded, with its local address.
    /// `certificateExceptions`: the page's (`BrowserPage`), by host.
    func firstAvailableIcon(
        among iconURLs: [URL],
        isPrivate: Bool,
        certificateExceptions: [String: String] = [:]
    ) async -> (icon: URL, file: URL)? {
        for iconURL in iconURLs {
            let file = await localFile(for: iconURL, isPrivate: isPrivate, certificateExceptions: certificateExceptions)
            if let file {
                return (iconURL, file)
            }
        }
        return nil
    }

    /// A file for a regular tab, an `ombre-private-favicon:` address for a
    /// private one.
    func localFile(for iconURL: URL, isPrivate: Bool, certificateExceptions: [String: String] = [:]) async -> URL? {
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
            let accepted = AcceptedCertificate.for(iconURL, in: certificateExceptions)
            guard let data = await self.fetch(iconURL, accepted: accepted, isPrivate: isPrivate) else { return nil }
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

    private func fetch(_ iconURL: URL, accepted: AcceptedCertificate?, isPrivate: Bool) async -> Data? {
        guard let data = await download(iconURL, accepted: accepted, isPrivate: isPrivate),
              !data.isEmpty, data.count <= Self.maximumSize, Self.isIconImage(data),
              NSImage(data: data) != nil
        else {
            return nil
        }
        return data
    }

    private func download(_ iconURL: URL, accepted: AcceptedCertificate?, isPrivate: Bool) async -> Data? {
        if Self.needsWebContent(iconURL) {
            if let data = await webContentFetch(iconURL, nil) { return data }
            // Redirected to another origin (often to https), the page's
            // fetch fails: the icon may well be there over https.
            guard let secure = Self.secureVariant(of: iconURL) else { return nil }
            return await sessionData(from: secure, isPrivate: isPrivate)
        }
        // A certificate the user accepted for this host (Continue anyway):
        // `URLSession` would refuse it; WebKit trusts that one only.
        if let accepted {
            let data = await webContentFetch(iconURL, accepted)
            if data == nil {
                let what = "not fetched (https, with the certificate accepted)" // not shown
                log(iconURL, isPrivate: isPrivate, what)
            }
            return data
        }
        return await sessionData(from: iconURL, isPrivate: isPrivate)
    }

    private func sessionData(from iconURL: URL, isPrivate: Bool) async -> Data? {
        do {
            let (data, response) = try await session.data(from: iconURL)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            // Without an exception for this host: no icon, never another way.
            if Self.isCertificateError(error) {
                log(iconURL, isPrivate: isPrivate, "refused: TLS or certificate not trusted, no exception") // not shown
            }
            return nil
        }
    }

    private static let logger = Logger(category: "Favicons")

    private func log(_ iconURL: URL, isPrivate: Bool, _ what: String) {
        let site = PageLog.site(iconURL, isPrivate: isPrivate)
        Self.logger.notice("icon of \(site, privacy: .public) \(what, privacy: .public)") // not shown
    }

    /// A TLS failure about the server's certificate (untrusted, expired,
    /// unknown root…).
    static func isCertificateError(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorSecureConnectionFailed
        ].contains(error.code)
    }

    /// Plain `http`: App Transport Security refuses it to `URLSession`
    /// (error -1022), not to web content.
    static func needsWebContent(_ iconURL: URL) -> Bool {
        iconURL.scheme?.lowercased() == "http"
    }

    static func secureVariant(of iconURL: URL) -> URL? {
        guard var components = URLComponents(url: iconURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        if components.port == 80 { components.port = nil }
        return components.url
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
