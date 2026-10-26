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
