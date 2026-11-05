import Foundation

/// The tab's page state, kept in its window's `TabRuntime` (ONG-05). These
/// stand in for the properties `Tab` used to store, until the code reads the
/// runtime directly; all of it runs on the main thread (views, `TabManager`,
/// WebKit's callbacks). Clearing a value never makes a runtime.
extension Tab {
    /// The window's runtime, made if needed to store a value.
    private func runtimeForWriting() -> TabRuntime? {
        MainActor.assumeIsolated { tabManager?.runtime(for: self) }
    }

    private func existingPageRuntime() -> TabRuntime? {
        MainActor.assumeIsolated { runtime }
    }

    private func update(_ change: @MainActor (TabRuntime) -> Void, creating: Bool) {
        guard let runtime = creating ? runtimeForWriting() : existingPageRuntime() else { return }
        MainActor.assumeIsolated { change(runtime) }
    }

    var browserPage: BrowserPage? {
        get { existingPageRuntime().flatMap { runtime in MainActor.assumeIsolated { runtime.page } } }
        set { update({ $0.page = newValue }, creating: newValue != nil) }
    }

    var pageDelegate: TabBrowserPageDelegate? {
        get { existingPageRuntime().flatMap { runtime in MainActor.assumeIsolated { runtime.pageDelegate } } }
        set { update({ $0.pageDelegate = newValue }, creating: newValue != nil) }
    }

    var isWebViewReady: Bool {
        get { existingPageRuntime().map { runtime in MainActor.assumeIsolated { runtime.isPageReady } } ?? false }
        set { update({ if $0.isPageReady != newValue { $0.isPageReady = newValue } }, creating: newValue) }
    }

    var isLoading: Bool {
        get { existingPageRuntime().map { runtime in MainActor.assumeIsolated { runtime.isLoading } } ?? false }
        set { update({ $0.isLoading = newValue }, creating: newValue) }
    }

    var crashRecovery: PageCrashRecoveryPolicy {
        get {
            existingPageRuntime().map { runtime in MainActor.assumeIsolated { runtime.crashRecovery } }
                ?? PageCrashRecoveryPolicy()
        }
        set { update({ $0.crashRecovery = newValue }, creating: true) }
    }

    var isReloadingAfterCrash: Bool {
        get { existingPageRuntime().map { runtime in
            MainActor.assumeIsolated { runtime.isReloadingAfterCrash }
        } ?? false }
        set { update({ $0.isReloadingAfterCrash = newValue }, creating: newValue) }
    }

    var showsCrashRecoveryNotice: Bool {
        get {
            existingPageRuntime().map { runtime in MainActor.assumeIsolated { runtime.showsCrashRecoveryNotice } }
                ?? false
        }
        set {
            update(
                { if $0.showsCrashRecoveryNotice != newValue { $0.showsCrashRecoveryNotice = newValue } },
                creating: newValue
            )
        }
    }

    // MARK: - Prompts, capture, passwords, page details

    private func read<Value>(_ value: @MainActor (TabRuntime) -> Value, otherwise empty: Value) -> Value {
        guard let runtime = existingPageRuntime() else { return empty }
        return MainActor.assumeIsolated { value(runtime) }
    }

    var passwordCoordinator: PasswordAutofillCoordinator? {
        get { read({ $0.passwordCoordinator }, otherwise: nil) }
        set { update({ $0.passwordCoordinator = newValue }, creating: newValue != nil) }
    }

    var passwordOverlayState: PasswordAutofillOverlayState? {
        get { read({ $0.passwordOverlayState }, otherwise: nil) }
        set { update({ $0.passwordOverlayState = newValue }, creating: newValue != nil) }
    }

    var passwordTriggerOverlayState: PasswordAutofillOverlayState? {
        get { read({ $0.passwordTriggerOverlayState }, otherwise: nil) }
        set { update({ $0.passwordTriggerOverlayState = newValue }, creating: newValue != nil) }
    }

    var permissionRequest: SitePermissionRequest? {
        get { read({ $0.permissionRequest }, otherwise: nil) }
        set { update({ $0.permissionRequest = newValue }, creating: newValue != nil) }
    }

    var mediaCaptureState: BrowserMediaCaptureState {
        get { read({ $0.mediaCaptureState }, otherwise: BrowserMediaCaptureState()) }
        set { update({ $0.mediaCaptureState = newValue }, creating: newValue != BrowserMediaCaptureState()) }
    }

    var faviconSiteHost: String? {
        get { read({ $0.faviconSiteHost }, otherwise: nil) }
        set { update({ $0.faviconSiteHost = newValue }, creating: newValue != nil) }
    }

    var lastRecordedVisitURL: URL? {
        get { read({ $0.lastRecordedVisitURL }, otherwise: nil) }
        set { update({ $0.lastRecordedVisitURL = newValue }, creating: newValue != nil) }
    }

    var fileAccessURL: URL? {
        get { read({ $0.fileAccessURL }, otherwise: nil) }
        set { update({ $0.fileAccessURL = newValue }, creating: newValue != nil) }
    }

    var folderAccessRequest: URL? {
        get { read({ $0.folderAccessRequest }, otherwise: nil) }
        set { update({ $0.folderAccessRequest = newValue }, creating: newValue != nil) }
    }

    var blockedContent: [String: Int] {
        get { read({ $0.blockedContent }, otherwise: [:]) }
        set { update({ $0.blockedContent = newValue }, creating: !newValue.isEmpty) }
    }
}
