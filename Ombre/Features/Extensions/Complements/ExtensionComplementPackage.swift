import Compression
import Foundation
import os.log

private let logger = Logger(category: "ExtensionComplements")

/// Ombre's complement in its own copy of an extension (Chrome Web Store,
/// folder, zip) whose background is a service worker: a page script can't
/// reach a worker. Done after the package's signature was checked (the
/// original is what is verified), never to an extension from an app.
///
/// The worker gets the complement first (`ExtensionComplementScript.workerSource`),
/// then its own script; the manifest gets "nativeMessaging", the only way
/// out of a worker, which reaches Ombre's channel only
/// (`ExtensionComplements`). Nothing else of the package changes, and only
/// an extension that asks for an added API gets it.
enum ExtensionComplementPackage {
    static let folder = "ombre-complement"
    /// Beside the extension's own worker: its relative addresses
    /// (`importScripts("lib.js")`, `fetch("rules.json")`) stay right.
    static let wrapperName = "ombre-complement-worker.js"
    /// The manifest says what Ombre added, for the complement to hide it
    /// from the extension (`permissions.contains`).
    static let addedPermissionsKey = "ombre_added_permissions"
    /// The user allowed its user scripts ("Allow User Scripts"): read by the
    /// complement when it starts, the only thing it reads at once in a worker.
    /// Ombre checks again at every call: this only defines the API or not.
    static let userScriptsAllowedKey = "ombre_user_scripts_allowed"
    static let complementFile = "\(folder)/complement.js"
    /// What Ombre added: `{"apis": […], "permissions": […]}`.
    static let addedFile = "\(folder)/added.json"

    struct Added: Codable, Equatable {
        var apis: [String]
        var permissions: [String]
    }

    enum Failure: Error {
        case unreadable
    }

    struct Changes {
        let manifest: Data
        let files: [String: Data]
        let added: Added
    }

