import Foundation
import os.log
import WebKit

private let logger = Logger(category: "FindController")

/// Find in page, in the app's world: the page's own view, or reader mode's
/// while it shows the article (`PageReader.webView`, JavaScript off for the
/// page there, not for the app's scripts).
@MainActor
class FindController: NSObject {
    private weak var webView: WKWebView?

    init(page: BrowserPage) {
        webView = page.reader.webView ?? page.webView
        super.init()
    }

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    private func evaluate(_ script: String, completion: ((Any?) -> Void)? = nil) {
        guard let webView else {
            completion?(nil)
            return
        }
        webView.evaluateJavaScript(script, in: nil, in: BrowserPage.appWorld) { result in
            if case let .failure(error) = result, completion == nil {
                logger.error("Find: \(error.localizedDescription)")
            }
            completion?(try? result.get())
        }
    }

    // MARK: - Inject mark.js

    func injectMarkJS() {
        guard let jsPath = Bundle.main.path(forResource: "mark", ofType: "js"),
              let jsCode = try? String(contentsOfFile: jsPath, encoding: .utf8)
        else {
            logger.error("mark.js not found or failed to load")
            return
        }

        evaluate(jsCode)
    }

    // MARK: - Highlight Text

    func highlight(_ searchTerm: String) {
        let escapedTerm = searchTerm.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            // Inject CSS if missing
            if (!document.getElementById('highlight-style')) {
                const style = document.createElement('style');
                style.id = 'highlight-style';
                style.textContent = `
                    mark.search-highlight {
                        background-color: yellow;
                        color: black;
                    }
                    mark.search-highlight.current {
                        background-color: orange !important;
                    }
                `;
                document.head.appendChild(style);
            }

            if (!window.findController) {
                window.findController = {
                    markInstance: new Mark(document.body),
                    matches: [],
                    currentIndex: -1
                };
            }

            // Unmark existing highlights and apply new
            findController.markInstance.unmark({
                done: function() {
                    findController.markInstance.mark('\(escapedTerm)', {
                        className: "search-highlight",
                        separateWordSearch: false,
                        done: function() {
                            findController.matches = Array.from(document.querySelectorAll("mark.search-highlight"));
                            if (findController.matches.length > 0) {
                                findController.currentIndex = 0;
                                let el = findController.matches[0];
                                el.classList.add("current");
                                el.scrollIntoView({behavior: "smooth", block: "center"});
                            }
                        }
                    });
                }
            });
        })();
        """
        evaluate(js)
    }

    // MARK: - Next Match

    func nextMatch() {
        let js = """
        (function() {
            const fc = window.findController;
            if (fc && fc.matches.length > 0) {
                fc.matches[fc.currentIndex].classList.remove("current");
                fc.currentIndex = (fc.currentIndex + 1) % fc.matches.length;
                const el = fc.matches[fc.currentIndex];
                el.classList.add("current");
                el.scrollIntoView({behavior: "smooth", block: "center"});
            }
        })();
        """
        evaluate(js)
    }

    // MARK: - Previous Match

    func previousMatch() {
        let js = """
        (function() {
            const fc = window.findController;
            if (fc && fc.matches.length > 0) {
                fc.matches[fc.currentIndex].classList.remove("current");
                fc.currentIndex = (fc.currentIndex - 1 + fc.matches.length) % fc.matches.length;
                const el = fc.matches[fc.currentIndex];
                el.classList.add("current");
                el.scrollIntoView({behavior: "smooth", block: "center"});
            }
        })();
        """
        evaluate(js)
    }

    // MARK: - Clear All Matches

    func clearMatches() {
        let js = """
        (function() {
            const fc = window.findController;
            if (fc) {
                fc.markInstance.unmark();
                fc.matches = [];
                fc.currentIndex = -1;
            }
        })();
        """
        evaluate(js)
    }

    // MARK: - Count Matches

    func countMatches(completion: @escaping (Int) -> Void) {
        let js = """
        (function() {
            return window.findController && findController.matches
                ? findController.matches.length
                : 0;
        })();
        """
        evaluate(js) { result in
            let count = result as? Int ?? 0
            completion(count)
        }
    }

    // MARK: - Get Current Match Index

    func getCurrentMatchIndex(completion: @escaping (Int) -> Void) {
        let js = """
        (function() {
            return window.findController
                ? findController.currentIndex + 1
                : 0;
        })();
        """
        evaluate(js) { result in
            let index = result as? Int ?? 0
            completion(index)
        }
    }

    // MARK: - Get Match Info

    func getMatchInfo(completion: @escaping (Int, Int) -> Void) {
        let js = """
        (function() {
            if (window.findController) {
                return {
                    total: findController.matches.length,
                    current: findController.currentIndex + 1
                };
            }
            return { total: 0, current: 0 };
        })();
        """
        evaluate(js) { result in
            if let dict = result as? [String: Any],
               let total = dict["total"] as? Int,
               let current = dict["current"] as? Int
            {
                completion(current, total)
            } else {
                completion(0, 0)
            }
        }
    }
}
