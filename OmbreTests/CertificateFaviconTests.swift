import AppKit
import Foundation
@testable import Ombre
import Testing

/// Icons of sites whose certificate the user accepted (Continue anyway):
/// fetched through WebKit trusting that certificate only, for that host
/// only; never any other untrusted certificate.
@MainActor
struct CertificateFaviconTests {
    private let digest = String(repeating: "ab", count: 32)

    @Test func onlyTheIconsHostWithAnExceptionHasOne() throws {
        let exceptions = ["10.100.100.70": digest]
        let icon = try #require(URL(string: "https://10.100.100.70:8006/pve2/images/favicon.ico"))
        #expect(AcceptedCertificate.for(icon, in: exceptions) == AcceptedCertificate(
            host: "10.100.100.70",
            digest: digest
        ))
        // Another host, or plain http: no exception.
        #expect(try AcceptedCertificate.for(
            #require(URL(string: "https://10.100.100.71:8006/favicon.ico")),
            in: exceptions
        ) == nil)
        #expect(try AcceptedCertificate
            .for(#require(URL(string: "http://10.100.100.70/favicon.ico")), in: exceptions) == nil)
        #expect(AcceptedCertificate.for(icon, in: [:]) == nil)
    }

    @Test func onlyTheCertificateAcceptedIsTrusted() {
        let accepted = AcceptedCertificate(host: "10.100.100.70", digest: digest)
        #expect(accepted.trusts(host: "10.100.100.70", digest: digest))
        // Another certificate on the same host (someone else's on the
        // network), the same one on another host, or none.
        #expect(!accepted.trusts(host: "10.100.100.70", digest: String(repeating: "cd", count: 32)))
        #expect(!accepted.trusts(host: "10.100.100.71", digest: digest))
        #expect(!accepted.trusts(host: "10.100.100.70", digest: nil))
    }

    @Test func certificateErrorsAreTold() {
        for code in [
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorSecureConnectionFailed
        ] {
            #expect(FaviconStore.isCertificateError(NSError(domain: NSURLErrorDomain, code: code)))
        }
        #expect(!FaviconStore.isCertificateError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        #expect(!FaviconStore.isCertificateError(NSError(
            domain: NSCocoaErrorDomain,
            code: NSURLErrorServerCertificateUntrusted
        )))
    }

    /// The defect: the icon of a page whose certificate was accepted went
    /// to `URLSession`, which refused it.
    @Test func anIconWithAnExceptionGoesThroughWebKitWithIt() async throws {
        let png = try #require(Self.pngData())
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Asked()
        let store = FaviconStore(directory: directory) { url, accepted in
            await asked.add(url, accepted)
            return png
        }
        let icon = try #require(URL(string: "https://pve.invalid:8006/favicon.ico"))

        let file = try #require(await store.localFile(
            for: icon, isPrivate: false, certificateExceptions: ["pve.invalid": digest]
        ))

        #expect(await asked.calls == [Asked.Call(
            url: icon,
            accepted: AcceptedCertificate(host: "pve.invalid", digest: digest)
        )])
        #expect(FileManager.default.contents(atPath: file.path) == png)
    }

    @Test func aPrivateIconWithAnExceptionStaysInMemory() async throws {
        let png = try #require(Self.pngData())
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory) { _, _ in png }
        let icon = try #require(URL(string: "https://pve.invalid:8006/favicon.ico"))

        let address = try #require(await store.localFile(
            for: icon, isPrivate: true, certificateExceptions: ["pve.invalid": digest]
        ))

        #expect(address.scheme == FaviconStore.privateScheme)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Without an exception for its host, an https icon never goes through
    /// WebKit: an untrusted certificate gives no icon.
    @Test func anIconWithoutAnExceptionStaysWithURLSession() async throws {
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Asked()
        let store = FaviconStore(directory: directory) { url, accepted in
            await asked.add(url, accepted)
            return nil
        }
        let icon = try #require(URL(string: "https://other.invalid/favicon.ico"))

        #expect(await store
            .localFile(for: icon, isPrivate: false, certificateExceptions: ["pve.invalid": digest]) == nil)
        #expect(await asked.calls.isEmpty)
    }

    private actor Asked {
        struct Call: Equatable {
            let url: URL
            let accepted: AcceptedCertificate?
        }

        var calls: [Call] = []
        func add(_ url: URL, _ accepted: AcceptedCertificate?) {
            calls.append(Call(url: url, accepted: accepted))
        }
    }

    private static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CertificateFaviconTests-\(UUID().uuidString)")
    }

    private static func pngData() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
