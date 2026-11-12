import Foundation
@testable import Ombre
import Security
import Testing

/// "Continue anyway" trusts the certificate that was shown, not the host
/// (MOT-12).
struct CertificateExceptionTests {
    /// Two self-signed test certificates (a.test, b.test).
    private static let first =
        "MIIBWDCB/qADAgECAhRj61Fo4ZyaZtFo6wXY9Et87q4Z0jAKBggqhkjOPQQDAjARMQ8wDQYDVQQDDAZhLnRlc3QwIBcNMjYx"
            + "MTA1MTQ1NDMyWhgPMjEyNjEwMTIxNDU0MzJaMBExDzANBgNVBAMMBmEudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IA"
            + "BOfdWepLcl49Izqd5+4F03VxJ/Am20SzCaggtOZ8L0JAGzhTo3dKibHkBUQX8t5fuO3ctKSdDhEn7D81IXU6q92jMjAwMB0G"
            + "A1UdDgQWBBS4j4AQjrBAgoTO7ghtPgjGUbf6wTAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQDTbJyqy7Ao"
            + "tD3Ikfk7qf4UE8fPvYrbFs9yfEmyhrJ9VgIhANTPX4t9hS03ztT9dxmnyYHwi9zH1xoRL1nPWADVbHh2"
    private static let second =
        "MIIBVzCB/qADAgECAhQ7DT3tYm2e4yAE5hlTVRiGbJuaSTAKBggqhkjOPQQDAjARMQ8wDQYDVQQDDAZiLnRlc3QwIBcNMjYx"
            + "MTA1MTQ1NDMzWhgPMjEyNjEwMTIxNDU0MzNaMBExDzANBgNVBAMMBmIudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IA"
            + "BAp80zEc6QYXqrqsoN1w4Vf1SZqjpScE9Dn1cAd+Y8VICByHdYFI8nZb/5lykojUhsN7SHsC5PALcMSybEKKBlujMjAwMB0G"
            + "A1UdDgQWBBQHSFX3m1zZ5uyExDmVIx2Jeh5aAzAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0gAMEUCIQD/yCfCEG8f"
            + "NdjPFBmv7i9S6v/lqk7gUdW5rIlIf3OfqAIgSW0XYSZEIAliOkOoOHqSC9ZgsCepL6OKCdFSLsqLrjU="

    private func certificate(_ base64: String) throws -> SecCertificate {
        let data = try #require(Data(base64Encoded: base64))
        return try #require(SecCertificateCreateWithData(nil, data as CFData))
    }

    private func trust(_ certificate: SecCertificate) throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test func digestIsTheServerCertificates() throws {
        let first = try certificate(Self.first)
        #expect(CertificateException.digest(of: first)
            == "8f72e204a3bc19806590e42989b62c8e0dd56c648df87742635b821f39086f54")
        #expect(try CertificateException.digest(of: trust(first)) == CertificateException.digest(of: first))
        #expect(try CertificateException.digest(of: certificate(Self.second))
            != CertificateException.digest(of: first))
    }

    /// Another certificate for the same host later (someone on the network)
    /// isn't accepted; nor the accepted one for another host.
    @Test func onlyTheAcceptedCertificateForItsHost() throws {
        let accepted = try CertificateException.digest(of: certificate(Self.first))
        let other = try CertificateException.digest(of: certificate(Self.second))
        let exceptions = ["self-signed.example": accepted]

        let host = "self-signed.example"
        #expect(CertificateException.isAccepted(digest: accepted, host: host, exceptions: exceptions))
        #expect(!CertificateException.isAccepted(digest: other, host: host, exceptions: exceptions))
        #expect(!CertificateException.isAccepted(digest: accepted, host: "other.example", exceptions: exceptions))
        #expect(!CertificateException.isAccepted(digest: nil, host: host, exceptions: exceptions))
    }

    @Test func refusedCertificateComesFromTheLoadError() throws {
        let refused = try trust(certificate(Self.first))
        let error = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted,
            userInfo: [NSURLErrorFailingURLPeerTrustErrorKey: refused]
        )
        #expect(CertificateException.trust(in: error).flatMap(CertificateException.digest(of:))
            == CertificateException.digest(of: refused))
        #expect(CertificateException.trust(in: URLError(.timedOut)) == nil)
    }

    /// A page showing a certificate accepted with "Continue Anyway" says
    /// "Not Secure", wherever it shows (a popup reusing the tab's
    /// connection); a certificate never accepted keeps the lock.
    @MainActor @Test func acceptedCertificateIsNotSecure() throws {
        let accepted = try trust(certificate(Self.first))
        let other = try trust(certificate(Self.second))
        let digest = try #require(CertificateException.digest(of: accepted))
        CertificateException.remember(digest)
        defer { CertificateException.forget(digest) }

        #expect(CertificateException.wasAccepted(accepted))
        #expect(!CertificateException.wasAccepted(other))
        #expect(!CertificateException.wasAccepted(nil))

        let https = try #require(URL(string: "https://self-signed.example/"))
        #expect(PageSecurity.of(https, hasOnlySecureContent: true, usesAcceptedCertificate: true) == .notSecure)
        #expect(PageSecurity.of(https, hasOnlySecureContent: true, usesAcceptedCertificate: false) == .secure)
    }

    /// The tab's bar: a lock, a warning (said in words), or a globe.
    @MainActor @Test func tabBarSaysWhatThePageIs() throws {
        let http = try #require(URL(string: "http://example.com/"))
        let blank = try #require(URL(string: "about:blank"))
        #expect(URLBar.securitySymbol(.secure) == "lock.fill")
        #expect(URLBar.securitySymbol(PageSecurity.of(http, hasOnlySecureContent: true))
            == "exclamationmark.triangle.fill")
        #expect(URLBar.securitySymbol(PageSecurity.of(blank, hasOnlySecureContent: false)) == "globe")
    }
}
