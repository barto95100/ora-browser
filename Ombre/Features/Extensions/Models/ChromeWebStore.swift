import Foundation

/// Extensions from the Chrome Web Store, fetched like Chrome does.
enum ChromeWebStore {
    /// The Chrome version Ombre asks for: extensions are served for it.
    /// Review it with each Ombre version (the store may stop serving some
    /// extensions to an old Chrome).
    static let chromeVersion = "141.0.0.0"

    /// The extension of a store page (`chromewebstore.google.com/detail/name/id`,
    /// or the older `chrome.google.com/webstore/detail/name/id`).
    static func extensionID(from url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let isDetailPage = (host == "chromewebstore.google.com" && parts.first == "detail")
            || (host == "chrome.google.com" && parts.starts(with: ["webstore", "detail"]))
        guard isDetailPage else { return nil }
        return parts.last(where: isExtensionID)
    }

    /// 32 letters from a to p.
    static func isExtensionID(_ text: String) -> Bool {
        text.count == 32 && text.allSatisfy { ("a" ... "p").contains($0) }
    }

    /// The largest package downloaded, well above any store extension.
    static let maximumPackageSize = 100 * 1024 * 1024

    /// Google's own servers only, in HTTPS (where the store sends packages).
    static func isDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return ["google.com", "googleusercontent.com", "gvt1.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Downloads a package, stopping past `maximumPackageSize`.
    static func downloadPackage(_ request: URLRequest, session: URLSession = .shared) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadFailure.notFound }
        if let finalURL = response.url, !isDownloadURL(finalURL) { throw DownloadFailure.notFromTheStore }
        if response.expectedContentLength > maximumPackageSize { throw DownloadFailure.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumPackageSize { throw DownloadFailure.tooLarge }
        }
        guard !data.isEmpty else { throw DownloadFailure.notFound }
        return data
    }

    enum DownloadFailure: LocalizedError {
        case notFound
        case notFromTheStore
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notFound: String(localized: "The Chrome Web Store didn't send this extension.")
            case .notFromTheStore: String(localized: "The extension was sent from outside the Chrome Web Store.")
            case .tooLarge: String(localized: "This extension is too large.")
            }
        }
    }

    /// Where Chrome downloads an extension (a `.crx`).
    static func downloadURL(for extensionID: String) -> URL? {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")
        components?.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: chromeVersion),
            // Version 3 only: the signed one (see `CRXVerifier`).
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(extensionID)&uc")
        ]
        return components?.url
    }
}

/// A Chrome extension file (`.crx`): a header, then a `.zip` that WebKit
/// reads as is.
enum CRXArchive {
    enum Failure: LocalizedError {
        case notAnExtension

        var errorDescription: String? {
            String(localized: "This file isn't a browser extension.")
        }
    }

    private static let zipMagic = Data([0x50, 0x4B, 0x03, 0x04])

    /// The `.zip` inside a `.crx` (versions 2 and 3); a `.zip` stays as is.
    static func zipData(from data: Data) throws -> Data {
        let data = Data(data)
        if data.prefix(4) == zipMagic { return data }
        guard data.count > 16, data.prefix(4) == Data("Cr24".utf8) else { throw Failure.notAnExtension } // not shown
        let start: Int
        switch uint32(data, at: 4) {
        case 3:
            start = 12 + Int(uint32(data, at: 8))
        case 2:
            start = 16 + Int(uint32(data, at: 8)) + Int(uint32(data, at: 12))
        default:
            throw Failure.notAnExtension
        }
        guard start + 4 <= data.count, data.subdata(in: start ..< start + 4) == zipMagic else {
            throw Failure.notAnExtension
        }
        return data.subdata(in: start ..< data.count)
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset ..< offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }
}

/// Extension packages kept by Ombre: `Application Support/Ombre/Extensions/Packages`,
/// one `.zip` or folder per extension, named after it.
enum ExtensionPackages {
    static var folder: URL {
        ExtensionRegistry.standard.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Packages", isDirectory: true) // not shown
    }

    /// Keeps a `.zip` for an extension.
    static func store(zip: Data, id: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(id).zip")
        try zip.write(to: url, options: .atomic)
        return url
    }

    /// Keeps a copy of an unpacked extension (a folder with a manifest.json).
    static func store(folder source: URL, id: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    static func remove(path: String) {
        let url = URL(fileURLWithPath: path)
        // Only Ombre's own copies, never an app.
        guard url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Updates of Chrome Web Store extensions, asked to Google like Chrome does
/// (the "update check" of its update protocol).
enum ChromeWebStoreUpdates {
    struct Update: Equatable {
        let version: String
        let downloadURL: URL
    }

    /// One request for all the extensions and their versions.
    static func checkURL(for extensions: [(storeID: String, version: String)]) -> URL? {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")
        components?.queryItems = [
            URLQueryItem(name: "response", value: "updatecheck"),
            URLQueryItem(name: "prodversion", value: ChromeWebStore.chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx3")
        ] + extensions.map { URLQueryItem(name: "x", value: "id=\($0.storeID)&v=\($0.version)&uc") }
        return components?.url
    }

    /// The updates in Google's answer, by extension; "noupdate" ones are left
    /// out.
    static func parse(_ data: Data) -> [String: Update] {
        let reader = UpdateCheckReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.updates
    }

    private final class UpdateCheckReader: NSObject, XMLParserDelegate {
        var updates: [String: Update] = [:]
        private var appID: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            switch elementName {
            case "app":
                appID = attributes["appid"]
            case "updatecheck":
                guard let appID, attributes["status"] == "ok",
                      let version = attributes["version"],
                      let codebase = attributes["codebase"].flatMap(URL.init(string:)),
                      ChromeWebStore.isDownloadURL(codebase)
                else { return }
                updates[appID] = Update(version: version, downloadURL: codebase)
            default:
                break
            }
        }
    }
}

/// Extension versions: up to four numbers separated by dots (Chrome's rule).
enum ExtensionVersion {
    static func isNewer(_ version: String, than current: String) -> Bool {
        let lhs = numbers(version)
        let rhs = numbers(current)
        for index in 0 ..< max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
