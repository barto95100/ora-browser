import AppKit

/// The sheets a page shows on its window, like Safari's: `alert`, `confirm`
/// and `prompt` (see `JavaScriptDialogPolicy`) and the login a server asks
/// for. One at a time on a window, never for a page out of sight. Used by
/// tabs, Peek and popups alike.
@MainActor
final class PageSheetPresenter {
    /// When the page may show `alert`, `confirm` and `prompt` dialogs.
    var dialogPolicy = JavaScriptDialogPolicy()
    /// The sheet open for the page, and its window (see `dismiss`).
    private(set) weak var sheet: NSWindow?
    private weak var parentWindow: NSWindow?

    /// A dialog the page asks for, as a sheet on `window` that answers the
    /// page when it closes. `isShown`: the page is in front in its window.
    func runJavaScriptDialog(
        _ dialog: BrowserJavaScriptDialog,
        in window: NSWindow?,
        isShown: Bool,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    ) {
        guard case let .show(offersToStopDialogs) = dialogPolicy.decide(isPageShown: window != nil && isShown),
              let window, sheet == nil, window.attachedSheet == nil
        else {
            completion(.refused)
            return
        }

        let alert = NSAlert()
        alert.messageText = dialog.title
        alert.informativeText = dialog.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "OK"))
        if dialog.kind != .alert {
            alert.addButton(withTitle: String(localized: "Cancel"))
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
            alert.suppressionButton?.title = String(localized: "Don't allow this page to show more dialogs")
        }

        present(alert, on: window) { [weak self] response in
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

    /// A login the server asks for, with the site's name and a warning when
    /// the password would travel unencrypted. A page out of sight gets the
    /// refusal.
    func authenticate(
        _ request: HTTPAuthenticationRequest,
        in window: NSWindow?,
        isShown: Bool,
        isPrivate: Bool,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let window, isShown, sheet == nil, window.attachedSheet == nil else {
            completion(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = HTTPAuthentication.title(for: request)
        alert.informativeText = HTTPAuthentication.message(for: request)
        alert.alertStyle = request.isSecure ? .informational : .warning
        alert.addButton(withTitle: String(localized: "Log In"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let fields = HTTPAuthenticationFields(user: request.proposedUser)
        alert.accessoryView = fields.view
        // The name filled in again: straight to the password, like Safari.
        alert.window.initialFirstResponder = request.proposedUser == nil ? fields.user : fields.password

        present(alert, on: window) { response in
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

    /// The page goes (closed, unloaded, its window closed): its open sheet
    /// closes too, and the page gets its answer (Cancel).
    func dismiss() {
        guard let sheet, let parentWindow else { return }
        self.sheet = nil
        self.parentWindow = nil
        parentWindow.endSheet(sheet, returnCode: .cancel)
    }

    private func present(
        _ alert: NSAlert,
        on window: NSWindow,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        sheet = alert.window
        parentWindow = window
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.forgetSheet(alert.window)
            completion(response)
        }
    }

    /// The sheet closed: no longer the page's, unless another one is.
    private func forgetSheet(_ closed: NSWindow) {
        guard sheet === closed else { return }
        sheet = nil
        parentWindow = nil
    }
}

/// The file picker a page's `<input type="file">` opens. Not modal: the
/// other windows stay usable.
@MainActor
enum BrowserOpenPanel {
    static func run(_ options: BrowserOpenPanelOptions, completion: @escaping ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = options.allowsDirectories
        openPanel.allowsMultipleSelection = options.allowsMultipleSelection
        openPanel.begin { result in
            completion(result == .OK ? openPanel.urls : nil)
        }
    }
}

/// Name and password fields of the login sheet.
@MainActor
private struct HTTPAuthenticationFields {
    let user = NSTextField()
    let password = NSSecureTextField()
    let view: NSView

    init(user proposedUser: String?) {
        user.placeholderString = String(localized: "auth.username", defaultValue: "Name")
        user.stringValue = proposedUser ?? ""
        user.contentType = .username
        password.placeholderString = String(localized: "Password")
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
