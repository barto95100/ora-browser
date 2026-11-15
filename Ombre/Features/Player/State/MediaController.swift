import Foundation
import SwiftUI

@MainActor
final class MediaController: ObservableObject {
    struct Session: Identifiable, Equatable {
        var id: UUID {
            tabID
        }

        var tabID: UUID
        var title: String
        var pageURL: URL
        var favicon: URL?
        var isPlaying: Bool
        var volume: Double
        var canGoNext: Bool
        var canGoPrevious: Bool
        var lastActive: Date
        var wasPlayed: Bool
    }

    // Published list of sessions ordered by recency (most recent first)
    @Published private(set) var sessions: [Session] = []
    @Published var isVisible: Bool = false

    /// Weak references to tabs by id so we can run JS in the right webview
    private final class WeakTab { weak var value: Tab?
        init(_ value: Tab?) {
            self.value = value
        }
    }

    private var tabRefs: [UUID: WeakTab] = [:]

    /// Tabs whose video is in Picture in Picture. Their page must stay attached
    /// to the window (see `ParkedBrowserPageView`), otherwise WebKit cannot
    /// bring the video back when the user clicks "back to tab".
    @Published private(set) var pictureInPictureTabIDs: Set<UUID> = []
    private var pictureInPictureTabRefs: [UUID: WeakTab] = [:]
    /// The last request to go to Picture in Picture, by tab.
    private var pictureInPictureRequests: [UUID: UUID] = [:]
    /// The tab manager of the window this controller belongs to (set by it).
    weak var tabManager: TabManager?

    // MARK: - Public accessors

    var primary: Session? {
        visibleSessions.first
    }

    var visibleSessions: [Session] {
        sessions.filter(\.wasPlayed)
    }

    // MARK: - Receive events from JS bridge

    func receive(event: MediaEventPayload, from tab: Tab) {
        tabRefs[tab.id] = WeakTab(tab)

        switch event.type {
        case "pip":
            if event.state == "entered" {
                tab.browserPage?.log("picture in picture entered")
                // Confirmed: no longer waited for (see `pictureInPictureNotEntered`).
                pictureInPictureRequests[tab.id] = nil
                pictureInPictureTabRefs[tab.id] = WeakTab(tab)
                pictureInPictureTabIDs.insert(tab.id)
            } else {
                if event.state == "failed" {
                    tab.browserPage?.log("picture in picture refused (\(event.error ?? "?"))")
                } else if pictureInPictureTabIDs.contains(tab.id) {
                    tab.browserPage?.log("picture in picture left")
                }
                guard pictureInPictureTabIDs.contains(tab.id) else { break }
                pictureInPictureRequests[tab.id] = nil
                pictureInPictureTabRefs[tab.id] = nil
                pictureInPictureTabIDs.remove(tab.id)
            }
        case "pipReturn":
            returnToTab(tab)
        default:
            receive(
                event: event,
                tabID: tab.id,
                title: tab.title,
                pageURL: tab.url,
                // A private icon lives in memory, not at an address the
                // player can load.
                favicon: tab.faviconLocalFile.flatMap { $0.scheme == FaviconStore.privateScheme ? nil : $0 }
                    ?? (tab.isPrivate ? nil : tab.favicon)
            )
        }
    }