    /// The new manifest and files, if the extension needs them.
    static func changes(forManifest data: Data) -> Changes? {
        guard var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              manifest["manifest_version"] as? Int == 3,
              var background = manifest["background"] as? [String: Any],
              let worker = background["service_worker"] as? String,
              URL(fileURLWithPath: worker).lastPathComponent != wrapperName
        else { return nil }
        var permissions = (manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        let optional = (manifest["optional_permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        let apis = ExtensionComplementScript.permissions.intersection(permissions + optional).sorted()
        guard !apis.isEmpty else { return nil }

        var added = Added(apis: apis, permissions: [])
        if !permissions.contains("nativeMessaging") {
            permissions.append("nativeMessaging")
            added.permissions.append("nativeMessaging")
        }
        manifest["permissions"] = permissions
        if !added.permissions.isEmpty { manifest[addedPermissionsKey] = added.permissions }
        let path = worker.trimmingCharacters(in: ["/"])
        let name = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        let wrapperPath = directory.isEmpty ? wrapperName : directory + "/" + wrapperName
        let isModule = background["type"] as? String == "module"
        // As JavaScript strings, whatever the names hold.
        guard let complement = jsString("/" + complementFile), let own = jsString(isModule ? "./" + name : name)
        else { return nil }
        let wrapper = isModule
            ? "import \(complement);\nimport \(own);\n" // not shown
            : "importScripts(\(complement), \(own));\n" // not shown
        background["service_worker"] = wrapperPath
        manifest["background"] = background
        guard let newManifest = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]),
              let addedData = try? JSONEncoder().encode(added)
        else { return nil }
        return Changes(manifest: newManifest, files: [
            wrapperPath: Data(wrapper.utf8),
            complementFile: Data(ExtensionComplementScript.workerSource.utf8),
            addedFile: addedData
        ], added: added)
    }

    private static func jsString(_ text: String) -> String? {
        (try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
            .flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// Adds it to an unpacked copy. What was added, if anything.
    @discardableResult
    static func add(toFolder url: URL) -> Added? {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let changes = changes(forManifest: data) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true
            )
            for (path, content) in changes.files {
                try content.write(to: url.appendingPathComponent(path), options: .atomic)
            }
            try changes.manifest.write(to: manifestURL, options: .atomic)
            return changes.added
        } catch {
            logger.error("Complement not added: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Adds it to a `.zip` copy, its other files copied as they are.
    @discardableResult
    static func add(toZip url: URL) -> Added? {
        guard let data = try? Data(contentsOf: url),
              let archive = try? ZipArchive(data),
              let manifest = archive.entry(named: "manifest.json"),
              let manifestData = try? archive.contents(of: manifest),
              let changes = changes(forManifest: manifestData)
        else { return nil }
        var files = changes.files
        files["manifest.json"] = changes.manifest
        do {
            try archive.replacing(files).write(to: url, options: .atomic)
            return changes.added
        } catch {
            logger.error("Complement not added: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The manifest with "Allow User Scripts" as `allowed`; nil if it is already.
    static func manifest(_ data: Data, allowingUserScripts allowed: Bool) -> Data? {
        guard var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (manifest[userScriptsAllowedKey] as? Bool == true) != allowed
        else { return nil }
        manifest[userScriptsAllowedKey] = allowed ? true : nil
        return try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
    }

    /// Writes "Allow User Scripts" in a copy that has the complement for
    /// them. Whether its manifest changed.
    @discardableResult
    static func setUserScriptsAllowed(_ allowed: Bool, at path: String) -> Bool {
        guard added(at: path)?.apis.contains("userScripts") == true else { return false }
        let url = URL(fileURLWithPath: path)
        do {
            if path.hasSuffix(".zip") {
                let archive = try ZipArchive(Data(contentsOf: url))
                guard let entry = archive.entry(named: "manifest.json"),
                      let changed = try manifest(archive.contents(of: entry), allowingUserScripts: allowed)
                else { return false }
                try archive.replacing(["manifest.json": changed]).write(to: url, options: .atomic)
            } else {
                let manifestURL = url.appendingPathComponent("manifest.json")
                guard let changed = try manifest(Data(contentsOf: manifestURL), allowingUserScripts: allowed)
                else { return false }
                try changed.write(to: manifestURL, options: .atomic)
            }
            return true
        } catch {
            logger.error("User scripts setting not written: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// What Ombre added to this copy (Settings › Extensions says it).
    static func added(at path: String) -> Added? {
        let url = URL(fileURLWithPath: path)
        let data: Data? = if path.hasSuffix(".zip") {
            (try? Data(contentsOf: url)).flatMap { try? ZipArchive($0) }.flatMap { archive in
                archive.entry(named: addedFile).flatMap { try? archive.contents(of: $0) }
            }
        } else {
            try? Data(contentsOf: url.appendingPathComponent(addedFile))
        }
        return data.flatMap { try? JSONDecoder().decode(Added.self, from: $0) }
    }
}

/// Just enough of the zip format to replace a few files of an archive:
/// entries are copied as they are (never recompressed), new ones stored.
/// No Zip64: such an archive is left alone.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let size: UInt32
        let localOffset: UInt32
        /// Its central directory record, as written.
        let central: Data
    }

    enum Failure: Error {
        case invalid
    }

    let data: Data
    let entries: [Entry]
    private let centralOffset: Int

    init(_ data: Data) throws {
        let data = Data(data)
        self.data = data
        guard data.count >= 22 else { throw Failure.invalid }
        // The end record, from the end (a comment may follow it).
        var end = -1
        var position = data.count - 22
        while position >= max(0, data.count - 22 - 65535) {
            if data.uint32(at: position) == 0x06054B50 { end = position
                break
            }
            position -= 1
        }
        guard end >= 0 else { throw Failure.invalid }
        let count = Int(data.uint16(at: end + 10))
        let offset = Int(data.uint32(at: end + 16))
        guard offset != 0xFFFFFFFF, count != 0xFFFF, offset < data.count else { throw Failure.invalid }
        centralOffset = offset
        var entries: [Entry] = []
        var cursor = offset
        for _ in 0 ..< count {
            guard cursor + 46 <= data.count, data.uint32(at: cursor) == 0x02014B50 else { throw Failure.invalid }
            let nameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            let length = 46 + nameLength + extraLength + commentLength
            guard cursor + length <= data.count else { throw Failure.invalid }
            let entry = Entry(
                name: String(bytes: data[(cursor + 46) ..< (cursor + 46 + nameLength)], encoding: .utf8) ?? "",
                method: data.uint16(at: cursor + 10),
                crc: data.uint32(at: cursor + 16),
                compressedSize: data.uint32(at: cursor + 20),
                size: data.uint32(at: cursor + 24),
                localOffset: data.uint32(at: cursor + 42),
                central: data[cursor ..< (cursor + length)]
            )
            guard entry.compressedSize != 0xFFFFFFFF, entry.size != 0xFFFFFFFF,
                  entry.localOffset != 0xFFFFFFFF
            else { throw Failure.invalid }
            entries.append(entry)
            cursor += length
        }
        self.entries = entries
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// Its file, uncompressed (stored or deflated).
    func contents(of entry: Entry) throws -> Data {
        let local = Int(entry.localOffset)
        guard local + 30 <= data.count, data.uint32(at: local) == 0x04034B50 else { throw Failure.invalid }
        let start = local + 30 + Int(data.uint16(at: local + 26)) + Int(data.uint16(at: local + 28))
        let end = start + Int(entry.compressedSize)
        guard end <= data.count else { throw Failure.invalid }
        let stored = data[start ..< end]
        switch entry.method {
        case 0:
            return Data(stored)
        case 8:
            guard entry.size > 0 else { return Data() }
            guard entry.size < 64 << 20 else { throw Failure.invalid }
            var output = Data(count: Int(entry.size))
            let input = Data(stored)
            let written = output.withUnsafeMutableBytes { out -> Int in
                input.withUnsafeBytes { source -> Int in
                    guard let destination = out.bindMemory(to: UInt8.self).baseAddress,
                          let bytes = source.bindMemory(to: UInt8.self).baseAddress
                    else { return 0 }
                    return compression_decode_buffer(
                        destination, Int(entry.size), bytes, input.count, nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == Int(entry.size) else { throw Failure.invalid }
            return output
        default:
            throw Failure.invalid
        }
    }

    /// The archive with `files` in place of (or beside) its own.
    func replacing(_ files: [String: Data]) throws -> Data {
        var output = Data()
        var central = Data()
        var count = 0
        // Each entry's record runs up to the next one (its data descriptor too).
        let starts = (entries.map { Int($0.localOffset) } + [centralOffset]).sorted()
        for entry in entries where files[entry.name] == nil {
            let start = Int(entry.localOffset)
            guard let end = starts.first(where: { $0 > start }), end <= data.count else { throw Failure.invalid }
            var record = Data(entry.central)
            record.setUInt32(UInt32(output.count), at: 42)
            central.append(record)
            output.append(data[start ..< end])
            count += 1
        }
        for (name, content) in files.sorted(by: { $0.key < $1.key }) {
            let nameData = Data(name.utf8)
            let crc = CRC32.checksum(content)
            var local = Data()
            local.appendUInt32(0x04034B50)
            local.appendUInt16(20) // version needed
            local.appendUInt16(0x0800) // UTF-8 names
            local.appendUInt16(0) // stored
            local.appendUInt16(0) // time
            local.appendUInt16(0x21) // date: 1980-01-01
            local.appendUInt32(crc)
            local.appendUInt32(UInt32(content.count))
            local.appendUInt32(UInt32(content.count))
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0)
            var record = Data()
            record.appendUInt32(0x02014B50)
            record.appendUInt16(0x031E) // made by Unix, 3.0
            record.appendUInt16(20)
            record.appendUInt16(0x0800)
            record.appendUInt16(0)
            record.appendUInt16(0)
            record.appendUInt16(0x21)
            record.appendUInt32(crc)
            record.appendUInt32(UInt32(content.count))
            record.appendUInt32(UInt32(content.count))
            record.appendUInt16(UInt16(nameData.count))
            record.appendUInt16(0) // extra
            record.appendUInt16(0) // comment
            record.appendUInt16(0) // disk
            record.appendUInt16(0) // internal attributes
            record.appendUInt32(0o100644 << 16) // a regular file, rw-r--r--
            record.appendUInt32(UInt32(output.count))
            record.append(nameData)
            central.append(record)
            output.append(local)
            output.append(nameData)
            output.append(content)
            count += 1
        }
        guard count < 0xFFFF, output.count < 0xFFFFFFFF else { throw Failure.invalid }
        let centralStart = output.count
        output.append(central)
        output.appendUInt32(0x06054B50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(count))
        output.appendUInt16(UInt16(count))
        output.appendUInt32(UInt32(central.count))
        output.appendUInt32(UInt32(centralStart))
        output.appendUInt16(0)
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB88320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }

    mutating func setUInt32(_ value: UInt32, at offset: Int) {
        for index in 0 ..< 4 {
            self[startIndex + offset + index] = UInt8((value >> (8 * UInt32(index))) & 0xFF)
        }
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(value & 0xFFFF))
        appendUInt16(UInt16(value >> 16))
    }
}
