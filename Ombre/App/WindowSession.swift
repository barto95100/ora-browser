import Foundation
import SwiftData

/// What a browser window owns: its database context and its managers, made
/// once for the window's life (it is a `@StateObject` of `OmbreRoot`, created
/// in its autoclosure, so re-creating `OmbreRoot` creates nothing).
///
/// Normal windows share the app's database (`DatabaseRecovery.mainContainer`),
/// each with its own context; a private window keeps everything in memory, in
/// a container of its own.
@MainActor
final class WindowSession: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let privacyMode: PrivacyMode
    let historyManager: HistoryManager
    let mediaController: MediaController
    let downloadManager: DownloadManager
    let tabManager: TabManager

    convenience init(isPrivate: Bool) {
        // Never crashes on the user's data: see `DatabaseRecovery`.
        self.init(
            isPrivate: isPrivate,
            container: isPrivate ? DatabaseRecovery.inMemoryContainer() : DatabaseRecovery.mainContainer
        )
    }

    init(isPrivate: Bool, container: ModelContainer) {
        modelContainer = container
        modelContext = ModelContext(container)
        privacyMode = PrivacyMode(isPrivate: isPrivate)
        historyManager = HistoryManager(modelContainer: container, modelContext: modelContext)
        mediaController = MediaController()
        downloadManager = DownloadManager(modelContainer: container, modelContext: modelContext)
        tabManager = TabManager(
            modelContainer: container,
            modelContext: modelContext,
            mediaController: mediaController,
            downloadManager: downloadManager,
            historyManager: historyManager
        )
    }
}
