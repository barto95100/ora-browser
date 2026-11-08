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
        // One sheet at a time on a window (a login, a split's other page).
        guard case let .show(offersToStopDialogs) = dialogPolicy.decide(isPageShown: window != nil && isInFront),
              let window, dialogSheet == nil, window.attachedSheet == nil
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
            self?.forgetSheet(alert.window)
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

    /// A login the server asks for: a sheet on the page's window, like
    /// Safari's, with the site's name and a warning when the password would
    /// travel unencrypted. Not for a page out of sight (it gets the refusal).
    func browserPage(
        _ page: BrowserPage,
        authenticate request: HTTPAuthenticationRequest,
        completion: @escaping (URLCredential?) -> Void
    ) {
        let isInFront = tab.map { tab in
            MainActor.assumeIsolated { tab.tabManager?.isShown(tab) ?? false }
        } ?? false
        guard let window = page.window, isInFront, dialogSheet == nil, window.attachedSheet == nil else {
            completion(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = HTTPAuthentication.title(for: request)
        alert.informativeText = HTTPAuthentication.message(for: request)
        alert.alertStyle = request.isSecure ? .informational : .warning
        alert.addButton(withTitle: "Log In")
        alert.addButton(withTitle: "Cancel")
        let fields = HTTPAuthenticationFields(user: request.proposedUser)
        alert.accessoryView = fields.view
        // The name filled in again: straight to the password, like Safari.
        alert.window.initialFirstResponder = request.proposedUser == nil ? fields.user : fields.password

        let isPrivate = tab?.isPrivate ?? true
        dialogSheet = alert.window
        dialogParentWindow = window
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.forgetSheet(alert.window)
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            completion(URLCredential(
                user: fields.user.stringValue,
                password: fields.password.stringValue,
                persistence: HTTPAuthentication.persistence(isPrivate: isPrivate)
            ))
        }
    }

    /// The sheet closed: no longer the page's, unless another one is.
    private func forgetSheet(_ sheet: NSWindow) {
        guard dialogSheet === sheet else { return }
        dialogSheet = nil
        dialogParentWindow = nil
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

/// Name and password fields of the login sheet.
@MainActor
private struct HTTPAuthenticationFields {
    let user = NSTextField()
    let password = NSSecureTextField()
    let view: NSView

    init(user proposedUser: String?) {
        user.placeholderString = "Name"
        user.stringValue = proposedUser ?? ""
        user.contentType = .username
        password.placeholderString = "Password"
        password.contentType = .password
        let stack = NSStackView(views: [user, password])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        for field in [user, password] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        user.nextKeyView = password
        view = stack
    }
}
