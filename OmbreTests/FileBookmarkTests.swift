import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// A local file the page went to by itself is kept by the tab across
    /// relaunches (its bookmark), the previous file's bookmark replaced.
    @MainActor
    @Suite(.serialized)
    struct FileBookmarkTests {
        private func files() throws -> (folder: URL, first: URL, second: URL) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let first = folder.appendingPathComponent("first.html")
            let second = folder.appendingPathComponent("second.html")
            try Data("<p>1</p>".utf8).write(to: first)
            try Data("<p>2</p>".utf8).write(to: second)
            return (folder, first, second)
        }

        private func bookmarkedPath(_ tab: Tab) throws -> String? {
            guard let bookmark = tab.fileBookmark else { return nil }
            var isStale = false
            return try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL.path
        }

        @Test
        func aFileReachedByThePageIsBookmarked() async throws {
            try await TabManagerTestWindow.run { managers in
                let (folder, first, second) = try files()
                defer { try? FileManager.default.removeItem(at: folder) }
                let tab = try managers.open("/page")
                #expect(tab.fileBookmark == nil)

                tab.rememberFileIfNeeded(first)
                #expect(try bookmarkedPath(tab) == first.standardizedFileURL.path)
                let kept = tab.fileBookmark
                tab.rememberFileIfNeeded(first)
                #expect(tab.fileBookmark == kept)

                tab.rememberFileIfNeeded(second)
                #expect(try bookmarkedPath(tab) == second.standardizedFileURL.path)

                // A web page leaves it alone.
                tab.rememberFileIfNeeded(TabManagerTestWindow.url("/web"))
                #expect(try bookmarkedPath(tab) == second.standardizedFileURL.path)
            }
        }

        /// A file Ombre can't read (any more) leaves the tab's bookmark alone.
        @Test
        func anUnreadableFileKeepsTheBookmark() async throws {
            try await TabManagerTestWindow.run { managers in
                let (folder, first, second) = try files()
                defer { try? FileManager.default.removeItem(at: folder) }
                let tab = try managers.open("/page")
                tab.rememberFileIfNeeded(first)
                let kept = try #require(tab.fileBookmark)
                try FileManager.default.removeItem(at: second)
                tab.rememberFileIfNeeded(second)
                #expect(tab.fileBookmark == kept)
            }
        }

        /// The bug: a tab whose page went from one file to another came back
        /// to the first one at the next launch (taken for moved).
        @Test
        func aRelaunchedTabStaysOnItsNewFile() async throws {
            try await TabManagerTestWindow.run { managers in
                let (folder, first, second) = try files()
                defer { try? FileManager.default.removeItem(at: folder) }
                let tab = try managers.open("/page")
                tab.keepFileAccess(to: first)
                tab.updateURL(second)
                tab.rememberFileIfNeeded(second)
                // As at a relaunch: no access yet, from the bookmark.
                tab.endFileAccess()
                tab.beginFileAccessIfNeeded()
                #expect(tab.url.standardizedFileURL.path == second.standardizedFileURL.path)
                tab.endFileAccess()
            }
        }

        /// A pinned tab keeps its own file, even when its page goes elsewhere.
        @Test
        func aPinnedTabKeepsItsFile() async throws {
            try await TabManagerTestWindow.run { managers in
                let (folder, first, second) = try files()
                defer { try? FileManager.default.removeItem(at: folder) }
                let tab = try managers.open("/page")
                tab.type = .pinned
                tab.savedURL = first
                tab.rememberFileIfNeeded(first)
                tab.rememberFileIfNeeded(second)
                #expect(try bookmarkedPath(tab) == first.standardizedFileURL.path)
            }
        }
    }
}
