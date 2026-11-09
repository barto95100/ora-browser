import AppKit

extension TabBrowserPageDelegate {
    /// `alert`, `confirm` and `prompt`, like Safari: a sheet on the page's
    /// window (the other windows stay usable), saying which site asks, that
    /// answers the page when it closes. See `PageSheetPresenter`.
    func browserPage(
        _ page: BrowserPage,
        runJavaScriptDialog dialog: BrowserJavaScriptDialog,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    ) {
        sheets.runJavaScriptDialog(dialog, in: page.window, isShown: isTabInFront, completion: completion)
    }

    /// A login the server asks for: a sheet on the page's window, like
    /// Safari's. Not for a page out of sight (it gets the refusal).
    func browserPage(
        _ page: BrowserPage,
        authenticate request: HTTPAuthenticationRequest,
        completion: @escaping (URLCredential?) -> Void
    ) {
        sheets.authenticate(
            request,
            in: page.window,
            isShown: isTabInFront,
            isPrivate: tab?.isPrivate ?? true,
            completion: completion
        )
    }

    /// The page goes (tab closed or unloaded, window closed): its open dialog
    /// closes too, and the page gets its answer (Cancel).
    func dismissDialog() {
        sheets.dismiss()
    }

    /// In front in its window (not a background tab, nor one parked in the
    /// window for Picture in Picture).
    private var isTabInFront: Bool {
        tab.map { tab in
            MainActor.assumeIsolated { tab.tabManager?.isShown(tab) ?? false }
        } ?? false
    }
}
