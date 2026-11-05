import Foundation
@testable import Ombre
import Testing

/// Files dropped on a window open as tabs when a browser shows them.
struct DroppedFilesTests {
    @Test func pagesDocumentsAndImagesOpen() {
        for name in [
            "page.html",
            "page.htm",
            "doc.pdf",
            "photo.jpg",
            "image.png",
            "drawing.svg",
            "notes.txt",
            "a.json"
        ] {
            #expect(DroppedFiles.isOpenable(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
    }

    @Test func otherFilesAndFoldersDont() throws {
        // A Photoshop file is an image WebKit doesn't show.
        for name in ["archive.zip", "installer.dmg", "music.mp3", "noextension", "layers.psd"] {
            #expect(!DroppedFiles.isOpenable(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
        #expect(!DroppedFiles.isOpenable(URL(fileURLWithPath: "/tmp/folder/", isDirectory: true)))
        #expect(try !DroppedFiles.isOpenable(#require(URL(string: "https://example.com/page.html"))))
    }
}
