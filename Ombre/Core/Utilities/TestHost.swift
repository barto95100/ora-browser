import Foundation

/// Whether the app runs as the host of the unit tests (Xcode, `xcodebuild
/// test`, the CI). It then keeps away from the user's data: a database in
/// memory, no browsing window nor first-launch assistant, a separate service
/// in the login keychain (the user's passwords are never read). Under the
/// "Test" build configuration it also has its own bundle identifier, so its
/// preferences and files are in a sandbox container of its own.
enum TestHost {
    nonisolated static let isActive: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()
}
