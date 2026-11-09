import Foundation
@testable import Ombre
import Testing

/// Arc's sidebar file, with made-up data only (Arc can no longer be
/// installed: the format is the one Arc wrote, ids alternating with objects).
struct ArcImporterTests {
    static let sidebar = #"""
    {
      "sidebar": {
        "containers": [
          {"global": {}},
          {
            "spaces": [
              "space-1",
              {"id": "space-1", "title": "Work",
               "customInfo": {"iconType": {"emoji_v2": "💼"}},
               "containerIDs": ["pinned", "pinned-1", "unpinned", "unpinned-1"]},
              "space-2",
              {"id": "space-2", "title": "",
               "customInfo": {"iconType": {"emoji": 127968}},
               "containerIDs": ["pinned", "pinned-2", "unpinned", "unpinned-2"]}
            ],
            "items": [
              "pinned-1", {"id": "pinned-1", "childrenIds": ["tab-1", "folder-1", "split-1"],
                           "data": {"itemContainer": {"containerType": {"spaceItems": {"_0": "space-1"}}}}},
              "tab-1", {"id": "tab-1", "parentID": "pinned-1", "childrenIds": [], "title": "Mail",
                        "data": {"tab": {"savedURL": "https://mail.example.com/", "savedTitle": "Inbox"}}},
              "folder-1", {"id": "folder-1", "parentID": "pinned-1", "childrenIds": ["tab-2", "tab-3"],
                           "title": "Projects", "data": {"list": {}}},
              "tab-2", {"id": "tab-2", "parentID": "folder-1", "childrenIds": [], "title": null,
                        "data": {"tab": {"savedURL": "https://board.example.org/", "savedTitle": "Board"}}},
              "tab-3", {"id": "tab-3", "parentID": "folder-1", "childrenIds": [], "title": null,
                        "data": {"tab": {"savedURL": "file:///Users/someone/notes.txt", "savedTitle": "Notes"}}},
              "split-1", {"id": "split-1", "parentID": "pinned-1", "childrenIds": ["tab-4", "tab-5"],
                          "data": {"splitView": {}}},
              "tab-4", {"id": "tab-4", "parentID": "split-1", "childrenIds": [],
                        "data": {"tab": {"savedURL": "https://left.example.com/", "savedTitle": "Left"}}},
              "tab-5", {"id": "tab-5", "parentID": "split-1", "childrenIds": [],
                        "data": {"tab": {"savedURL": "https://right.example.com/", "savedTitle": "Right"}}},
              "unpinned-1", {"id": "unpinned-1", "childrenIds": ["tab-6"], "data": {"itemContainer": {}}},
              "tab-6", {"id": "tab-6", "parentID": "unpinned-1", "childrenIds": [],
                        "data": {"tab": {"savedURL": "https://open.example.com/", "savedTitle": "Open tab"}}},
              "pinned-2", {"id": "pinned-2", "childrenIds": [], "data": {"itemContainer": {}}},
              "top-1", {"id": "top-1", "childrenIds": ["fav-1"], "data": {"itemContainer": {}}},
              "fav-1", {"id": "fav-1", "parentID": "top-1", "childrenIds": [],
                        "data": {"tab": {"savedURL": "https://calendar.example.com/", "savedTitle": "Calendar"}}}
            ],
            "topAppsContainerIDs": [{"default": {}}, "top-1"]
          }
        ]
      }
    }
    """#

    @Test func spacesKeepTheirPinnedTabsAndFolders() throws {
        let data = try ArcImporter.parse(Data(Self.sidebar.utf8))
        #expect(data.spaces.map(\.name) == ["Work", "Space"])
        #expect(data.spaces.map(\.emoji) == ["💼", "🏠"])
        let work = data.spaces[0]
        #expect(try work.pinned == [
            .tab(ImportedTab(url: #require(URL(string: "https://mail.example.com/")), title: "Mail")),
            .folder(name: "Projects", isOpen: false, items: [
                .tab(ImportedTab(url: #require(URL(string: "https://board.example.org/")), title: "Board"))
            ]),
            .tab(ImportedTab(url: #require(URL(string: "https://left.example.com/")), title: "Left")),
            .tab(ImportedTab(url: #require(URL(string: "https://right.example.com/")), title: "Right"))
        ])
    }

    @Test func favoritesGoToTheFirstSpaceAndOpenTabsStay() throws {
        let data = try ArcImporter.parse(Data(Self.sidebar.utf8))
        #expect(data.spaces[0].favorites.map(\.title) == ["Calendar"])
        #expect(data.spaces[1].favorites.isEmpty)
        // The open (unpinned) tab is not imported.
        let titles = data.spaces.flatMap(\.pinned).map { item -> String in
            if case let .tab(tab) = item { return tab.title }
            return ""
        }
        #expect(!titles.contains("Open tab"))
    }

    @Test func somethingElseIsRefused() {
        #expect(throws: ArcImporter.Failure.unreadable) {
            try ArcImporter.parse(Data(#"{"other": 1}"#.utf8))
        }
        let empty = #"{"sidebar": {"containers": [{"spaces": [], "items": []}]}}"#
        #expect(throws: ArcImporter.Failure.nothingToImport) {
            try ArcImporter.parse(Data(empty.utf8))
        }
    }

    @Test func aFolderNestingWithoutEndIsCut() throws {
        // Each folder holds the next one; the last holds a tab.
        var items: [String] = []
        for level in 0 ... 40 {
            let child = level == 40 ? "tab" : "folder-\(level + 1)"
            items
                .append(
                    #""folder-\#(level)", {"id": "folder-\#(level)", "childrenIds": ["\#(child)"], "title": "F", "data": {"list": {}}}"#
                )
        }
        items
            .append(
                #""tab", {"id": "tab", "childrenIds": [], "data": {"tab": {"savedURL": "https://deep.example.com/"}}}"#
            )
        items.append(#""pinned", {"id": "pinned", "childrenIds": ["folder-0"], "data": {"itemContainer": {}}}"#)
        let json = #"{"sidebar": {"containers": [{"spaces": [{"id": "s", "title": "Deep", "containerIDs": ["pinned", "pinned"]}], "items": [\#(items.joined(separator: ","))]}]}}"#
        let data = try ArcImporter.parse(Data(json.utf8))
        #expect(ImportedPinnedItem.tabCount(in: data.spaces[0].pinned) == 1)
        #expect(ImportedPinnedItem.folderCount(in: data.spaces[0].pinned) <= ArcImporter.maxDepth + 1)
    }
}
