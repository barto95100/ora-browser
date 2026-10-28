import AppKit
import Foundation

enum BrowserWebsiteDataType: Hashable {
    case cookies
    case cache
    case all
}

enum BrowserUserScriptInjectionTime {
    case atDocumentStart
    case atDocumentEnd
}

struct BrowserUserScript {
    let name: String?
    let source: String
    let injectionTime: BrowserUserScriptInjectionTime
    let forMainFrameOnly: Bool
}

struct BrowserScriptMessage {
    let name: String
    let body: Any?
}

struct BrowserOpenPanelOptions {
    let allowsDirectories: Bool
    let allowsMultipleSelection: Bool
}

enum BrowserPermissionKind {
    case camera
    case microphone
    case cameraAndMicrophone
    /// Web notifications, see `WebNotificationBridge`.
    case notifications
}

/// A notification a page asked to show (`new Notification(...)`).
struct BrowserWebNotification: Equatable {
    /// Unique within its page.
    let id: String
    let title: String
    let body: String
    /// Notifications of a page sharing a tag replace each other.
    let tag: String?
    let isSilent: Bool
    let origin: URL?
}

/// How a link asked to open in a new tab is shown.
enum BrowserNewTabDisposition {
    case foreground
    case background
    /// Beside the tab it comes from.
    case splitView
}

enum BrowserPermissionDecision {
    case grant
    case deny
    /// Let WebKit ask the user with its own built-in prompt.
    case prompt
}

enum BrowserCaptureDevice: CaseIterable {
    case camera
    case microphone
}

/// Whether a page is using a capture device.
enum BrowserCaptureState: Equatable {
    case none
    case active
    /// Still granted, but paused by the user: the page receives no image/sound.
    case muted
}

struct BrowserMediaCaptureState: Equatable {
    var camera: BrowserCaptureState = .none
    var microphone: BrowserCaptureState = .none

    var isCapturing: Bool {
        camera != .none || microphone != .none
    }

    /// The device a tab's indicator shows: the camera first, it matters more
    /// than the microphone. Nil when nothing is captured.
    var indicatedDevice: BrowserCaptureDevice? {
        BrowserCaptureDevice.allCases.first { self[$0] != .none }
    }

    subscript(device: BrowserCaptureDevice) -> BrowserCaptureState {
        switch device {
        case .camera: camera
        case .microphone: microphone
        }
    }

    /// Whether the device must be muted (true) or resumed (false) to toggle it,
    /// or nil when the page is not using it.
    func mutedAfterToggling(_ device: BrowserCaptureDevice) -> Bool? {
        switch self[device] {
        case .none: nil
        case .active: true
        case .muted: false
        }
    }
}

struct BrowserNavigationAction {
    let request: URLRequest
    let modifierFlags: NSEvent.ModifierFlags
    /// The user clicked a link that loads in the page itself (not a frame,
    /// not a redirect or a script navigation).
    var isMainFrameLinkClick = false
}

enum BrowserNavigationActionDisposition {
    case allow
    case cancel
    case openInNewTab
}

enum BrowserNavigationPhase {
    case started
    case committed
    case finished
}

struct BrowserNavigationEvent {
    let phase: BrowserNavigationPhase
    let url: URL?
    let title: String?
    let progress: Double
    let isLoading: Bool
}

struct BrowserSnapshotConfiguration {
    let rect: CGRect?
    let afterScreenUpdates: Bool

    static let full = BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: false)
}

/// Navigation "failures" that are not errors for the user, like in Safari: no
/// error page for them.
enum BrowserNavigationError {
    /// WebKitErrorFrameLoadInterruptedByPolicyChange: the load was turned into
    /// something else (a download, a new tab...).
    static let frameLoadInterruptedByPolicyChange = 102
    /// WebKitErrorPlugInWillHandleLoad: WebKit shows the resource itself, e.g.
    /// a video or audio file opened directly, in its media player.
    static let plugInWillHandleLoad = 204

    static func isInterruption(_ error: Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSURLErrorDomain:
            return error.code == NSURLErrorCancelled
        case "WebKitErrorDomain":
            return [frameLoadInterruptedByPolicyChange, plugInWillHandleLoad].contains(error.code)
        default:
            return false
        }
    }
}
