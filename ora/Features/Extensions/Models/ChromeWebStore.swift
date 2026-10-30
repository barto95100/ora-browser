import Foundation

/// Extensions from the Chrome Web Store, fetched like Chrome does.
enum ChromeWebStore {
    /// The Chrome version Ora asks for: extensions are served for it.
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

    /// Where Chrome downloads an extension (a `.crx`).
    static func downloadURL(for extensionID: String) -> URL? {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")
        components?.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx2,crx3"),
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
            "This file isn't a browser extension."
        }
    }

    private static let zipMagic = Data([0x50, 0x4B, 0x03, 0x04])

    /// The `.zip` inside a `.crx` (versions 2 and 3); a `.zip` stays as is.
    static func zipData(from data: Data) throws -> Data {
        let data = Data(data)
        if data.prefix(4) == zipMagic { return data }
        guard data.count > 16, data.prefix(4) == Data("Cr24".utf8) else { throw Failure.notAnExtension }
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

/// Extension packages kept by Ora: `Application Support/Extensions/Packages`,
/// one `.zip` or folder per extension, named after it.
enum ExtensionPackages {
    static var folder: URL {
        ExtensionRegistry.standard.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Packages", isDirectory: true)
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
        // Only Ora's own copies, never an app.
        guard url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
