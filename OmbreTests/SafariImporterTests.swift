import Compression
import Foundation
@testable import Ombre
import SwiftData
import Testing

/// Safari's export, with made-up data only.
struct SafariImporterTests {
    static let bookmarks = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <HTML>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DT><H3>Favorites</H3>
    <DL><p>
        <DT><A HREF="https://news.example.com/">News &amp; more</A>
        <DT><H3>Work</H3>
        <DL><p>
            <DT><A HREF="https://tracker.example.org/board?a=1&amp;b=2">Board</A>
        </DL><p>
    </DL><p>
    <DT><H3>Recipes</H3>
    <DL><p>
        <DT><A HREF="https://cook.example.net/">Cooking</A>
        <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
    </DL><p>
    </HTML>
    """

    static func history(_ visits: [(String, Int64, Int)]) -> Data {
        let items = visits.map { url, time, count in
            #"{"url": "\#(url)", "time_usec": \#(time), "visit_count": \#(count), "title": "Page"}"#
        }
        let json = #"{"metadata": {"browser_name": "Safari", "data_type": "history", "schema_version": 1}, "#
            + #""history": [\#(items.joined(separator: ","))]}"#
        return Data(json.utf8)
    }

    static func files() -> [(path: String, data: Data)] {
        [
            ("Export/Signets.html", Data(bookmarks.utf8)),
            ("Export/Historique - Work.json", history([("https://work.example.com/", 1_700_000_000_000_000, 3)])),
            ("Export/Historique.json", history([
                ("https://old.example.com/", 1_600_000_000_000_000, 1),
                ("https://new.example.com/", 1_700_000_000_000_000, 5),
                ("file:///Users/someone/secret.txt", 1_700_000_000_000_000, 1)
            ])),
            ("Export/Extensions.json", Data(#"{"metadata": {"data_type": "extensions"}, "extensions": []}"#.utf8))
        ]
    }

    @Test func theBookmarksKeepTheirFolders() throws {
        let top = SafariBookmarks.parse(Self.bookmarks)
        guard case let .folder(name, _, items)? = top.first else {
            Issue.record("No Favorites folder")
            return
        }
        #expect(name == "Favorites")
        #expect(try items.first == .tab(ImportedTab(
            url: #require(URL(string: "https://news.example.com/")),
            title: "News & more"
        )))
        guard case let .folder(work, _, workItems) = items[1] else {
            Issue.record("No Work folder")
            return
        }
        #expect(work == "Work")
        #expect(try workItems == [.tab(ImportedTab(
            url: #require(URL(string: "https://tracker.example.org/board?a=1&b=2")),
            title: "Board"
        ))])
        // Web addresses only: the bookmarklet is left out.
        #expect(ImportedPinnedItem.tabCount(in: top) == 3)
    }

    @Test func profilesAreFoundByWhatTheyHold() throws {
        let export = try SafariImporter.read(files: Self.files())
        #expect(export.profiles.map(\.name) == [nil, "Work"])
        let main = try #require(export.profiles.first)
        // Most recent first; a local file is not a web page.
        #expect(main.history.map(\.url.host) == ["new.example.com", "old.example.com"])
        #expect(main.history.first?.visitCount == 5)
        #expect(main.history.first?.lastVisit == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(export.bookmarkCount == 3)
    }

    @Test func theBookmarksGoToTheChosenSpace() throws {
        let export = try SafariImporter.read(files: Self.files())
        let data = export.spaces(profiles: [0, 1], bookmarksIn: 1, defaultName: "Safari")
        #expect(data.spaces.map(\.name) == ["Safari", "Work"])
        #expect(data.spaces[0].pinned.isEmpty)
        // The Favorites bar's content, then the other folders.
        #expect(data.spaces[1].pinned.count == 3)
        #expect(data.spaces[1].history.count == 1)
        #expect(export.spaces(profiles: [0], bookmarksIn: nil, defaultName: "Safari").spaces[0].pinned.isEmpty)
    }

    @Test func aZipIsReadInMemory() throws {
        let archive = ZipBuilder.archive(Self.files() + [("__MACOSX/Export/._Signets.html", Data("junk".utf8))])
        let export = try SafariImporter.read(archive: archive)
        #expect(export.profiles.count == 2)
        #expect(export.bookmarkCount == 3)
    }

    @Test func storedAndDeflatedFilesAreRead() throws {
        let text = Data(String(repeating: "Ombre ", count: 500).utf8)
        let entries = try ZipReader.entries(of: ZipBuilder.archive([("a.txt", text), ("b.txt", text)], deflateFrom: 1))
        #expect(entries.map(\.path) == ["a.txt", "b.txt"])
        #expect(entries.allSatisfy { $0.data == text })
    }

    @Test func somethingElseIsRefused() {
        #expect(throws: SafariImporter.Failure.unreadable) {
            try SafariImporter.read(archive: Data("not a zip".utf8))
        }
        #expect(throws: SafariImporter.Failure.nothingToImport) {
            try SafariImporter.read(files: [("notes.txt", Data("hello".utf8))])
        }
    }

    @Test func bookmarksAloneGetASpace() throws {
        let export = try SafariImporter.read(files: [("Bookmarks.html", Data(Self.bookmarks.utf8))])
        #expect(export.profiles == [SafariImporter.Profile(name: nil, history: [])])
    }

    /// A damaged or forged archive is refused, never read past its end.
    @Test func aBrokenZipIsRefused() {
        let good = ZipBuilder.archive([("a.json", Data("{}".utf8))])
        // Cut: the end record is gone.
        #expect(throws: ZipReader.Failure.notAZip) { try ZipReader.entries(of: good.prefix(20)) }
        // The file's data claims to start past the archive's end.
        var forged = good
        let central = forged.count - 22 - 46 - 6
        forged[central + 42] = 0xFF
        forged[central + 43] = 0xFF
        #expect(throws: ZipReader.Failure.damaged) { try ZipReader.entries(of: forged) }
        // A stored file whose sizes disagree.
        var mismatch = good
        mismatch[central + 24] = 9
        #expect(throws: ZipReader.Failure.damaged) { try ZipReader.entries(of: mismatch) }
        // Too large once unpacked.
        var huge = good
        huge[central + 27] = 0x7F
        #expect(throws: ZipReader.Failure.tooLarge) { try ZipReader.entries(of: huge) }
    }

    @Test func onlyBookmarksAndHistoriesAreUnpacked() throws {
        let archive = ZipBuilder.archive([
            ("Export/Passwords.csv", Data("site,user,password".utf8)),
            ("Export/History.json", Self.history([("https://a.example.com/", 1_700_000_000_000_000, 1)]))
        ])
        let entries = try ZipReader.entries(of: archive, shouldRead: SafariImporter.isReadable)
        #expect(entries.map(\.path) == ["Export/History.json"])
    }

    @Test func anAddressSeenTwiceIsOneEntry() {
        let data = Self.history([
            ("https://a.example.com/", 1_600_000_000_000_000, 2),
            ("https://a.example.com/", 1_700_000_000_000_000, 3)
        ])
        let visits = SafariImporter.history(from: data) ?? []
        #expect(visits.count == 1)
        #expect(visits.first?.visitCount == 5)
        #expect(visits.first?.lastVisit == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func profileNamesComeFromTheFileName() {
        #expect(SafariImporter.profileName(fromFile: "History - A - B.json") == "A - B")
        #expect(SafariImporter.profileName(fromFile: "History - Personal stuff.json") == "Personal stuff")
        #expect(SafariImporter.profileName(fromFile: "Historique.json") == nil)
    }
}

extension TabManagerTests {
    /// Safari's history lands in the new space, with its dates and counts.
    @MainActor
    struct SafariHistoryImport {
        @Test func theHistoryIsImportedIntoTheSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let visit = ImportedVisit(
                    url: URL(string: "https://work.example.com/")!, title: "Work",
                    lastVisit: Date(timeIntervalSince1970: 1_700_000_000), visitCount: 3
                )
                var space = ImportedSpace(name: "Work")
                space.history = [visit]
                let created = window.tabManager.importSpaces(ImportedBrowserData(spaces: [space]), from: "Safari")
                let imported = try #require(created.first)
                window.remember(imported)
                let spaceID = imported.id
                let entries = try window.modelContext.fetch(FetchDescriptor<History>())
                    .filter { $0.container?.id == spaceID }
                #expect(entries.count == 1)
                #expect(entries.first?.visitCount == 3)
                #expect(entries.first?.lastAccessedAt == visit.lastVisit)
            }
        }
    }
}

/// A minimal zip writer for the tests (no CRC: the reader doesn't check it).
enum ZipBuilder {
    static func archive(_ files: [(path: String, data: Data)], deflateFrom: Int = .max) -> Data {
        var body = Data()
        var central = Data()
        for (index, file) in files.enumerated() {
            let deflated = index >= deflateFrom ? deflate(file.data) : nil
            let stored = deflated ?? file.data
            let name = Data(file.path.utf8)
            let method: UInt16 = deflated == nil ? 0 : 8
            let offset = UInt32(body.count)
            let sizes = le32(UInt32(stored.count)) + le32(UInt32(file.data.count))
            var local = le32(0x04034B50) + le16(20) + le16(0) + le16(method)
            local += le32(0) + le32(0) + sizes
            local += le16(UInt16(name.count)) + le16(0)
            body += local + name + stored
            var entry = le32(0x02014B50) + le16(20) + le16(20) + le16(0) + le16(method)
            entry += le32(0) + le32(0) + sizes
            entry += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0)
            entry += le32(0) + le32(offset)
            central += entry + name
        }
        var end = le32(0x06054B50) + le16(0) + le16(0)
        end += le16(UInt16(files.count)) + le16(UInt16(files.count))
        end += le32(UInt32(central.count)) + le32(UInt32(body.count)) + le16(0)
        return body + central + end
    }

    private static func deflate(_ data: Data) -> Data {
        let input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: input.count + 1024)
        let size = compression_encode_buffer(&output, output.count, input, input.count, nil, COMPRESSION_ZLIB)
        return Data(output.prefix(size))
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data((0 ..< 4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}
