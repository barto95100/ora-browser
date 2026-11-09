import Foundation

enum AdBlockUpdateMode: String, CaseIterable, Codable, Identifiable {
    case onLaunchDaily
    case manualOnly
    case aggressiveAuto

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .onLaunchDaily:
            String(localized: "On Launch + Daily")
        case .manualOnly:
            String(localized: "Manual Refresh Only")
        case .aggressiveAuto:
            String(localized: "Aggressive Auto-Refresh")
        }
    }

    var refreshInterval: TimeInterval? {
        switch self {
        case .onLaunchDaily:
            24 * 60 * 60
        case .manualOnly:
            nil
        case .aggressiveAuto:
            6 * 60 * 60
        }
    }
}

enum FilterListSourceKind: String, Codable {
    case builtin
    case custom
}

enum FilterListStatus: String, Codable {
    case idle
    case updating
    case ready
    case failed
}

struct FilterListCoverage: Codable, Equatable, Hashable {
    var totalRuleCount: Int
    var convertedRuleCount: Int
    var skippedRuleCount: Int
    var safariRuleCount: Int
    var shardCount: Int
}

struct FilterListRecord: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var name: String
    var summary: String
    let sourceKind: FilterListSourceKind
    let sourceURL: String
    var isRecommended: Bool
    var enabledByDefault: Bool
    var status: FilterListStatus
    var lastErrorMessage: String?
    var lastFetchAt: Date?
    var lastSuccessfulRefreshAt: Date?
    var etag: String?
    var lastModified: String?
    var activeRevision: String?
    var coverage: FilterListCoverage?

    init(
        id: String,
        name: String,
        summary: String,
        sourceKind: FilterListSourceKind,
        sourceURL: String,
        isRecommended: Bool,
        enabledByDefault: Bool,
        status: FilterListStatus = .idle,
        lastErrorMessage: String? = nil,
        lastFetchAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        activeRevision: String? = nil,
        coverage: FilterListCoverage? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sourceKind = sourceKind
        self.sourceURL = sourceURL
        self.isRecommended = isRecommended
        self.enabledByDefault = enabledByDefault
        self.status = status
        self.lastErrorMessage = lastErrorMessage
        self.lastFetchAt = lastFetchAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.etag = etag
        self.lastModified = lastModified
        self.activeRevision = activeRevision
        self.coverage = coverage
    }

    var isBuiltin: Bool {
        sourceKind == .builtin
    }
}

struct SpaceAdBlockSettings: Codable, Equatable, Hashable {
    var enabled: Bool
    var enabledBuiltinListIDs: [String]
    var enabledCustomListIDs: [String]
    var updateMode: AdBlockUpdateMode

    init(
        enabled: Bool = false,
        enabledBuiltinListIDs: [String] = FilterListCatalogService.defaultBuiltinSelectionIDs,
        enabledCustomListIDs: [String] = [],
        updateMode: AdBlockUpdateMode = .onLaunchDaily
    ) {
        self.enabled = enabled
        self.enabledBuiltinListIDs = Self.normalized(enabledBuiltinListIDs)
        self.enabledCustomListIDs = Self.normalized(enabledCustomListIDs)
        self.updateMode = updateMode
    }

    var enabledListIDs: [String] {
        enabledBuiltinListIDs + enabledCustomListIDs
    }

    func isEnabled(_ record: FilterListRecord) -> Bool {
        switch record.sourceKind {
        case .builtin:
            enabledBuiltinListIDs.contains(record.id)
        case .custom:
            enabledCustomListIDs.contains(record.id)
        }
    }

    mutating func setEnabled(_ isEnabled: Bool, for record: FilterListRecord) {
        switch record.sourceKind {
        case .builtin:
            if isEnabled {
                enabledBuiltinListIDs = Self.normalized(enabledBuiltinListIDs + [record.id])
            } else {
                enabledBuiltinListIDs.removeAll { $0 == record.id }
            }
        case .custom:
            if isEnabled {
                enabledCustomListIDs = Self.normalized(enabledCustomListIDs + [record.id])
            } else {
                enabledCustomListIDs.removeAll { $0 == record.id }
            }
        }
    }

    mutating func removeCustomList(id: String) {
        enabledCustomListIDs.removeAll { $0 == id }
    }

    private static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum AdBlockServiceError: LocalizedError {
    case invalidCustomListURL
    case invalidFilterResponse
    case downloadFailed(statusCode: Int)
    case missingCachedList(String)
    case emptyFilterList(String)
    /// The bytes announced or received when the download stopped.
    case filterListTooLarge(bytes: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidCustomListURL:
            String(localized: "Filter lists must use an https:// address.")
        case .invalidFilterResponse:
            String(localized: "The filter list response could not be read.")
        case let .downloadFailed(statusCode):
            String(localized: "The filter list download failed with status \(statusCode).")
        case let .missingCachedList(name):
            String(localized: "No cached filter rules are available for \(name).")
        case let .emptyFilterList(name):
            String(localized: "No WebKit-compatible rules were produced for \(name).")
        case .filterListTooLarge:
            String(localized: "The filter list is larger than 32 MB: Ombre doesn't download it.")
        }
    }

    /// Why a list's update failed, for the log: the HTTP status, the size,
    /// the network error's code (never the list's content).
    static func logReason(for error: Error) -> String {
        switch error {
        case let AdBlockServiceError.downloadFailed(statusCode):
            return "HTTP \(statusCode)" // not shown
        case let AdBlockServiceError.filterListTooLarge(bytes):
            let limit = FilterListUpdateService.maxListSize
            return "larger than \(limit) bytes (\(bytes) bytes announced or received)" // not shown
        case let error as URLError:
            return "network error \(error.code.rawValue)" // not shown
        case let error as AdBlockServiceError:
            // The case only: a custom list's name is the user's.
            return "\(error)".components(separatedBy: "(").first ?? "AdBlockServiceError" // not shown
        default:
            // Domain and code only: a file error's text holds its path.
            let error = error as NSError
            return "\(error.domain) \(error.code)"
        }
    }
}
