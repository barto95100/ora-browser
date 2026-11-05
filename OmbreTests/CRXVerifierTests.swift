import CryptoKit
import Foundation
@testable import Ombre
import Security
import Testing

/// Chrome Web Store packages are trusted only when signed by the key their
/// extension id comes from, and when that id is the one asked for.
struct CRXVerifierTests {
    private let zip = Data([0x50, 0x4B, 0x03, 0x04]) + Data("the extension's files".utf8)

    // MARK: - Valid packages

    @Test func aPackageSignedWithECDSAIsAccepted() throws {
        let key = P256.Signing.PrivateKey()
        let package = try CRXBuilder.ecdsa(key: key, zip: zip)

        #expect(try CRXVerifier.verifiedZip(from: package.data, extensionID: package.id) == zip)
    }

    @Test func aPackageSignedWithRSAIsAccepted() throws {
        let package = try CRXBuilder.rsa(zip: zip)

        #expect(try CRXVerifier.verifiedZip(from: package.data, extensionID: package.id) == zip)
    }

    // MARK: - Refused packages

    @Test func aChangedZipIsRefused() throws {
        let package = try CRXBuilder.ecdsa(key: P256.Signing.PrivateKey(), zip: zip)
        var altered = package.data
        altered[altered.count - 1] ^= 0xFF

        #expect(throws: CRXVerifier.Failure.badSignature) {
            try CRXVerifier.verifiedZip(from: altered, extensionID: package.id)
        }
    }

    @Test func anotherExtensionIsRefused() throws {
        let package = try CRXBuilder.ecdsa(key: P256.Signing.PrivateKey(), zip: zip)
        let other = try CRXBuilder.ecdsa(key: P256.Signing.PrivateKey(), zip: zip)

        #expect(throws: CRXVerifier.Failure.wrongExtension) {
            try CRXVerifier.verifiedZip(from: package.data, extensionID: other.id)
        }
    }

    @Test func aSignatureByAnotherKeyIsRefused() throws {
        // Claims the id of one key, signed by another.
        let owner = P256.Signing.PrivateKey()
        let forger = P256.Signing.PrivateKey()
        let package = try CRXBuilder.ecdsa(key: forger, zip: zip, claimedKey: owner)

        #expect(throws: CRXVerifier.Failure.badSignature) {
            try CRXVerifier.verifiedZip(from: package.data, extensionID: package.id)
        }
    }

    @Test func anotherKeysOwnSignatureIsRefused() throws {
        // The forger signs with its own key and shows it, but claims the
        // owner's extension id: its key doesn't give that id.
        let owner = P256.Signing.PrivateKey()
        let forger = P256.Signing.PrivateKey()
        let package = try CRXBuilder.ecdsa(key: forger, zip: zip, claimedID: owner)

        #expect(throws: CRXVerifier.Failure.badSignature) {
            try CRXVerifier.verifiedZip(from: package.data, extensionID: package.id)
        }
    }

    @Test func aPackageWithoutItsZipIsRefused() throws {
        let package = try CRXBuilder.ecdsa(key: P256.Signing.PrivateKey(), zip: zip)
        let headerOnly = package.data.prefix(package.data.count - zip.count)

        #expect(throws: CRXVerifier.Failure.malformed) {
            try CRXVerifier.verifiedZip(from: Data(headerOnly), extensionID: package.id)
        }
    }

    @Test(arguments: [
        // A group (wire type 3), a length past the end, an endless varint.
        Data([0x1B, 0x00]),
        Data([0x12, 0x7F, 0x00]),
        Data(repeating: 0xFF, count: 12)
    ])
    func aBrokenHeaderIsRefused(header: Data) {
        var data = Data("Cr24".utf8) + Data([3, 0, 0, 0])
        data.append(withUnsafeBytes(of: UInt32(header.count).littleEndian) { Data($0) })
        data.append(header)
        data.append(zip)
        #expect(throws: CRXVerifier.Failure.malformed) {
            try CRXVerifier.verifiedZip(from: data, extensionID: String(repeating: "a", count: 32))
        }
    }

    @Test func unsignedFormatsAreRefused() {
        let crx2 = Data("Cr24".utf8) + Data([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + zip
        #expect(throws: CRXVerifier.Failure.notCRX3) {
            try CRXVerifier.verifiedZip(from: crx2, extensionID: String(repeating: "a", count: 32))
        }
        #expect(throws: CRXVerifier.Failure.notCRX3) {
            try CRXVerifier.verifiedZip(from: zip, extensionID: String(repeating: "a", count: 32))
        }
    }

    @Test func aTruncatedHeaderIsRefused() {
        let truncated = Data("Cr24".utf8) + Data([3, 0, 0, 0, 0xFF, 0, 0, 0]) + Data([0x12, 0x05])
        #expect(throws: CRXVerifier.Failure.malformed) {
            try CRXVerifier.verifiedZip(from: truncated, extensionID: String(repeating: "a", count: 32))
        }
    }

    // MARK: - Ids and hosts

    @Test func extensionIDsUseTheLettersAToP() {
        let crxID = Data([0x00, 0x1F, 0xA5, 0xFF] + Array(repeating: 0, count: 12))
        #expect(CRXVerifier.extensionID(of: crxID) == "aabpkfpp" + String(repeating: "a", count: 24))
    }

    @Test func packagesComeOnlyFromGoogleInHTTPS() throws {
        let allowed = [
            "https://clients2.googleusercontent.com/crx/blobs/abc/extension.crx",
            "https://clients2.google.com/service/update2/crx",
            "https://edgedl.me.gvt1.com/edgedl/release2/chrome_component/abc.crx"
        ]
        let refused = [
            "http://clients2.googleusercontent.com/crx/blobs/abc.crx",
            "https://evil.example/extension.crx",
            "https://googleusercontent.com.evil.example/a.crx",
            "https://notgoogle.com/a.crx"
        ]
        for string in allowed {
            #expect(try ChromeWebStore.isDownloadURL(#require(URL(string: string))), "\(string)")
        }
        for string in refused {
            #expect(try !ChromeWebStore.isDownloadURL(#require(URL(string: string))), "\(string)")
        }
    }

    @Test func anUpdateFromElsewhereIsIgnored() {
        let xml = """
        <gupdate><app appid="aaaa"><updatecheck status="ok" version="2.0" \
        codebase="https://evil.example/a.crx"/></app>\
        <app appid="bbbb"><updatecheck status="ok" version="3.0" \
        codebase="https://clients2.googleusercontent.com/crx/blobs/b.crx"/></app></gupdate>
        """
        let updates = ChromeWebStoreUpdates.parse(Data(xml.utf8))

        #expect(updates["aaaa"] == nil)
        #expect(updates["bbbb"]?.version == "3.0")
    }
}

