import AppKit
import Foundation
@testable import Ombre
import Testing

/// Icons of `http` sites: App Transport Security refuses them to the app's
/// own requests (`URLSession`, error -1022), so they come through WebKit
/// (`WebContentIconFetcher`), with the same rules: nothing on the disk for
/// private tabs.
@MainActor
struct HTTPFaviconTests {
    @Test func onlyPlainHTTPGoesThroughWebKit() throws {
        #expect(try FaviconStore.needsWebContent(#require(URL(string: "http://minio.example/favicon.ico"))))
        #expect(try FaviconStore.needsWebContent(#require(URL(string: "HTTP://minio.example/favicon.ico"))))
        #expect(try !FaviconStore.needsWebContent(#require(URL(string: "https://example.com/favicon.ico"))))
        #expect(try !FaviconStore.needsWebContent(#require(URL(string: "data:image/png;base64,AAAA"))))
    }

    @Test func theHiddenPageTakesTheIconsOrigin() throws {
        let icon = try #require(URL(string: "http://minio.example/static/favicon.ico?v=2"))
        #expect(WebContentIconFetcher.origin(of: icon) == URL(string: "http://minio.example/"))
        let withPort = try #require(URL(string: "http://intranet.example:8080/icon.png"))
        #expect(WebContentIconFetcher.origin(of: withPort) == URL(string: "http://intranet.example:8080/"))
        #expect(try WebContentIconFetcher.origin(of: #require(URL(string: "data:image/png;base64,AAAA"))) == nil)
    }

    /// The defect: an `http` icon went to `URLSession`, refused by ATS.
    @Test func anHTTPIconIsFetchedThroughWebKitAndKept() async throws {
        let png = try #require(Self.pngData())
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Asked()
        let store = FaviconStore(directory: directory) { url in
            await asked.add(url)
            return png
        }
        let icon = try #require(URL(string: "http://minio.example/favicon.ico"))

        let file = try #require(await store.localFile(for: icon, isPrivate: false))

        #expect(await asked.urls == [icon])
        #expect(FileManager.default.contents(atPath: file.path) == png)
    }

    @Test func aPrivateHTTPIconStaysInMemory() async throws {
        let png = try #require(Self.pngData())
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory) { _ in png }
        let icon = try #require(URL(string: "http://minio.example/favicon.ico"))

        let address = try #require(await store.localFile(for: icon, isPrivate: true))

        #expect(address.scheme == FaviconStore.privateScheme)
        #expect(await store.privateIconData(for: address) == png)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func whatWebKitBringsMustStillBeAnIcon() async throws {
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory) { _ in Data("<html>login</html>".utf8) }
        let icon = try #require(URL(string: "http://minio.example/favicon.ico"))

        #expect(await store.localFile(for: icon, isPrivate: false) == nil)
    }

    @Test func otherIconsDontGoThroughWebKit() async throws {
        let png = try #require(Self.pngData())
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Asked()
        let store = FaviconStore(directory: directory) { url in
            await asked.add(url)
            return nil
        }
        let icon = try #require(URL(string: "data:image/png;base64," + png.base64EncodedString()))

        #expect(await store.localFile(for: icon, isPrivate: false) != nil)
        #expect(await asked.urls.isEmpty)
    }

    /// The hidden page's script, end to end, without the network: a page of
    /// an `http` origin fetches the icon and hands its bytes back.
    @Test func theHiddenPageHandsTheIconsBytesBack() async throws {
        let png = try #require(Self.pngData())
        let icon = try #require(URL(string: "data:image/png;base64," + png.base64EncodedString()))
        let origin = try #require(URL(string: "http://favicon-test.invalid/"))
        let fetcher = WebContentIconFetcher()

        #expect(await fetcher.data(from: icon, origin: origin) == png)
        #expect(await fetcher.data(from: icon, origin: origin, maximumSize: 8) == nil)
    }

    private actor Asked {
        var urls: [URL] = []
        func add(_ url: URL) {
            urls.append(url)
        }
    }

    private static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HTTPFaviconTests-\(UUID().uuidString)")
    }

    private static func pngData() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
