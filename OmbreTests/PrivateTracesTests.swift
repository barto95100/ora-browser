import AppKit
import Foundation
@testable import Ombre
import Testing

/// Private browsing leaves nothing behind: permissions go with their window,
/// icons stay in memory and go with the last private window.
@MainActor
struct PrivateTracesTests {
    private let origin = SiteOrigin(scheme: "https", host: "meet.example.com", port: nil) ?? {
        preconditionFailure("valid test origin")
    }()

    private func makeStore() -> SitePermissionStore {
        let suite = "PrivateTracesTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("defaults suite") }
        defaults.removePersistentDomain(forName: suite)
        return SitePermissionStore(defaults: defaults)
    }

    @Test func aClosedPrivateWindowForgetsItsPermissions() {
        let store = makeStore()
        var forgotIcons = 0
        let windows = PrivateWindows(permissions: store, forgetIcons: { forgotIcons += 1 })
        let first = NSObject()
        let second = NSObject()
        let firstSpace = UUID()
        let secondSpace = UUID()
        windows.opened(first)
        windows.opened(second)
        store.setState(.allow, for: [.camera], origin: origin, in: firstSpace, isPrivate: true)
        store.setState(.allow, for: [.camera], origin: origin, in: secondSpace, isPrivate: true)

        windows.closed(first, spaceIDs: [firstSpace])

        #expect(store.permissions(for: origin, in: firstSpace, isPrivate: true).camera == .ask)
        // The other private window keeps its own, and the icons.
        #expect(store.permissions(for: origin, in: secondSpace, isPrivate: true).camera == .allow)
        #expect(forgotIcons == 0)

        windows.closed(second, spaceIDs: [secondSpace])

        #expect(store.permissions(for: origin, in: secondSpace, isPrivate: true).camera == .ask)
        #expect(forgotIcons == 1)
        #expect(windows.isEmpty)
    }

    @Test func closingAnUnknownWindowChangesNothing() {
        var forgotIcons = 0
        let windows = PrivateWindows(permissions: makeStore(), forgetIcons: { forgotIcons += 1 })

        windows.closed(NSObject(), spaceIDs: [])

        #expect(forgotIcons == 0)
    }

    @Test func onlyIconImageTypesAreDecoded() throws {
        let png = try #require(Self.pngData())
        #expect(FaviconStore.isIconImage(png))
        #expect(FaviconStore.isIconImage(Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)))
        // A TIFF is an image, but not a site icon.
        let tiff = try #require(NSImage(size: NSSize(width: 2, height: 2), flipped: false) { _ in
            true
        }.tiffRepresentation)
        #expect(!FaviconStore.isIconImage(tiff))
        #expect(!FaviconStore.isIconImage(Data("<html><body>not an icon</body></html>".utf8)))
    }

    @Test func privateIconsHaveNoFileAndAreForgotten() async throws {
        let png = try #require(Self.pngData())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateTracesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory)
        let iconURL = try #require(URL(string: "data:image/png;base64," + png.base64EncodedString()))

        let address = try #require(await store.localFile(for: iconURL, isPrivate: true))

        #expect(address.scheme == FaviconStore.privateScheme)
        #expect(await store.privateIconData(for: address) == png)
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        await store.forgetPrivateIcons()

        #expect(await store.privateIconData(for: address) == nil)
    }

    @Test func regularIconsAreStillKeptOnDisk() async throws {
        let png = try #require(Self.pngData())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateTracesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory)
        let iconURL = try #require(URL(string: "data:image/png;base64," + png.base64EncodedString()))

        let file = try #require(await store.localFile(for: iconURL, isPrivate: false))

        #expect(file.isFileURL)
        #expect(FileManager.default.contents(atPath: file.path) == png)
    }

    @Test func anSVGAfterALongPrologIsAnIcon() {
        let prolog = "<?xml version='1.0'?><!-- " + String(repeating: "é", count: 600) + " -->"
        #expect(FaviconStore.isIconImage(Data((prolog + "<svg xmlns='http://www.w3.org/2000/svg'/>").utf8)))
    }

    private static func pngData() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.systemPink.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
