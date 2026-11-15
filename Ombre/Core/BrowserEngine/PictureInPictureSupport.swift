import AVKit
import Foundation
import WebKit

/// Picture in Picture needs macOS's Picture in Picture service (PIPAgent).
/// The app sandbox lets an app reach it only if Picture in Picture's
/// framework was loaded when the sandbox started (a rule of macOS's
/// `frameworks.sb`). WebKit loads it later, on the first Picture in Picture:
/// the sandbox refused, and the video stayed "in Picture in Picture" with no
/// window. AVKit, public, loads it at launch: the app links it (`project.yml`)
/// and uses it here, so that the linker keeps it. The Debug build got it from
/// Xcode's preview support, which hid the problem.
enum PictureInPictureSupport {
    static let frameworkPath = "/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP"

    /// Whether Picture in Picture's framework is in the process: only looked
    /// up, never loaded.
    static var isFrameworkLoaded: Bool {
        guard let handle = dlopen(frameworkPath, RTLD_NOLOAD | RTLD_LAZY) else { return false }
        dlclose(handle)
        return true
    }

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// Once at launch, before any page asked for it: whether pages can have
    /// Picture in Picture, in the log.
    @MainActor
    static func logAtLaunch() {
        let setting = PictureInPicturePreference.isAvailable(in: WKPreferences())
        let loaded = isFrameworkLoaded
        PageLog.notice("picture in picture: setting \(setting), framework \(loaded), supported \(isSupported)")
    }
}
