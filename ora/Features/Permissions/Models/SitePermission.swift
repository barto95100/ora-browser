import Foundation

/// A capability a website can ask the user for.
enum SitePermissionType: String, Codable, CaseIterable, Identifiable {
    case camera
    case microphone

    var id: String {
        rawValue
    }
}

/// The user's choice for a capability on a given site.
enum SitePermissionState: String, Codable, CaseIterable {
    /// Ask the user the next time the site requests it.
    case ask
    case allow
    case deny
}

// MARK: - Site Origin

/// A web origin (scheme, host and port), the unit browsers scope permissions to.
///
/// `http://example.com` and `https://example.com` are distinct origins. A
/// default port (80 for http, 443 for https, or 0 as reported by WebKit) is
/// stored as `nil`, so `https://example.com` and `https://example.com:443`
/// are the same origin.
struct SiteOrigin: Hashable, Codable, Identifiable, CustomStringConvertible {
    let scheme: String
    let host: String
    let port: Int?

    init?(scheme: String, host: String, port: Int?) {
        let scheme = scheme.lowercased()
        let host = host.lowercased()
        guard !scheme.isEmpty, !host.isEmpty else { return nil }

        self.scheme = scheme
        self.host = host
        if let port, port > 0, port != Self.defaultPort(for: scheme) {
            self.port = port
        } else {
            self.port = nil
        }
    }

    init?(url: URL) {
        guard let scheme = url.scheme, let host = url.host(percentEncoded: false) else { return nil }
        self.init(scheme: scheme, host: host, port: url.port)
    }

    /// Parses the canonical string produced by `description`.
    init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url: url)
    }

    var id: String {
        description
    }

    var description: String {
        if let port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// How to show the site to the user: the host alone for regular HTTPS
    /// sites, the full origin otherwise, so an insecure scheme or an unusual
    /// port is visible before granting anything.
    var displayName: String {
        scheme == "https" && port == nil ? host : description
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http": 80
        case "https": 443
        default: nil
        }
    }
}

// MARK: - Site Permissions

/// The permissions granted to one site within one space.
struct SitePermissions: Codable, Hashable {
    var camera: SitePermissionState = .ask
    var microphone: SitePermissionState = .ask

    init(camera: SitePermissionState = .ask, microphone: SitePermissionState = .ask) {
        self.camera = camera
        self.microphone = microphone
    }

    /// Tolerate missing keys so that capabilities added later decode as `.ask`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        camera = try container.decodeIfPresent(SitePermissionState.self, forKey: .camera) ?? .ask
        microphone = try container.decodeIfPresent(SitePermissionState.self, forKey: .microphone) ?? .ask
    }

    subscript(type: SitePermissionType) -> SitePermissionState {
        get {
            switch type {
            case .camera: camera
            case .microphone: microphone
            }
        }
        set {
            switch type {
            case .camera: camera = newValue
            case .microphone: microphone = newValue
            }
        }
    }

    /// Whether nothing has been decided yet for this site.
    var isUndecided: Bool {
        SitePermissionType.allCases.allSatisfy { self[$0] == .ask }
    }

    /// The combined decision for a request covering several capabilities:
    /// denied if any is denied, allowed only if all are allowed, otherwise ask.
    func decision(for types: Set<SitePermissionType>) -> SitePermissionState {
        let states = types.map { self[$0] }
        if states.contains(.deny) {
            return .deny
        }
        if !states.isEmpty, states.allSatisfy({ $0 == .allow }) {
            return .allow
        }
        return .ask
    }
}

// MARK: - Display

extension SitePermissionType {
    var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        }
    }
}

extension SitePermissionState {
    var title: String {
        switch self {
        case .ask: "Ask"
        case .allow: "Allow"
        case .deny: "Don't Allow"
        }
    }
}

// MARK: - Engine Mapping

extension BrowserPermissionKind {
    /// The site permissions a WebKit capture request covers.
    var sitePermissionTypes: Set<SitePermissionType> {
        switch self {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        }
    }
}

extension SitePermissionState {
    /// Answer to `navigator.permissions.query()` for this saved decision.
    var permissionQueryDecision: BrowserPermissionDecision {
        switch self {
        case .allow: .grant
        case .deny: .deny
        case .ask: .prompt
        }
    }
}
