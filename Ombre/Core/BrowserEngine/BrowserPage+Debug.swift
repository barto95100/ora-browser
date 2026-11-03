#if DEBUG
    import Foundation
    import WebKit

    extension BrowserPage {
        /// Identifier of the process rendering the page, to simulate a crash by
        /// killing it. Debug builds only: it reads a private WebKit property.
        var webContentProcessIdentifier: pid_t? {
            let key = "_webProcessIdentifier"
            guard webView.responds(to: NSSelectorFromString(key)),
                  let pid = (webView.value(forKey: key) as? NSNumber)?.int32Value,
                  pid > 0
            else {
                return nil
            }
            return pid
        }
    }
#endif
