import AppKit

extension TabBrowserPageDelegate {
    /// `alert`, `confirm` and `prompt`, like Safari: a sheet on the page's
    /// window (the other windows stay usable), saying which site asks, that
    /// answers the page when it closes. See `JavaScriptDialogPolicy`.
    func browserPage(
        _ page: BrowserPage,
        runJavaScriptDialog dialog: BrowserJavaScriptDialog,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    ) {
        // In front in its window (not a background tab, nor one parked in
        // the window for Picture in Picture).
        let window = page.window
        let isInFront = tab.map { tab in
            MainActor.assumeIsolated { tab.tabManager?.isShown(tab) ?? false }
        } ?? false
        guard case let .show(offersToStopDialogs) = dialogPolicy.decide(isPageShown: window != nil && isInFront),
              let window
        else {
            completion(.refused)
            return
        }

        let alert = NSAlert()
        alert.messageText = dialog.title
        alert.informativeText = dialog.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if dialog.kind != .alert {
            alert.addButton(withTitle: "Cancel")
        }
        var textField: NSTextField?
        if case let .prompt(defaultText) = dialog.kind {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.stringValue = defaultText
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            textField = field
        }
        if offersToStopDialogs {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't allow this page to show more dialogs"
        }

        dialogSheet = alert.window
        dialogParentWindow = window
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.dialogSheet = nil
            self?.dialogParentWindow = nil
            if alert.suppressionButton?.state == .on {
                self?.dialogPolicy.stopDialogs()
            }
            let isConfirmed = response == .alertFirstButtonReturn
            completion(BrowserJavaScriptDialogReply(
                isConfirmed: isConfirmed,
                text: isConfirmed ? textField?.stringValue : nil
            ))
        }
    }

    /// The page goes (tab closed or unloaded, window closed): its open dialog
    /// closes too, and the page gets its answer (Cancel).
    func dismissDialog() {
        guard let sheet = dialogSheet, let parent = dialogParentWindow else { return }
        dialogSheet = nil
        dialogParentWindow = nil
        parent.endSheet(sheet, returnCode: .cancel)
    }
}
