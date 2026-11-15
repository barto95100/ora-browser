import SwiftData
import SwiftUI

/// What a space's page in the sidebar reads from its window's environment,
/// given to it again. The pages used to be hosted apart, where a page made
/// while the app ran (a new space shown at once) was first laid out with none
/// of the window's environment, and a missing object crashed it. They are in
/// the window's own views now (`SpacePager`); this stays as a safety net, and
/// tells what `ContainerView` and its views read (a test hosts it with only
/// these).
struct SpacePageEnvironment: ViewModifier {
    let appState: AppState
    let downloadManager: DownloadManager
    let historyManager: HistoryManager
    let privacyMode: PrivacyMode
    let sidebarManager: SidebarManager
    let tabManager: TabManager
    let toastManager: ToastManager
    let toolbarManager: ToolbarManager
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .environmentObject(appState)
            .environmentObject(downloadManager)
            .environmentObject(historyManager)
            .environmentObject(privacyMode)
            .environmentObject(sidebarManager)
            .environmentObject(tabManager)
            .environmentObject(toastManager)
            .environmentObject(toolbarManager)
            .environment(\.modelContext, modelContext)
    }
}