    /// Session state for a media event, without the tab itself (testable).
    /// The tab's `isPlayingMedia` is updated when the tab is known.
    func receive(event: MediaEventPayload, tabID id: UUID, title: String, pageURL: URL, favicon: URL?) {
        func ensureSession() -> Int {
            if let idx = sessions.firstIndex(where: { $0.tabID == id }) { return idx }
            let session = Session(
                tabID: id,
                title: title,
                pageURL: pageURL,
                favicon: favicon,
                isPlaying: false,
                volume: 1.0,
                canGoNext: false,
                canGoPrevious: false,
                lastActive: Date(),
                wasPlayed: false
            )
            sessions.insert(session, at: 0)
            return 0
        }

        switch event.type {
        case "state":
            let idx = ensureSession()
            let playing = (event.state == "playing")
            sessions[idx].isPlaying = playing
            // Update tab's isPlayingMedia property (published: only on change)
            if let trackedTab = tabRefs[id]?.value, trackedTab.isPlayingMedia != playing {
                trackedTab.isPlayingMedia = playing
            }
            if let vol = event.volume { sessions[idx].volume = clamp(vol) }
            // Update recency when it starts playing
            if playing { sessions[idx].lastActive = Date()
                moveToFront(index: idx)
            }
            if let wasPlayed = event.wasPlayed { sessions[idx].wasPlayed = wasPlayed }

        case "volume":
            if let idx = sessions.firstIndex(where: { $0.tabID == id }), let vol = event.volume {
                sessions[idx].volume = clamp(vol)
            }

        case "caps":
            if let idx = sessions.firstIndex(where: { $0.tabID == id }) {
                let canGoNext = event.hasNext ?? sessions[idx].canGoNext
                let canGoPrevious = event.hasPrevious ?? sessions[idx].canGoPrevious
                // Don't republish identical values: every write to `sessions`
                // re-renders the sidebar.
                if sessions[idx].canGoNext != canGoNext || sessions[idx].canGoPrevious != canGoPrevious {
                    sessions[idx].canGoNext = canGoNext
                    sessions[idx].canGoPrevious = canGoPrevious
                }
            }

        case "ended":
            if let idx = sessions.firstIndex(where: { $0.tabID == id }) {
                sessions[idx].isPlaying = false
                // Update tab's isPlayingMedia property
                tabRefs[id]?.value?.isPlayingMedia = false
            }

        case "removed":
            removeSession(for: id)

        default:
            break
        }

        updateVisibility()
    }

    // MARK: - Controls (per session, default to primary)

    func togglePlayPause(_ tabID: UUID? = nil) {
        guard let id = tabID ?? primary?.tabID else { return }
        eval(id, "window.__media && window.__media.toggle && window.__media.toggle()") // no translation
        if let idx = sessions.firstIndex(where: { $0.tabID == id }) {
            sessions[idx].isPlaying.toggle()
        }
    }

    func nextTrack(_ tabID: UUID? = nil) {
        guard let id = tabID ?? primary?.tabID else { return }
        // The new title arrives through the page's title change.
        eval(id, "window.__media && window.__media.next && window.__media.next()") // no translation
    }

    func previousTrack(_ tabID: UUID? = nil) {
        guard let id = tabID ?? primary?.tabID else { return }
        eval(id, "window.__media && window.__media.previous && window.__media.previous()") // no translation
    }

    func setVolume(for tabID: UUID? = nil, _ value: Double) {
        guard let id = tabID ?? primary?.tabID else { return }
        let clampedVolume = clamp(value)
        if let idx = sessions.firstIndex(where: { $0.tabID == id }) { sessions[idx].volume = clampedVolume }
        eval(
            id,
            "window.__media && window.__media.setVolume && window.__media.setVolume(\(clampedVolume))" // no translation
        )
    }

    func volumeDelta(for tabID: UUID? = nil, _ delta: Double) {
        guard let id = tabID ?? primary?.tabID else { return }
        if let idx = sessions.firstIndex(where: { $0.tabID == id }) {
            sessions[idx].volume = clamp(sessions[idx].volume + delta)
        }
        eval(
            id,
            "window.__media && window.__media.deltaVolume && window.__media.deltaVolume(\(delta))" // no translation
        )
    }

    func closeSession(_ tabID: UUID? = nil) {
        guard let id = tabID ?? primary?.tabID else { return }
        eval(id, "window.__media && window.__media.pause && window.__media.pause()") // no translation
        if let idx = sessions.firstIndex(where: { $0.tabID == id }) {
            sessions.remove(at: idx)
        }
        // Update tab's isPlayingMedia property
        tabRefs[id]?.value?.isPlayingMedia = false
        tabRefs[id] = nil
        updateVisibility()
    }

    func removeSession(for tabID: UUID) {
        if let idx = sessions.firstIndex(where: { $0.tabID == tabID }) {
            sessions.remove(at: idx)
        }
        pictureInPictureRequests[tabID] = nil
        pictureInPictureTabRefs[tabID] = nil
        pictureInPictureTabIDs.remove(tabID)
        // Update tab's isPlayingMedia property
        tabRefs[tabID]?.value?.isPlayingMedia = false
        tabRefs[tabID] = nil
        updateVisibility()
    }

    /// Helpers
    func volume(of tabID: UUID) -> Double {
        sessions.first(where: { $0.tabID == tabID })?.volume ?? 1.0
    }

