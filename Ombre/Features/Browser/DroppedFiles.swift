import Foundation
import UniformTypeIdentifiers

/// Files dropped on a browser window that open as tabs, like in Safari: what a
/// browser shows (pages, PDF, images, text). Others (a zip, an app) are left
/// alone.
enum DroppedFiles {
    /// The images WebKit shows (not every image: a Photoshop or raw file would
    /// open blank).
    static let openableTypes: [UTType] = [
        .html, .pdf, .plainText, .svg, .webArchive, .json,
        .png, .jpeg, .gif, .webP, .heic, .tiff, .bmp, .ico
    ]

    static func isOpenable(_ url: URL) -> Bool {
        guard url.isFileURL, !url.hasDirectoryPath else { return false }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return openableTypes.contains { type.conforms(to: $0) }
    }
}
