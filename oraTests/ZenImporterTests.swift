import Foundation
@testable import Ora
import Testing

struct ZenImporterTests {
    /// Two spaces; Essentials found by container, by space, or neither; a
    /// folder in a folder; a split view folder; tabs that are not imported.
    private let session = """
    {
      "spaces": [
        {"uuid": "{perso}", "name": "Perso", "icon": "👨‍💻", "containerTabId": 1},
        {"uuid": "{work}", "name": "Work", "icon": "chrome://browser/skin/zen-icons/selectable/briefcase.svg"}
      ],
      "folders": [
        {"id": "f-dev", "name": "Dev", "parentId": null, "workspaceId": "{work}", "collapsed": false},
        {"id": "f-prod", "name": "Prod", "parentId": "f-dev", "workspaceId": "{work}", "collapsed": true},
        {"id": "f-split", "name": "Split", "parentId": "f-dev", "workspaceId": "{work}", "splitViewGroup": true},
        {"id": "f-empty", "name": "Empty", "parentId": null, "workspaceId": "{work}"}
      ],
      "tabs": [
        {"pinned": true, "zenEssential": true, "userContextId": 0, "zenWorkspace": null,
         "entries": [{"url": "https://mail.example.com/", "title": "Mail"}], "index": 1},
        {"pinned": true, "zenEssential": true, "userContextId": 1, "zenWorkspace": null,
         "entries": [{"url": "https://cal.example.com/", "title": "Calendar"}], "index": 1},
        {"pinned": true, "zenEssential": true, "userContextId": 0, "zenWorkspace": "{work}",
         "entries": [{"url": "https://chat.example.com/", "title": "Chat"}], "index": 1},
        {"pinned": true, "zenWorkspace": "{work}", "groupId": "f-prod", "zenStaticLabel": "Prod console",
         "_zenPinnedInitialState": {"entry": {"url": "https://prod.example.com/", "title": "Console"}},
         "entries": [{"url": "https://prod.example.com/"}, {"url": "https://prod.example.com/later"}], "index": 2},
        {"pinned": true, "zenWorkspace": "{work}",
         "entries": [{"url": "https://wiki.example.com/", "title": "Wiki"}], "index": 1},
        {"pinned": true, "zenWorkspace": "{work}", "groupId": "f-dev",
         "entries": [{"url": "https://git.example.com/", "title": "Git"}], "index": 1},
        {"pinned": true, "zenWorkspace": "{work}", "groupId": "f-split",
         "entries": [{"url": "https://docs.example.com/", "title": "Docs"}], "index": 1},
        {"pinned": true, "zenWorkspace": "{perso}", "image": "https://news.example.com/icon.png",
         "entries": [{"url": "https://news.example.com/", "title": "News"}], "index": 1},
        {"pinned": true, "zenWorkspace": "{perso}", "zenIsEmpty": true,
         "entries": [{"url": "about:blank"}], "index": 1},
        {"pinned": true, "zenWorkspace": "{perso}",
         "entries": [{"url": "about:preferences", "title": "Settings"}], "index": 1},
        {"pinned": false, "zenWorkspace": "{perso}",
         "entries": [{"url": "https://open.example.com/", "title": "Open tab"}], "index": 1}
      ]
    }
    """

    private func imported() throws -> ImportedBrowserData {
        try ZenImporter.parse(Data(session.utf8))
    }

    private func tab(_ url: String, _ title: String, favicon: String? = nil) throws -> ImportedPinnedItem {
        let url = try #require(URL(string: url))
        return .tab(ImportedTab(url: url, title: title, faviconURL: favicon.flatMap(URL.init(string:))))
    }

    @Test func spacesKeepTheirNameAndEmoji() throws {
        let spaces = try imported().spaces
        #expect(spaces.map(\.name) == ["Perso", "Work"])
        #expect(spaces.map(\.emoji) == ["👨‍💻", nil])
    }

    @Test func essentialsGoToTheSpaceOfTheirContainer() throws {
        let spaces = try imported().spaces
        // Container 1 is Perso's; container 0 has no space: its own space, else the first.
        #expect(spaces[0].favorites.map(\.title) == ["Mail", "Calendar"])
        #expect(spaces[1].favorites.map(\.title) == ["Chat"])
    }

    @Test func pinnedTabsAndNestedFoldersKeepZenOrder() throws {
        let spaces = try imported().spaces
        #expect(try spaces[0].pinned == [tab(
            "https://news.example.com/",
            "News",
            favicon: "https://news.example.com/icon.png"
        )])
        #expect(try spaces[1].pinned == [
            .folder(name: "Dev", isOpen: true, items: [
                .folder(name: "Prod", isOpen: false, items: [tab("https://prod.example.com/", "Prod console")]),
                tab("https://git.example.com/", "Git"),
                // A split view's tabs show in the folder above it.
                tab("https://docs.example.com/", "Docs")
            ]),
            tab("https://wiki.example.com/", "Wiki"),
            .folder(name: "Empty", isOpen: true, items: [])
        ])
    }

    @Test func countsCoverEverySpace() throws {
        let data = try imported()
        #expect(data.favoriteCount == 3)
        #expect(data.pinnedTabCount == 5)
        #expect(data.folderCount == 3)
    }

    @Test func mozLZ4DecodesALiteralBlock() throws {
        let text = Data(String(repeating: "Zen session ", count: 4).utf8)
        let decoded = try MozLZ4.decompress(Self.mozLZ4(literals: text))
        #expect(decoded == text)
        #expect(throws: MozLZ4.Failure.self) { try MozLZ4.decompress(Data("{}".utf8)) }
    }

    @Test func takenNamesGetTheBrowserName() {
        #expect(TabManager.importedName("Perso", browser: "Zen", taken: []) == "Perso")
        #expect(TabManager.importedName("Perso", browser: "Zen", taken: ["Perso"]) == "Perso (Zen)")
        #expect(TabManager.importedName("Perso", browser: "Zen", taken: ["Perso", "Perso (Zen)"]) == "Perso (Zen 2)")
    }

    /// A `.jsonlz4` file whose LZ4 block holds only literals.
    static func mozLZ4(literals: Data) -> Data {
        var file = Data("mozLz40\0".utf8)
        withUnsafeBytes(of: UInt32(literals.count).littleEndian) { file.append(contentsOf: $0) }
        var length = literals.count
        file.append(UInt8(min(length, 15) << 4))
        if length >= 15 {
            length -= 15
            while length >= 255 {
                file.append(255)
                length -= 255
            }
            file.append(UInt8(length))
        }
        file.append(literals)
        return file
    }
}
