import Foundation
import UniformTypeIdentifiers
import WebKit

/// "Send to a Note": the article becomes a note of the space, its images
/// saved next to it (notes show only their own files), with its link.
/// Never from a private window: private windows have no notes.
@MainActor
enum ReaderNote {
    /// At most this many images, each up to `maximumImageSize`: the rest
    /// stay as links to the site.
    static let maximumImages = 40
    static let maximumImageSize: Int64 = 15 * 1024 * 1024

    /// The images are downloaded by the reader's web view: with the page's
    /// data and protections, as the reader showed them.
    static func save(
        _ article: ReaderArticle,
        in spaceID: UUID,
        named spaceName: String,
        downloadingWith webView: WKWebView,
        completion: @escaping @MainActor (Note?) -> Void
    ) {
        let store = NotesStore.shared
        let folder = store.folder(for: spaceID, named: spaceName)
        let sources = Array(article.images.prefix(maximumImages))
        ImageDownloads(webView: webView, folder: folder).fetch(sources) { saved in
            guard let note = store.create(in: folder, title: article.title) else { return completion(nil) }
            store.write(markdown(for: article, images: saved), to: note)
            completion(note)
        }
    }

    /// Its link and details first, then the article, its images as saved.
    /// Notes show only their own files: an image not saved becomes a link
    /// to the site's (an embedded one, none).
    static func markdown(for article: ReaderArticle, images: [String: String]) -> String {
        let saved = Dictionary(
            images.map { (escapedForLink($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let pattern = /!\[([^\]\n]*)\]\(([^)\s]+)\)/
        let text = article.markdown.replacing(pattern) { match in
            let alt = String(match.output.1)
            let source = String(match.output.2)
            if let path = saved[source] { return "![\(alt)](\(path))" }
            guard source.hasPrefix("https:") || source.hasPrefix("http:") else { return "" }
            let text = alt.isEmpty ? String(localized: "reader.note.image", defaultValue: "Image") : alt
            return "[\(text)](\(source))" // not shown
        }
        let title = escaped(article.title)
        let link = escapedForLink(article.pageURL.absoluteString)
        return "[\(title)](\(link))\n\n*\(escaped(article.details))*\n\n\(text)\n"
    }

    /// Words of the page as text in Markdown, never as its marks.
    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<>#".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// As the reader's script writes addresses in Markdown.
    static func escapedForLink(_ address: String) -> String {
        address.replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: " ", with: "%20")
    }

    static func fileExtension(for mimeType: String?, suggested: String?) -> String? {
        if let mimeType, mimeType.hasPrefix("image/"),
           let type = UTType(mimeType: mimeType), let ext = type.preferredFilenameExtension
        {
            return ext == "jpeg" ? "jpg" : ext
        }
        let ext = (suggested as NSString?)?.pathExtension.lowercased() ?? ""
        return ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "svg"].contains(ext) ? ext : nil
    }
}

/// Downloads images one after the other into the note's `attachments`.
@MainActor
private final class ImageDownloads: NSObject, WKDownloadDelegate {
    private let webView: WKWebView
    private let attachments: URL
    private var queue: [String] = []
    private var saved: [String: String] = [:]
    /// The download under way, its image and the file it goes to (once known).
    private struct Current {
        var download: WKDownload?
        let source: String
        var file: URL?
        var size: NSKeyValueObservation?
    }

    private var current: Current?
    private var completion: (@MainActor ([String: String]) -> Void)?
    /// Kept alive until all are done.
    private var keepAlive: ImageDownloads?
    private let stamp: String

    init(webView: WKWebView, folder: URL) {
        self.webView = webView
        attachments = folder.appendingPathComponent("attachments", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        stamp = formatter.string(from: Date())
    }

    func fetch(_ sources: [String], completion: @escaping @MainActor ([String: String]) -> Void) {
        try? FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        queue = sources
        self.completion = completion
        keepAlive = self
        next()
    }

    private func next() {
        guard !queue.isEmpty else {
            completion?(saved)
            completion = nil
            keepAlive = nil
            return
        }
        let source = queue.removeFirst()
        guard let url = URL(string: source) else { return next() }
        if url.scheme == "data" {
            saveData(url, as: source)
            return next()
        }
        guard url.scheme == "https" || url.scheme == "http" else { return next() }
        // A slow site: left as a link rather than the note waiting on it.
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        current = Current(source: source)
        webView.startDownload(using: request) { [weak self] download in
            download.delegate = self
            self?.current?.download = download
            self?.limitSize(of: download)
        }
    }

    /// A size the server didn't tell: cancelled once it grows too big.
    private func limitSize(of download: WKDownload) {
        let limit = ReaderNote.maximumImageSize
        current?.size = download.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            guard progress.completedUnitCount > limit else { return }
            Task { @MainActor in self?.cancelCurrent() }
        }
    }

    /// Too big: WebKit then tells it failed, and the next one starts.
    private func cancelCurrent() {
        current?.size = nil
        current?.download?.cancel { _ in }
    }

    private func saveData(_ source: URL, as key: String) {
        // "data:image/png;base64,…": its type up to the first ";" or ",".
        let type = key.dropFirst(5).prefix { $0 != ";" && $0 != "," }
        guard let ext = ReaderNote.fileExtension(for: String(type), suggested: nil),
              let data = try? Data(contentsOf: source), Int64(data.count) <= ReaderNote.maximumImageSize
        else { return }
        let file = uniqueFile(ext)
        if (try? data.write(to: file)) != nil {
            saved[key] = "attachments/" + file.lastPathComponent
        }
    }

    private func uniqueFile(_ ext: String) -> URL {
        var index = saved.count + 1
        var file: URL
        repeat {
            file = attachments.appendingPathComponent("article-\(stamp)-\(index).\(ext)")
            index += 1
        } while FileManager.default.fileExists(atPath: file.path)
        return file
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let tooBig = response.expectedContentLength > ReaderNote.maximumImageSize
        guard current?.download === download else { return completionHandler(nil) }
        guard !tooBig, let ext = ReaderNote.fileExtension(for: response.mimeType, suggested: suggestedFilename) else {
            // Not an image, or too big: left as a link. Whatever WebKit
            // tells of this download later is ignored.
            completionHandler(nil)
            current = nil
            return next()
        }
        let file = uniqueFile(ext)
        current?.file = file
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let current, current.download === download else { return }
        if let file = current.file {
            saved[current.source] = "attachments/" + file.lastPathComponent
        }
        self.current = nil
        next()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let current, current.download === download else { return }
        if let file = current.file { try? FileManager.default.removeItem(at: file) }
        self.current = nil
        next()
    }
}
