import Foundation

extension Tab {
    /// Pauses the device if the page is using it, resumes it if it is paused.
    func toggleCapture(_ device: BrowserCaptureDevice) {
        guard let muted = mediaCaptureState.mutedAfterToggling(device) else { return }
        browserPage?.setCaptureMuted(muted, for: device)
    }

    func updateMediaCaptureState(_ state: BrowserMediaCaptureState) {
        if mediaCaptureState != state {
            mediaCaptureState = state
        }
    }
}
