import Foundation
@testable import Ora
import Testing

struct DownloadFileSizeTests {
    @Test func unknownSizesShowADash() {
        #expect(Download.formattedSize(-1) == "—")
        #expect(Download.formattedSize(0) == "—")
    }

    @Test func knownSizesAreFormatted() {
        #expect(Download.formattedSize(2048) == ByteCountFormatter.string(fromByteCount: 2048, countStyle: .file))
    }

    @Test func sizeIsReadFromTheDownloadedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ora-size-\(UUID().uuidString).html")
        try Data(count: 1234).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(Download.fileSize(at: url) == 1234)
    }

    @Test func missingFileHasNoSize() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ora-missing-\(UUID().uuidString)")

        #expect(Download.fileSize(at: url) == nil)
    }
}
