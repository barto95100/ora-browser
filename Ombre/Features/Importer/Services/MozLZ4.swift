import Compression
import Foundation

/// Firefox's and Zen's compressed JSON files (`.jsonlz4`): "mozLz40\0", the
/// decompressed size (4 bytes, little endian), then one LZ4 block.
enum MozLZ4 {
    enum Failure: Error {
        case notMozLZ4
        case corrupted
    }

    private static let magic = Data("mozLz40\0".utf8)

    static func decompress(_ data: Data) throws -> Data {
        guard data.count > 12, data.prefix(8) == magic else { throw Failure.notMozLZ4 }
        let size = data.subdata(in: 8 ..< 12).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        guard size > 0 else { return Data() }
        let block = data.subdata(in: 12 ..< data.count)
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { outputBytes in
            block.withUnsafeBytes { inputBytes -> Int in
                guard let destination = outputBytes.bindMemory(to: UInt8.self).baseAddress,
                      let source = inputBytes.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(destination, size, source, block.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard written == size else { throw Failure.corrupted }
        return output
    }
}
