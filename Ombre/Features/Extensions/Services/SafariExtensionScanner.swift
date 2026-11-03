import Foundation

/// Finds the Safari extensions brought by installed apps (from the App Store,
/// like Safari): `.appex` bundles of the Safari web extension point in the
/// apps of /Applications and ~/Applications.
enum SafariExtensionScanner {
    static let extensionPoint = "com.apple.Safari.web-extension"

    static var applicationFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            RealHome.url.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    static func scan(folders: [URL] = applicationFolders) -> [SafariExtensionCandidate] {
        let fileManager = FileManager.default
        var found: [SafariExtensionCandidate] = []
        for folder in folders {
            let apps = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                found += candidates(inApp: app)
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func candidates(inApp app: URL) -> [SafariExtensionCandidate] {
        let plugIns = app.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        let bundles = (try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? []
        let appName = displayName(ofBundleAt: app) ?? app.deletingPathExtension().lastPathComponent
        return bundles.compactMap { appex in
            guard appex.pathExtension == "appex",
                  let info = NSDictionary(contentsOf: appex.appendingPathComponent("Contents/Info.plist"))
                  as? [String: Any],
                  isWebExtension(info: info),
                  let identifier = info["CFBundleIdentifier"] as? String
            else { return nil }
            return SafariExtensionCandidate(
                appexURL: appex,
                bundleIdentifier: identifier,
                name: name(info: info) ?? appName,
                appName: appName,
                appURL: app
            )
        }
    }

    /// Whether an `.appex`'s Info.plist is a Safari web extension.
    static func isWebExtension(info: [String: Any]) -> Bool {
        let point = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        return point == extensionPoint
    }

    static func name(info: [String: Any]) -> String? {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info[key] as? String, !name.isEmpty { return name }
        }
        return nil
    }

    private static func displayName(ofBundleAt url: URL) -> String? {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            as? [String: Any]
        else { return nil }
        return name(info: info)
    }
}
