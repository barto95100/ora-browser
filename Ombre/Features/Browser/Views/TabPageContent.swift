import SwiftUI

/// A tab's page with its overlays (prompts, find bar, link preview...), or its
/// error or loading state. Shown alone, or as one side of a split.
struct TabPageContent: View {
    @Environment(\.theme) var theme
    @EnvironmentObject private var appState: AppState
    let tab: Tab

    /// The tab's state in this window: its error page, the hovered link. A
    /// ready page always has one; never made here (it changes the tab).
    private var runtime: TabRuntime? {
        tab.runtime
    }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if tab.isWebViewReady {
            if let failure = runtime?.navigationFailure {
                StatusPageView(
                    error: failure.error,
                    failedURL: failure.url,
                    onRetry: { tab.retryNavigation() },
                    onGoBack: tab.canGoBack
                        ? {
                            tab.goBack()
                            tab.clearNavigationError()
                        } : nil,
                    // Only for a refused certificate it can trust (see
                    // `CertificateException`): never a button that does nothing.
                    onContinueAnyway: CertificateException.trust(in: failure.error) == nil ? nil : {
                        tab.continueToInsecureSite()
                    }
                )
                .id(tab.id)
            } else if let page = tab.browserPage {
                BrowserPageView(page: page).id(tab.id)
                    .background {
                        if let runtime { PageTranslationHost(tab: tab, runtime: runtime) }
                    }
                    .overlay(alignment: .topLeading) {
                        if let triggerState = tab.passwordTriggerOverlayState {
                            PasswordAutofillTriggerView(overlay: triggerState, tab: tab)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let passwordOverlayState = tab.passwordOverlayState {
                            PasswordAutofillOverlayView(overlay: passwordOverlayState, tab: tab)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if appState.showFinderIn == tab.id {
                            FindView(page: page)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let hovered = runtime?.hoveredLinkURL {
                            LinkPreview(text: hovered)
                        }
                    }
                    .overlay(alignment: .top) {
                        if let request = tab.permissionRequest {
                            SitePermissionPromptView(request: request, isPrivate: tab.isPrivate) { granted, remember in
                                tab.answerPermissionRequest(granted: granted, remember: remember)
                            }
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .top) {
                        if tab.showsCrashRecoveryNotice {
                            PageCrashNoticeView { tab.dismissCrashRecoveryNotice() }
                                .padding(.top, 12)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: runtime?.hoveredLinkURL)
                    .animation(.easeOut(duration: 0.2), value: tab.permissionRequest)
                    .overlay(alignment: .top) {
                        if let folder = tab.folderAccessRequest {
                            LocalFolderAccessPromptView(
                                folderName: folder.lastPathComponent,
                                onAllow: { tab.requestFolderAccess() },
                                onDismiss: { tab.folderAccessRequest = nil }
                            )
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    // An extension's page in the Chrome Web Store: "Add to Ombre".
                    .overlay(alignment: .top) {
                        ChromeWebStoreBanner(tab: tab)
                            .padding(.top, 12)
                    }
                    .animation(.easeOut(duration: 0.2), value: tab.showsCrashRecoveryNotice)
                    .animation(.easeOut(duration: 0.2), value: tab.folderAccessRequest)
                    // A site blocked during focus.
                    .overlay { FocusBlockView(tab: tab) }
            } else {
                ZStack {
                    Rectangle().fill(theme.background)
                    ProgressView().frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ZStack {
                Rectangle().fill(theme.background)
                ProgressView().frame(width: 32, height: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
