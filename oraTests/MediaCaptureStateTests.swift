@testable import Ora
import Testing

struct MediaCaptureStateTests {
    @Test func nothingCapturedByDefault() {
        let state = BrowserMediaCaptureState()

        #expect(!state.isCapturing)
        #expect(state.mutedAfterToggling(.camera) == nil)
        #expect(state.mutedAfterToggling(.microphone) == nil)
    }

    @Test func togglingAnActiveDevicePausesIt() {
        let state = BrowserMediaCaptureState(camera: .active, microphone: .none)

        #expect(state.isCapturing)
        #expect(state.mutedAfterToggling(.camera) == true)
        #expect(state.mutedAfterToggling(.microphone) == nil)
    }

    @Test func togglingAPausedDeviceResumesIt() {
        let state = BrowserMediaCaptureState(camera: .active, microphone: .muted)

        #expect(state.isCapturing)
        #expect(state.mutedAfterToggling(.microphone) == false)
    }

    @Test func aPausedDeviceStillCountsAsCapturing() {
        let state = BrowserMediaCaptureState(camera: .muted, microphone: .none)

        #expect(state.isCapturing)
    }

    @Test func theIndicatorShowsTheCameraFirst() {
        #expect(BrowserMediaCaptureState().indicatedDevice == nil)
        #expect(BrowserMediaCaptureState(camera: .none, microphone: .active).indicatedDevice == .microphone)
        #expect(BrowserMediaCaptureState(camera: .muted, microphone: .active).indicatedDevice == .camera)
    }
}
