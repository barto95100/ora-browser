import Foundation

struct FilterListFetchResult {
    let record: FilterListRecord
    let rawText: String?
}

/// Only a URL session (thread-safe): used from the ad blocker's actor.
final class FilterListUpdateService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The largest list downloaded: the biggest public lists are a few
    /// megabytes; past this, the download stops.
    static let maxListSize = 32 * 1024 * 1024

    func isValidCustomListURL(_ rawValue: String) -> Bool {
        normalizedURL(from: rawValue) != nil
    }

    /// HTTPS only: the app's own requests in clear are blocked anyway (App
    /// Transport Security), and a list read in clear could be changed on the way.
    func normalizedURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    /// The response's body, stopped past `limit` bytes.
    static func body(
        of bytes: URLSession.AsyncBytes,
        expectedLength: Int64,
        limit: Int = maxListSize
    ) async throws -> Data {
        if expectedLength > Int64(limit) { throw AdBlockServiceError.filterListTooLarge(bytes: expectedLength) }
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(expectedLength)) }
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw AdBlockServiceError.filterListTooLarge(bytes: Int64(data.count)) }
        }
        return data
    }

    func fetchLatest(for record: FilterListRecord) async throws -> FilterListFetchResult {
        guard let url = normalizedURL(from: record.sourceURL) else {
            throw AdBlockServiceError.invalidCustomListURL
        }

        var request = URLRequest(url: url)
        if let etag = record.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = record.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AdBlockServiceError.invalidFilterResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            let data = try await Self.body(of: bytes, expectedLength: response.expectedContentLength)
            guard let rawText = String(data: data, encoding: .utf8) else {
                throw AdBlockServiceError.invalidFilterResponse
            }

            var updatedRecord = record
            updatedRecord.lastFetchAt = Date()
            updatedRecord.etag = httpResponse.value(forHTTPHeaderField: "ETag")
            updatedRecord.lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
            updatedRecord.lastErrorMessage = nil
            return FilterListFetchResult(record: updatedRecord, rawText: rawText)
        case 304:
            var updatedRecord = record
            updatedRecord.lastFetchAt = Date()
            updatedRecord.lastErrorMessage = nil
            return FilterListFetchResult(record: updatedRecord, rawText: nil)
        default:
            throw AdBlockServiceError.downloadFailed(statusCode: httpResponse.statusCode)
        }
    }
}
