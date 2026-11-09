import Compression
import Foundation

/// Reads the files of a zip archive in memory (stored or deflated), so an
/// export is never unpacked on disk. Enough for the archives browsers export:
/// no ZIP64, no encryption, bounded sizes.
enum ZipReader {
    enum Failure: Error, Equatable {
        case notAZip
        case unsupported
        case tooLarge
        case damaged
    }

    struct Entry: Equatable {
        let path: String
        let data: Data
    }

    /// One file at most, and all of them: an export is a few megabytes.
    static let maxFileSize = 64 * 1024 * 1024
    static let maxTotalSize = 128 * 1024 * 1024
    static let maxEntries = 2000

    /// The archive's files, folders and macOS's `__MACOSX` copies left out;
    /// only those `shouldRead` accepts are unpacked (the others never are).
    static func entries(of archive: Data, shouldRead: (String) -> Bool = { _ in true }) throws -> [Entry] {
        let bytes = [UInt8](archive)
        let end = try endOfCentralDirectory(in: bytes)
        let count = Int(bytes.uint16(at: end + 10))
        var offset = Int(bytes.uint32(at: end + 16))
        guard count <= maxEntries else { throw Failure.tooLarge }

        var entries: [Entry] = []
        var total = 0
        for _ in 0 ..< count {
            guard offset + 46 <= bytes.count, bytes.uint32(at: offset) == 0x02014B50 else { throw Failure.damaged }
            let flags = bytes.uint16(at: offset + 8)
            let method = bytes.uint16(at: offset + 10)
            let compressedSize = Int(bytes.uint32(at: offset + 20))
            let size = Int(bytes.uint32(at: offset + 24))
            let nameLength = Int(bytes.uint16(at: offset + 28))
            let extraLength = Int(bytes.uint16(at: offset + 30))
            let commentLength = Int(bytes.uint16(at: offset + 32))
            let localOffset = Int(bytes.uint32(at: offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw Failure.damaged }
            let path = String(decoding: bytes[offset + 46 ..< offset + 46 + nameLength], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            if path.hasSuffix("/") || path.hasPrefix("__MACOSX/") || !shouldRead(path) { continue }
            // Encrypted, or sizes kept for ZIP64.
            guard flags & 1 == 0, size != 0xFFFFFFFF, compressedSize != 0xFFFFFFFF else {
                throw Failure.unsupported
            }
            guard size <= maxFileSize else { throw Failure.tooLarge }
            total += size
            guard total <= maxTotalSize else { throw Failure.tooLarge }

            let data = try fileData(
                in: bytes, localOffset: localOffset, method: method,
                compressedSize: compressedSize, size: size
            )
            entries.append(Entry(path: path, data: data))
        }
        return entries
    }

    private static func endOfCentralDirectory(in bytes: [UInt8]) throws -> Int {
        guard bytes.count >= 22 else { throw Failure.notAZip }
        // The record is at the end, after a comment of 65,535 bytes at most.
        let lowest = max(0, bytes.count - 22 - 65535)
        var index = bytes.count - 22
        while index >= lowest {
            if bytes.uint32(at: index) == 0x06054B50 { return index }
            index -= 1
        }
        throw Failure.notAZip
    }

    private static func fileData(
        in bytes: [UInt8], localOffset: Int, method: UInt16, compressedSize: Int, size: Int
    ) throws -> Data {
        guard localOffset + 30 <= bytes.count, bytes.uint32(at: localOffset) == 0x04034B50 else {
            throw Failure.damaged
        }
        let start = localOffset + 30 + Int(bytes.uint16(at: localOffset + 26)) + Int(bytes.uint16(at: localOffset + 28))
        guard start + compressedSize <= bytes.count else { throw Failure.damaged }
        let stored = bytes[start ..< start + compressedSize]

        switch method {
        case 0:
            guard compressedSize == size else { throw Failure.damaged }
            return Data(stored)
        case 8:
            return try inflate(Array(stored), size: size)
        default:
            throw Failure.unsupported
        }
    }

    /// Raw deflate (what zip stores), to exactly `size` bytes.
    private static func inflate(_ input: [UInt8], size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !input.isEmpty else { throw Failure.damaged }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(
                    destination.baseAddress!, size,
                    source.baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.damaged }
        return Data(output)
    }
}

private extension [UInt8] {
    func uint16(at index: Int) -> UInt16 {
        guard index + 1 < count else { return 0 }
        return UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }

    func uint32(at index: Int) -> UInt32 {
        guard index + 3 < count else { return 0 }
        return UInt32(self[index]) | UInt32(self[index + 1]) << 8
            | UInt32(self[index + 2]) << 16 | UInt32(self[index + 3]) << 24
    }
}
