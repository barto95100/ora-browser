import Darwin
import Foundation
@testable import Ombre
import Testing
import WebKit

/// The context menu finds WebKit's "Open Link/Image in New Window" items by
/// identifier (MOT-24). If WebKit changes them, Ombre's "New Tab",
/// "Background Tab" and "Split View" items disappear without a sound: this
/// test fails instead. Only reads WebKit's exported constants.
struct ContextMenuIdentifierTests {
    private func webKitConstant(_ name: String) -> String? {
        _ = WKWebView.self // WebKit loaded.
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, name) else { return nil }
        let pointer = symbol.assumingMemoryBound(to: NSString?.self)
        return pointer.pointee as String?
    }

    @Test func webKitStillNamesItsOpenLinkItemTheSame() {
        #expect(webKitConstant("_WKMenuItemIdentifierOpenLinkInNewWindow") == BrowserPage.openLinkIdentifier)
    }

    @Test func webKitStillNamesItsOpenImageItemTheSame() {
        #expect(webKitConstant("_WKMenuItemIdentifierOpenImageInNewWindow") == BrowserPage.openImageIdentifier)
    }
}
