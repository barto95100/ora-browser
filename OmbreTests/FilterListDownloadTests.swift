import Foundation
@testable import Ombre
import Testing

/// Serves a body of `bodySize` bytes, optionally announcing its length.
private final class SizedBodyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodySize = 0
    nonisolated(unsafe) static var announcesLength = true

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var headers = ["Content-Type": "text/plain"]
        if Self.announcesLength { headers["Content-Length"] = String(Self.bodySize) }
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200, httpVersion: nil, headerFields: headers
        )
        client?.urlProtocol(self, didReceive: response ?? HTTPURLResponse(), cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: UInt8(ascii: "a"), count: Self.bodySize))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Custom filter lists: HTTPS only, with a size cap (SEC-17).
@Suite(.serialized)
struct FilterListDownloadTests {
    private func service() -> FilterListUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SizedBodyURLProtocol.self]
        return FilterListUpdateService(session: URLSession(configuration: configuration))
    }

    private func record(_ url: String) -> FilterListRecord {
        FilterListRecord(
            id: "size-test", name: "Size Test", summary: "", sourceKind: .custom, sourceURL: url,
            isRecommended: false, enabledByDefault: false, status: .ready, activeRevision: nil
        )
    }

    @Test func onlyHTTPSListsAreAccepted() async {
        let service = service()
        #expect(service.normalizedURL(from: " https://example.com/list.txt ") != nil)
        #expect(service.normalizedURL(from: "http://example.com/list.txt") == nil)
        #expect(service.normalizedURL(from: "https://") == nil)
        await #expect(throws: AdBlockServiceError.self) {
            try await service.fetchLatest(for: record("http://example.com/list.txt"))
        }
    }

    @Test func aListUnderTheCapIsRead() async throws {
        SizedBodyURLProtocol.bodySize = 1024
        SizedBodyURLProtocol.announcesLength = true
        let result = try await service().fetchLatest(for: record("https://example.com/list.txt"))
        #expect(result.rawText?.count == 1024)
    }

    @Test(arguments: [true, false])
    func aListOverTheCapIsRefused(announcesLength: Bool) async {
        SizedBodyURLProtocol.bodySize = FilterListUpdateService.maxListSize + 1
        SizedBodyURLProtocol.announcesLength = announcesLength
        defer { SizedBodyURLProtocol.bodySize = 0 }
        do {
            _ = try await service().fetchLatest(for: record("https://example.com/list.txt"))
            Issue.record("A list over the cap was read")
        } catch let error as AdBlockServiceError {
            if case .filterListTooLarge = error {} else { Issue.record("Unexpected error: \(error)") }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
