import Foundation
@testable import Ora
import Testing

struct BrowserNavigationErrorTests {
    @Test func aMediaFileShownByWebKitIsNotAnError() {
        let error = NSError(domain: "WebKitErrorDomain", code: BrowserNavigationError.plugInWillHandleLoad)
        #expect(BrowserNavigationError.isInterruption(error))
    }

    @Test func cancelledAndRedirectedLoadsAreNotErrors() {
        #expect(BrowserNavigationError.isInterruption(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(BrowserNavigationError.isInterruption(NSError(
            domain: "WebKitErrorDomain",
            code: BrowserNavigationError.frameLoadInterruptedByPolicyChange
        )))
    }

    @Test func realFailuresStillShowAnError() {
        #expect(!BrowserNavigationError.isInterruption(NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost
        )))
        #expect(!BrowserNavigationError.isInterruption(NSError(domain: "WebKitErrorDomain", code: 101)))
    }
}
