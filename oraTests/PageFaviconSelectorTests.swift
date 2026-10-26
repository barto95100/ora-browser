import Foundation
@testable import Ora
import Testing

struct PageFaviconSelectorTests {
    private let page = URL(string: "https://docs.example.com/document/1")!

    private func icon(
        _ href: String,
        rel: String = "icon",
        sizes: String = "",
        type: String = ""
    ) -> PageIconCandidate {
        PageIconCandidate(href: href, rel: rel, sizes: sizes, type: type)
    }

    @Test func noDeclaredIconFallsBackToFaviconIco() throws {
        let urls = PageFaviconSelector.orderedIconURLs(from: [], pageURL: page)

        #expect(try urls == [#require(URL(string: "https://docs.example.com/favicon.ico"))])
    }

    @Test func relativeIconsResolveAgainstThePage() throws {
        let urls = PageFaviconSelector.orderedIconURLs(from: [icon("/img/icon.png")], pageURL: page)

        #expect(try urls.first == #require(URL(string: "https://docs.example.com/img/icon.png")))
    }

    @Test func closestSizeAboveSidebarSizeWins() {
        let urls = PageFaviconSelector.orderedIconURLs(
            from: [
                icon("https://cdn.example.com/16.png", sizes: "16x16"),
                icon("https://cdn.example.com/192.png", sizes: "192x192"),
                icon("https://cdn.example.com/32.png", sizes: "32x32")
            ],
            pageURL: page
        )

        #expect(urls.first?.lastPathComponent == "32.png")
        #expect(urls.last?.lastPathComponent == "favicon.ico")
    }

    /// Touch icons are reliable raster images; SVG may not render everywhere.
    @Test func plainIconFirstThenTouchIconThenSvg() {
        let urls = PageFaviconSelector.orderedIconURLs(
            from: [
                icon("/apple.png", rel: "apple-touch-icon", sizes: "180x180"),
                icon("/icon.svg", type: "image/svg+xml"),
                icon("/favicon.png")
            ],
            pageURL: page
        )

        #expect(urls.map(\.lastPathComponent) == ["favicon.png", "apple.png", "icon.svg", "favicon.ico"])
    }

    @Test func unsupportedSchemesAreIgnored() throws {
        let urls = PageFaviconSelector.orderedIconURLs(from: [icon("javascript:alert(1)")], pageURL: page)

        #expect(try urls == [#require(URL(string: "https://docs.example.com/favicon.ico"))])
    }

    @Test func sizesAreParsed() {
        #expect(PageFaviconSelector.parsedSizes("16x16 32X32") == [16, 32])
        #expect(PageFaviconSelector.parsedSizes("any").isEmpty)
    }

    @Test func iconFilesAreNamedByURL() throws {
        let first = try FaviconStore.fileName(for: #require(URL(string: "https://a.example/icon.png")))
        let second = try FaviconStore.fileName(for: #require(URL(string: "https://b.example/icon.png")))

        #expect(first != second)
        #expect(first.count == 32)
    }
}
