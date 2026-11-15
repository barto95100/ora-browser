@testable import Ombre
import Testing

/// macOS's sandbox lets the app reach the Picture in Picture service only if
/// Picture in Picture's framework is loaded when the app starts
/// (`PictureInPictureSupport`). The app under test is the same target: its
/// framework must be there before any page asks for Picture in Picture.
struct PictureInPictureSupportTests {
    @Test func theSystemFrameworkIsLoadedAtLaunch() {
        #expect(PictureInPictureSupport.isFrameworkLoaded)
    }

    @Test func picturesInPictureAreSupported() {
        #expect(PictureInPictureSupport.isSupported)
    }
}
