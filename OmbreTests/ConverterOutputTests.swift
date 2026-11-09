import Foundation
@testable import Ombre
import Testing

/// The rule converter's thousands of lines don't reach the console; the
/// output comes back after (lot F).
/// On the main actor: never alongside the tests that compile a list.
@MainActor
@Suite(.serialized)
struct ConverterOutputTests {
    private func outputFile() -> (device: dev_t, inode: ino_t) {
        var info = stat()
        fstat(STDOUT_FILENO, &info)
        return (info.st_dev, info.st_ino)
    }

    private func nullFile() -> (device: dev_t, inode: ino_t) {
        var info = stat()
        stat("/dev/null", &info)
        return (info.st_dev, info.st_ino)
    }

    @Test func theOutputGoesNowhereWhileAListCompilesThenComesBack() {
        let before = outputFile()
        let (during, nested, afterNested) = ConverterOutput.silenced {
            let during = outputFile()
            let nested = ConverterOutput.silenced { outputFile() }
            return (during, nested, outputFile())
        }
        let null = nullFile()
        #expect(during == null)
        #expect(nested == null)
        // Still silenced while the outer compilation goes on.
        #expect(afterNested == null)
        #expect(outputFile() == before)
    }

    @Test func aFailingCompilationGivesTheOutputBack() {
        struct Failure: Error {}
        let before = outputFile()
        #expect(throws: Failure.self) {
            try ConverterOutput.silenced { throw Failure() }
        }
        #expect(outputFile() == before)
    }
}
