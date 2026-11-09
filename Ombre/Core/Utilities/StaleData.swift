import Foundation
import OSLog

/// Data Ombre identified as no longer used, removed at launch: never
/// anything it can't name, each removal logged with the space it frees.
enum StaleData {
    static let logger = Logger(category: "StaleData")

    static var library: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    }

    /// Disk space of a file or folder, its contents included.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// One line per removal, then the total freed.
    static func logRemovals(_ removed: [(name: String, bytes: Int64)], of kind: String) {
        guard !removed.isEmpty else { return }
        for item in removed {
            let size = formatted(item.bytes)
            logger
                .notice(
                    "Removed stale \(kind, privacy: .public) \(item.name, privacy: .public) (\(size, privacy: .public))"
                )
        }
        let total = formatted(removed.reduce(0) { $0 + $1.bytes })
        logger.notice("Stale \(kind, privacy: .public): \(removed.count) removed, \(total, privacy: .public) freed")
    }
}
