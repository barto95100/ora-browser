import Foundation
@testable import Ombre
import Testing

/// Local files typed in the address bar open like in Safari.
struct LocalFileAddressTests {
    @Test(arguments: [
        ("file:///Users/someone/notif-test.html", "/Users/someone/notif-test.html"),
        ("file:///Users/someone/My%20Page.html", "/Users/someone/My Page.html"),
        ("file:///Users/someone/My Page.html", "/Users/someone/My Page.html"),
        ("FILE:///tmp/a.pdf", "/tmp/a.pdf"),
        ("file://localhost/tmp/a.pdf", "/tmp/a.pdf")
    ])
    func typedFileAddressesAreFiles(typed: String, path: String) throws {
        let url = try #require(constructURL(from: typed))
        #expect(url.isFileURL)
        #expect(url.path == path)
        #expect(isValidURL(typed))
    }

    /// The page's anchor and query stay out of the file's path.
    @Test
    func anAnchorStaysAnAnchor() throws {
        let url = try #require(localFileURL(from: "file:///Users/someone/page.html?tab=2#notes"))
        #expect(url.path == "/Users/someone/page.html")
        #expect(url.query == "tab=2")
        #expect(url.fragment == "notes")
        let anchorOnly = try #require(localFileURL(from: "file:///Users/someone/page.html#top"))
        #expect(anchorOnly.path == "/Users/someone/page.html")
        #expect(anchorOnly.fragment == "top")
        #expect(anchorOnly.query == nil)
    }

    /// A bare path to an existing file opens it.
    @Test
    func anExistingFilesPathIsAFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("typed \(UUID().uuidString).html")
        try Data("<p>typed</p>".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = try #require(constructURL(from: "  \(file.path)  "))
        #expect(url.isFileURL)
        #expect(url.path == file.path)
        #expect(isValidURL(file.path))
    }

    @Test
    func theHomeFolderIsTheUsersOne() {
        // Not the app's container.
        #expect(expandingHomeFolder("~/Developer/page.html") == "/Users/\(NSUserName())/Developer/page.html")
    }

    /// Searches that start with a slash, folders and paths to nothing.
    @Test(arguments: [
        "/r/swift", "/", "/help me", "~", "~/", "/Users", "~/no-such-file-\(UUID().uuidString)",
        "file://relative/path", "//server/share", "notes", "example.com", "https://example.com/a",
    ])
    func otherTextIsNotAFile(typed: String) {
        #expect(localFileURL(from: typed) == nil)
    }
}

/// A typed file Ombre may not read yet: the user is asked first.
@MainActor
@Suite(.serialized)
struct LocalFileAccessTests {
    private final class Requests {
        var asked: [URL] = []
    }

    /// Runs `body` with the access request answered by `answer`.
    private func withRequests(
        answer: @escaping (URL) -> URL?,
        _ body: (Requests) async throws -> Void
    ) async rethrows {
        let requests = Requests()
        let previous = LocalFileAccess.requestAccess
        LocalFileAccess.requestAccess = { url, completion in
            requests.asked.append(url)
            completion(answer(url))
        }
        defer { LocalFileAccess.requestAccess = previous }
        try await body(requests)
    }

    /// A file Ombre can't read (no read permission).
    private func unreadableFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("unreadable-\(UUID().uuidString).html")
        try Data("<p>file</p>".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        return url
    }

    private func readableFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("readable-\(UUID().uuidString).html")
        try Data("<p>file</p>".utf8).write(to: url)
        return url
    }

    @Test
    func aReadableFileOpensAtOnce() async throws {
        let file = try readableFile()
        defer { try? FileManager.default.removeItem(at: file) }
        await withRequests(answer: { $0 }) { requests in
            var opened: URL?
            LocalFileAccess.whenReadable(file) { opened = $0 }
            #expect(opened == file)
            #expect(requests.asked.isEmpty)
        }
    }

    @Test
    func anUnreadableFileOpensOnceAllowed() async throws {
        let file = try unreadableFile()
        let granted = try readableFile()
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: granted)
        }
        await withRequests(answer: { _ in granted }) { requests in
            var opened: URL?
            LocalFileAccess.whenReadable(file) { opened = $0 }
            #expect(requests.asked == [file])
            #expect(opened == granted)
        }
    }

    @Test
    func aDeclinedFileStaysClosed() async throws {
        let file = try unreadableFile()
        defer { try? FileManager.default.removeItem(at: file) }
        await withRequests(answer: { _ in nil }) { requests in
            var opened: URL?
            LocalFileAccess.whenReadable(file) { opened = $0 }
            #expect(requests.asked == [file])
            #expect(opened == nil)
        }
    }

    @Test
    func webAddressesAreNotChecked() async throws {
        try await withRequests(answer: { $0 }) { requests in
            var opened: URL?
            let page = try #require(URL(string: "https://example.com"))
            LocalFileAccess.whenReadable(page) { opened = $0 }
            #expect(opened == page)
            #expect(requests.asked.isEmpty)
        }
    }
}

extension TabManagerTests {
    @MainActor
    @Suite(.serialized)
    struct TypedFileTabTests {
        /// Typed in the current tab: it keeps access to the file after a
        /// relaunch (its bookmark is that file's, not the previous one's).
        @Test
        func aTypedFileIsKeptByTheTab() async throws {
            try await TabManagerTestWindow.run { managers in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let first = folder.appendingPathComponent("first.html")
                let typed = folder.appendingPathComponent("typed.html")
                try Data("<p>first</p>".utf8).write(to: first)
                try Data("<p>typed</p>".utf8).write(to: typed)

                let tab = try managers.open("/page")
                tab.keepFileAccess(to: first)
                tab.loadURL(typed.absoluteString)

                let bookmark = try #require(tab.fileBookmark)
                var isStale = false
                let resolved = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                #expect(resolved.standardizedFileURL.path == typed.standardizedFileURL.path)
            }
        }
    }
}
