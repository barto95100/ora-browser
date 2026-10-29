import AppKit
import Foundation
import SwiftData
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ExternalFileOpener.shared.install()
        // Before launch ends: a click on a notification can be what launches Ora.
        WebNotificationCenter.shared.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ExternalFileOpener.shared.applicationDidFinishLaunching()
        // Disable automatic window tabbing for all NSWindow instances
        NSWindow.allowsAutomaticWindowTabbing = false
        AppearanceManager.shared.updateAppearance()
        ShortcutOverrideMonitor.shared.start()
        #if DEBUG
            Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
            Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSSwiftUISupport.bundle")?.load()
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let targetWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
        guard let targetWindow else { return .terminateNow }
        NotificationCenter.default.post(name: .quitRequested, object: targetWindow)
        return .terminateLater
    }

    // Links opened from other apps are routed by SwiftUI to a browser window
    // (see `handlesExternalEvents` on the scenes and in `OraRoot`), so the app
    // delegate deliberately does not implement `application(_:open:)`. Files
    // from Finder go through `ExternalFileOpener`.
}

func deleteSwiftDataStore(_ loc: String) {
    let fileManager = FileManager.default
    let storeURL = URL.applicationSupportDirectory.appending(path: loc)
    let shmURL = storeURL.appendingPathExtension("-shm")
    let walURL = storeURL.appendingPathExtension("-wal")
    try? fileManager.removeItem(at: storeURL)
    try? fileManager.removeItem(at: shmURL)
    try? fileManager.removeItem(at: walURL)
}

class AppState: ObservableObject {
    @Published var showLauncher: Bool = false
    /// The history panel (⌘Y), see `HistoryPanel`.
    @Published var showHistory: Bool = false
    /// The space's notes (⌥⌘N), see `NotesPanel`.
    @Published var showNotes: Bool = false
    /// The note of the current tab, at the right of the page, see `TabNotePanel`.
    /// It shares that place with the tasks: one at a time.
    @Published var showTabNote: Bool = false {
        didSet { if showTabNote { showTasks = false } }
    }

    /// The space's tasks, at the right of the page, see `TasksPanel`.
    @Published var showTasks: Bool = false {
        didSet { if showTasks { showTabNote = false } }
    }
    /// An area of the page to trace for a note, see `AreaCaptureOverlay`.
    @Published var areaCapture: AreaCaptureRequest?
    @Published var launcherSearchText: String = ""
    @Published var showFinderIn: UUID?
    @Published var isFloatingTabSwitchVisible: Bool = false
    @Published var isFullscreen: Bool = false
    @Published var isURLBarEditing: Bool = false
}

@main
struct OraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Shared model container that uses the same configuration as the main browser
    private let sharedModelContainer: ModelContainer? =
        try? ModelConfiguration.createOraContainer(isPrivate: false)

    var body: some Scene {
        WindowGroup(id: "normal") {
            OraRoot()
                .frame(minWidth: 500, minHeight: 360)
                .environmentObject(DefaultBrowserManager.shared)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // Links opened from other apps (Ora as default browser) go to a regular
        // window; SwiftUI creates one if none is open, e.g. on a cold launch.
        .handlesExternalEvents(matching: ["*"])

        WindowGroup("Private", id: "private") {
            OraRoot(isPrivate: true)
                .frame(minWidth: 500, minHeight: 360)
                .environmentObject(DefaultBrowserManager.shared)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: [])

        WindowGroup("Settings", id: "settings") {
            if let sharedModelContainer {
                SettingsWindowRoot()
                    .environmentObject(AppearanceManager.shared)
                    .environmentObject(UpdateService.shared)
                    .environmentObject(DefaultBrowserManager.shared)
                    .modelContainer(sharedModelContainer)
            } else {
                // Fallback UI when SwiftData is completely broken
                VStack {
                    Text("Settings Unavailable")
                        .font(.title)
                }
                .padding()
                .frame(width: 400, height: 300)
            }
        }
        .windowToolbarStyle(UnifiedCompactWindowToolbarStyle())
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 640)
        .handlesExternalEvents(matching: [])
        .commands { OraCommands() }
    }
}
