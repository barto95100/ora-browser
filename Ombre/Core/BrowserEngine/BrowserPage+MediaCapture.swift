import Foundation
@preconcurrency import WebKit

extension BrowserPage {
    /// Pauses every media element of the page at once, in WebKit itself (does
    /// not depend on the page's scripts).
    func pauseAllMedia(completion: @escaping @MainActor @Sendable () -> Void) {
        webView.pauseAllMediaPlayback(completionHandler: completion)
    }

    var mediaCaptureState: BrowserMediaCaptureState {
        BrowserMediaCaptureState(
            camera: BrowserCaptureState(webView.cameraCaptureState),
            microphone: BrowserCaptureState(webView.microphoneCaptureState)
        )
    }

    /// Pauses (muted) or resumes a capture device the page is using, like the
    /// camera and microphone buttons of Safari's address bar.
    func setCaptureMuted(_ muted: Bool, for device: BrowserCaptureDevice) {
        let state: WKMediaCaptureState = muted ? .muted : .active
        switch device {
        case .camera:
            guard webView.cameraCaptureState != .none else { return }
            webView.setCameraCaptureState(state, completionHandler: nil)
        case .microphone:
            guard webView.microphoneCaptureState != .none else { return }
            webView.setMicrophoneCaptureState(state, completionHandler: nil)
        }
    }

    /// Pauses the device if the page is using it, resumes it if it is paused.
    func toggleCapture(_ device: BrowserCaptureDevice) {
        guard let muted = mediaCaptureState.mutedAfterToggling(device) else { return }
        setCaptureMuted(muted, for: device)
    }

    /// Called by the capture state observers set up in `init`.
    nonisolated func mediaCaptureStateDidChange() {
        notifyOnMain { $0.delegate?.browserPage($0, didChangeMediaCaptureState: $0.mediaCaptureState) }
    }
}

private extension BrowserCaptureState {
    init(_ state: WKMediaCaptureState) {
        switch state {
        case .active: self = .active
        case .muted: self = .muted
        default: self = .none
        }
    }
}
