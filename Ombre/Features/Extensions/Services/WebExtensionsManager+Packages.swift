import AppKit
import UniformTypeIdentifiers
@preconcurrency import WebKit

/// Extensions that aren't Safari extensions: from the Chrome Web Store, or a
/// folder or archive the user chose. Ombre keeps its own copy (a package).
@available(macOS 15.4, *)
extension WebExtensionsManager {
    enum PackageFailure: LocalizedError {
        case download
        case noManifest

        var errorDescription: String? {
            switch self {
            case .download: String(localized: "The Chrome Web Store didn't send this extension.")
            case .noManifest: String(localized: "This folder has no manifest.json: it isn't an extension.")
            }
        }
    }

    /// The installed extension from this Chrome Web Store page, if any.
    func installed(storeID: String) -> ExtensionRecord? {
        installed.first { $0.record.storeID == storeID }?.record
    }

    /// Downloads an extension from the Chrome Web Store, like Chrome, to
    /// show what it asks for before adding it.
    func reviewFromWebStore(_ storeID: String) async throws -> Review {
        guard let url = ChromeWebStore.downloadURL(for: storeID) else { throw PackageFailure.download }
        let data = try await ChromeWebStore.downloadPackage(Self.chromeRequest(url))
        // Signed by its developer, and the extension asked for.
        let zip = try CRXVerifier.verifiedZip(from: data, extensionID: storeID)
        let id = UUID().uuidString
        let package = try ExtensionPackages.store(zip: zip, id: id)
        return try await review(
            package: package,
            id: id,
            source: .chromeWebStore(storeID: storeID, packagePath: package.path),
            fallbackName: String(localized: "Extension")
        )
    }

    /// An extension the user chose: a folder with a manifest.json, a `.zip`
    /// or a `.crx`. Ombre copies it.
    func reviewFile(at url: URL) async throws -> Review {
        let id = UUID().uuidString
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let package: URL
        if url.hasDirectoryPath {
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else {
                throw PackageFailure.noManifest
            }
            package = try ExtensionPackages.store(folder: url, id: id)
        } else {
            package = try ExtensionPackages.store(zip: CRXArchive.zipData(from: Data(contentsOf: url)), id: id)
        }
        return try await review(
            package: package,
            id: id,
            source: .file(packagePath: package.path),
            fallbackName: url.deletingPathExtension().lastPathComponent
        )
    }

    /// Not added after all: its package goes.
    func discard(_ review: Review) {
        guard installed.allSatisfy({ $0.id != review.id }), let path = review.source.packagePath else { return }
        ExtensionPackages.remove(path: path)
    }

    /// Lets the user choose a folder, `.zip` or `.crx` (Settings › Extensions).
    static func chooseExtensionFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder, .init(filenameExtension: "crx") ?? .data]
        panel.message = String(localized: "Choose an extension: a folder with a manifest.json, a .zip or a .crx.")
        panel.prompt = String(localized: "Choose")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func review(package: URL, id: String, source: ExtensionRecord.Source, fallbackName: String)
        async throws -> Review
    {
        do {
            let webExtension = try await WKWebExtension(resourceBaseURL: package)
            return Review(id: id, source: source, appName: nil, fallbackName: fallbackName, webExtension: webExtension)
        } catch {
            ExtensionPackages.remove(path: package.path)
            throw error
        }
    }
}

extension ExtensionRecord.Source {
    /// Ombre's copy, for an extension that isn't in an app.
    var packagePath: String? {
        switch self {
        case .safariApp: nil
        case let .chromeWebStore(_, path): path
        case let .file(path): path
        }
    }
}
