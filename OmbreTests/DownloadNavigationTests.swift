import Foundation
@testable import Ombre
import Testing

/// A load that becomes a download (MOT-04, MOT-21).
@MainActor
struct DownloadNavigationTests {
    /// A frame's file never counts as the page's load (the tab used to go
    /// back a page), and a frame's page leaves the page's state alone.
    @Test func aFramesFileLeavesThePageAlone() {
        #expect(BrowserDownloadPolicy.handling(isForMainFrame: false, isDownload: true) == .frameDownload)
        #expect(BrowserDownloadPolicy.handling(isForMainFrame: true, isDownload: true) == .pageDownload)
        #expect(BrowserDownloadPolicy.handling(isForMainFrame: false, isDownload: false) == .show)
        #expect(BrowserDownloadPolicy.handling(isForMainFrame: true, isDownload: false) == .show)
    }

    /// The page shown stays: the tab no longer goes back. Only a tab
    /// opened for the file closes.
    @Test func onlyATabThatShowedNothingCloses() {
        let shown = URL(string: "https://example.com/")
        #expect(!TabBrowserPageDelegate.closesTab(afterDownloadNavigation: true, shown: shown))
        #expect(TabBrowserPageDelegate.closesTab(afterDownloadNavigation: true, shown: nil))
        #expect(!TabBrowserPageDelegate.closesTab(afterDownloadNavigation: false, shown: nil))
    }

    @Test(arguments: [
        ("report.pdf", "report.pdf"),
        ("../../.zshrc", "-..-.zshrc"),
        ("a/b:c.txt", "a-b-c.txt"),
        (".hidden", "hidden"),
        ("...", DownloadFileName.fallback),
        ("", DownloadFileName.fallback),
        ("  \n ", DownloadFileName.fallback),
        ("line\u{0}break.txt", "line break.txt"),
        (". .zshrc", "zshrc"),
        (". . .", DownloadFileName.fallback),
    ])
    func fileNamesStayInTheDownloadsFolder(suggested: String, saved: String) {
        #expect(DownloadFileName.safe(suggested) == saved)
    }

    @Test func aLongNameWithoutExtensionIsCut() {
        let name = DownloadFileName.safe(String(repeating: "a", count: 400))
        #expect(name.utf8.count == 255)
    }

    /// One character longer than the disk allows (a letter and its many
    /// accents): never an empty or hidden name.
    @Test func anUncuttableNameFallsBack() {
        let giant = "e" + String(repeating: "\u{301}", count: 200)
        #expect(DownloadFileName.safe(giant + ".zip") == DownloadFileName.fallback)
        #expect(DownloadFileName.safe(giant) == DownloadFileName.fallback)
    }

    @Test func aLongNameKeepsItsExtension() {
        let name = DownloadFileName.safe(String(repeating: "é", count: 300) + ".zip")
        #expect(name.utf8.count <= 255)
        #expect(name.hasSuffix(".zip"))
    }
}
