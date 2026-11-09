import CryptoKit
import Foundation
import Security

/// Checks a Chrome Web Store package (`.crx`, version 3) like Chrome: it is
/// signed by the key its extension id comes from, and that id is the one
/// asked for. Then the `.zip` inside can be trusted.
///
/// Format: "Cr24", version 3, the header's size, the header (a
/// `CrxFileHeader` protobuf), then the `.zip`. The header holds the signed
/// data (the 16-byte `crx_id`) and the proofs: a public key (DER
/// SubjectPublicKeyInfo) and its SHA-256 signature, RSA or ECDSA P-256, of
/// "CRX3 SignedData\0" + the signed data's size (4 bytes) + the signed data
/// + the `.zip`. The extension id is the `crx_id` written with the letters
/// a to p, and the `crx_id` is the start of the key's SHA-256.
enum CRXVerifier {
    enum Failure: LocalizedError, Equatable {
        case notCRX3
        case malformed
        case wrongExtension
        case badSignature

        var errorDescription: String? {
            switch self {
            case .notCRX3, .malformed: String(localized: "This extension package is damaged.")
            case .wrongExtension: String(
                    localized: "The Chrome Web Store sent a different extension from the one requested."
                )
            case .badSignature: String(
                    localized: "This extension package isn't signed by its developer: it was changed."
                )
            }
        }
    }

    /// The `.zip` of a package of the extension `extensionID`, once checked.
    static func verifiedZip(from data: Data, extensionID: String) throws -> Data {
        let data = Data(data)
        guard data.count > 12, data.prefix(4) == Data("Cr24".utf8), uint32(data, at: 4) == 3 else { // not shown
            throw Failure.notCRX3
        }
        let headerSize = Int(uint32(data, at: 8))
        let zipStart = 12 + headerSize
        guard headerSize > 0, zipStart < data.count else { throw Failure.malformed }
        let header = try CRXHeader(data.subdata(in: 12 ..< zipStart))
        let zip = data.subdata(in: zipStart ..< data.count)

        guard let crxID = try SignedData(header.signedData).crxID, crxID.count == 16 else {
            throw Failure.malformed
        }
        guard Self.extensionID(of: crxID) == extensionID else { throw Failure.wrongExtension }

        var message = Data("CRX3 SignedData".utf8) + Data([0]) // not shown
        var size = UInt32(header.signedData.count).littleEndian
        message.append(Data(bytes: &size, count: 4))
        message.append(header.signedData)
        message.append(zip)

        // The proof made with the key the id comes from.
        let isDeveloperKey: (Proof) -> Bool = { Data(SHA256.hash(data: $0.publicKey).prefix(16)) == crxID }
        let rsa = header.rsaProofs.filter(isDeveloperKey)
        let ecdsa = header.ecdsaProofs.filter(isDeveloperKey)
        guard rsa.contains(where: { verifyRSA($0, message) }) || ecdsa.contains(where: { verifyECDSA($0, message) })
        else { throw Failure.badSignature }
        return zip
    }

    /// 16 bytes as Chrome writes an extension id: each half-byte as a
    /// letter from a to p.
    static func extensionID(of crxID: Data) -> String {
        let letters = Array("abcdefghijklmnop")
        return String(crxID.flatMap { [letters[Int($0 >> 4)], letters[Int($0 & 0x0F)]] })
    }

    // MARK: - Signatures

    private static func verifyECDSA(_ proof: Proof, _ message: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: proof.publicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: proof.signature)
        else { return false }
        return key.isValidSignature(signature, for: message)
    }

    private static func verifyRSA(_ proof: Proof, _ message: Data) -> Bool {
        guard let pkcs1 = DER.rsaPublicKey(fromSubjectPublicKeyInfo: proof.publicKey) else { return false }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            proof.signature as CFData,
            nil
        )
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset ..< offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }
}

// MARK: - Header

private struct Proof {
    let publicKey: Data
    let signature: Data
}

/// `CrxFileHeader`: 2 = RSA proofs, 3 = ECDSA proofs, 10000 = signed data.
private struct CRXHeader {
    var rsaProofs: [Proof] = []
    var ecdsaProofs: [Proof] = []
    var signedData = Data()

    init(_ data: Data) throws {
        for field in try Protobuf.fields(of: data) {
            switch field.number {
            case 2: try rsaProofs.append(Self.proof(field.value))
            case 3: try ecdsaProofs.append(Self.proof(field.value))
            case 10000: signedData = field.value
            default: break
            }
        }
    }

    /// `AsymmetricKeyProof`: 1 = public key, 2 = signature.
    private static func proof(_ data: Data) throws -> Proof {
        let fields = try Protobuf.fields(of: data)
        guard let key = fields.first(where: { $0.number == 1 })?.value,
              let signature = fields.first(where: { $0.number == 2 })?.value
        else { throw CRXVerifier.Failure.malformed }
        return Proof(publicKey: key, signature: signature)
    }
}

/// `SignedData`: 1 = crx_id.
private struct SignedData {
    let crxID: Data?

    init(_ data: Data) throws {
        // The last one counts, like protobuf.
        crxID = try Protobuf.fields(of: data).last { $0.number == 1 }?.value
    }
}

/// Just enough protobuf: the length-delimited fields; other kinds skipped.
private enum Protobuf {
    struct Field {
        let number: Int
        let value: Data
    }

    static func fields(of data: Data) throws -> [Field] {
        let bytes = [UInt8](data)
        var fields: [Field] = []
        var index = 0
        while index < bytes.count {
            let key = try varint(bytes, &index)
            let number = Int(key >> 3)
            switch key & 0x07 {
            case 0: _ = try varint(bytes, &index)
            case 1: index += 8
            case 5: index += 4
            case 2:
                let length = try varint(bytes, &index)
                guard length <= UInt64(bytes.count - index) else { throw CRXVerifier.Failure.malformed }
                let end = index + Int(length)
                fields.append(Field(number: number, value: Data(bytes[index ..< end])))
                index = end
            default:
                throw CRXVerifier.Failure.malformed
            }
            guard index <= bytes.count else { throw CRXVerifier.Failure.malformed }
        }
        return fields
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        throw CRXVerifier.Failure.malformed
    }
}

/// Just enough DER for a SubjectPublicKeyInfo: SEQUENCE { algorithm, BIT
/// STRING { 0, key } }.
enum DER {
    static func rsaPublicKey(fromSubjectPublicKeyInfo data: Data) -> Data? {
        let bytes = [UInt8](data)
        var index = 0
        guard let outer = element(bytes, &index, tag: 0x30) else { return nil }
        var inner = outer.lowerBound
        guard element(bytes, &inner, tag: 0x30) != nil,
              let bitString = element(bytes, &inner, tag: 0x03),
              bitString.count > 1, bytes[bitString.lowerBound] == 0
        else { return nil }
        return Data(bytes[(bitString.lowerBound + 1) ..< bitString.upperBound])
    }

    /// The contents of the element at `index` with `tag`; `index` moves past it.
    private static func element(_ bytes: [UInt8], _ index: inout Int, tag: UInt8) -> Range<Int>? {
        guard index + 2 <= bytes.count, bytes[index] == tag else { return nil }
        var length = Int(bytes[index + 1])
        var start = index + 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, start + count <= bytes.count else { return nil }
            length = bytes[start ..< start + count].reduce(0) { $0 << 8 | Int($1) }
            start += count
        }
        guard start + length <= bytes.count else { return nil }
        index = start + length
        return start ..< start + length
    }
}