    func canGoNext(of tabID: UUID) -> Bool {
        sessions.first(where: { $0.tabID == tabID })?.canGoNext ?? false
    }

    func canGoPrevious(of tabID: UUID) -> Bool {
        sessions.first(where: { $0.tabID == tabID })?.canGoPrevious ?? false
    }

    // MARK: - Private

    private func moveToFront(index: Int) {
        guard index < sessions.count else { return }
        let session = sessions.remove(at: index)
        sessions.insert(session, at: 0)
    }

    private func eval(_ tabID: UUID, _ javaScript: String) {
        tabRefs[tabID]?.value?.evaluateJavaScript(javaScript)
    }

    /// The tab's video is asked to go to Picture in Picture: its page is kept
    /// in the window from now on, as when it is in Picture in Picture.
    /// Returns the request, to tell its answer from a later request's.
    @discardableResult
    func pictureInPictureWillStart(for tab: Tab) -> UUID {
        let request = UUID()
        pictureInPictureRequests[tab.id] = request
        pictureInPictureTabRefs[tab.id] = WeakTab(tab)
        pictureInPictureTabIDs.insert(tab.id)
        return request
    }

    /// The page had no video to put in Picture in Picture for `request` (a
    /// later request of the tab keeps its page).
    func pictureInPictureDidNotStart(for tab: Tab, request: UUID) {
        guard pictureInPictureRequests[tab.id] == request, pictureInPictureTabIDs.contains(tab.id) else { return }
        pictureInPictureRequests[tab.id] = nil
        pictureInPictureTabRefs[tab.id] = nil
        pictureInPictureTabIDs.remove(tab.id)
    }

    /// Picture in Picture asked for `request` was still not confirmed after
    /// `pictureInPictureEntryDeadline`: macOS refused it without a word (its
    /// service unreachable), and the video showed "in Picture in Picture"
    /// with no window. The video is put back in the page.
    func pictureInPictureNotEntered(for tab: Tab, request: UUID) {
        guard pictureInPictureRequests[tab.id] == request else { return }
        tab.browserPage?.log("picture in picture not entered in 3 s, video put back in the page")
        if let page = tab.browserPage {
            page.evaluateJavaScript("document.pictureInPictureElement && document.exitPictureInPicture(); true")
            page.closeMediaPresentations {}
        }
        pictureInPictureRequests[tab.id] = nil
        pictureInPictureTabRefs[tab.id] = nil
        pictureInPictureTabIDs.remove(tab.id)
    }

    static let pictureInPictureEntryDeadline: TimeInterval = 3

    /// Tabs in Picture in Picture whose page is loaded, except `excludedTabID`
    /// (the tab currently displayed, whose page is already in the window).
    func pictureInPictureTabs(excluding excludedTabID: UUID?) -> [Tab] {
        pictureInPictureTabIDs
            .filter { $0 != excludedTabID }
            .compactMap { pictureInPictureTabRefs[$0]?.value }
            .filter { $0.browserPage != nil }
    }

    /// "Back to tab" in the Picture in Picture window: like Safari, show the
    /// tab the video belongs to. Its page is not displayed otherwise, so the
    /// video would come back into a hidden page.
    private func returnToTab(_ tab: Tab) {
        // Same path as the mini player's "go to tab" button: it also switches
        // to the tab's space.
        guard let tabManager else { return }
        tabManager.activateTab(id: tab.id)
        NSApp.activate()
        DispatchQueue.main.async {
            tab.pageWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func updateVisibility() {
        let visible = !visibleSessions.isEmpty
        if isVisible != visible {
            isVisible = visible
        }
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    // MARK: - Title sync helpers

    /// Called on every title change of the page (WebKit notification): no
    /// polling needed to keep the mini player's title up to date.
    func syncTitleForTab(_ tabID: UUID, newTitle: String) {
        if let idx = sessions.firstIndex(where: { $0.tabID == tabID }), sessions[idx].title != newTitle {
            sessions[idx].title = newTitle
        }
    }
}

/// Payload from injected JS
struct MediaEventPayload: Codable {
    let type: String
    let wasPlayed: Bool?
    let state: String?
    let volume: Double?
    let title: String?
    let hasNext: Bool?
    let hasPrevious: Bool?
    /// Why the page's request was refused (a DOMException's name).
    var error: String?
}