// MARK: - Building packages

/// Writes `.crx` files as the Chrome Web Store does, for the tests.
private enum CRXBuilder {
    struct Package {
        let data: Data
        let id: String
    }

    /// `claimedKey`: shows the owner's key with the forger's signature.
    /// `claimedID`: shows the forger's own key, with the owner's id.
    static func ecdsa(
        key: P256.Signing.PrivateKey,
        zip: Data,
        claimedKey: P256.Signing.PrivateKey? = nil,
        claimedID: P256.Signing.PrivateKey? = nil
    ) throws -> Package {
        let shownKey = (claimedKey ?? key).publicKey.derRepresentation
        let idKey = (claimedID ?? claimedKey ?? key).publicKey.derRepresentation
        let crxID = Data(SHA256.hash(data: idKey).prefix(16))
        let signedData = field(1, crxID)
        let signature = try key.signature(for: message(signedData, zip)).derRepresentation
        let proof = field(1, shownKey) + field(2, signature)
        return package(header: field(3, proof) + field(10000, signedData), zip: zip, crxID: crxID)
    }

    static func rsa(zip: Data) throws -> Package {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else { throw CRXVerifier.Failure.malformed }
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        let spki = der(0x30, algorithm + der(0x03, Data([0]) + pkcs1))
        let crxID = Data(SHA256.hash(data: spki).prefix(16))
        let signedData = field(1, crxID)
        guard let signature = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA256, message(signedData, zip) as CFData, &error
        ) as Data? else { throw CRXVerifier.Failure.malformed }
        let proof = field(1, spki) + field(2, signature)
        return package(header: field(2, proof) + field(10000, signedData), zip: zip, crxID: crxID)
    }

    private static func package(header: Data, zip: Data, crxID: Data) -> Package {
        var data = Data("Cr24".utf8) + uint32(3) + uint32(UInt32(header.count))
        data.append(header)
        data.append(zip)
        return Package(data: data, id: CRXVerifier.extensionID(of: crxID))
    }

    private static func message(_ signedData: Data, _ zip: Data) -> Data {
        Data("CRX3 SignedData".utf8) + Data([0]) + uint32(UInt32(signedData.count)) + signedData + zip
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// A length-delimited protobuf field.
    private static func field(_ number: Int, _ value: Data) -> Data {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(value.count)) + value
    }

    private static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }

    /// A DER element (lengths up to 65535).
    private static func der(_ tag: UInt8, _ contents: Data) -> Data {
        let length = contents.count
        let lengthBytes: [UInt8] = length < 0x80
            ? [UInt8(length)]
            : length < 0x100 ? [0x81, UInt8(length)] : [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        return Data([tag] + lengthBytes) + contents
    }
}
