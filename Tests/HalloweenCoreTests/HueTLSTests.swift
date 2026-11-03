import XCTest
import Security
@testable import HalloweenCore

final class HueTLSTests: XCTestCase {
    // Public leaf from a BSB003 Bridge Pro. Its 2025–2038 lifetime reproduces
    // Apple's SSL-policy rejection; no keys or pairing credentials are included.
    private let pem = """
-----BEGIN CERTIFICATE-----
MIICUDCCAfWgAwIBAgIJAMQplv/+xLf+MAoGCCqGSM49BAMCMDkxCzAJBgNVBAYT
Ak5MMRQwEgYDVQQKDAtQaGlsaXBzIEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2Uw
IhgPMjAyNTAyMjcxMjM5MTFaGA8yMDM4MDExOTAzMTQwN1owTzELMAkGA1UEBhMC
TkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRkwFwYDVQQDDBBDNDI5OTZGRkZFQzRC
N0ZFMQ8wDQYDVQQLDAZCU0IwMDMwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARq
aevP+GaPqAMz9hmV81s/W5d9u9B3szEeBJPvqqPxQHObl4ZgcQ2WeZuYa0Rt8aAX
EyelCwGv9PcXsf8cqPCCo4HLMIHIMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQD
AgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBTzOo47+tqBpBMlwfzS
hXGxZoOQZjB0BgNVHSMEbTBrgBRnY41MWsNPqjwi1Gcp+pYqccUaZKE9pDswOTEL
MAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRQwEgYDVQQDDAtyb290
LWJyaWRnZYIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIDSQAwRgIh
ALMVa0Kx29k7xLFFcKSsMghnMD7BzMj0tiEgF+StHJbdAiEAu0jIFlAb4+5H6Jbm
N4urv60SF30PYF5W9Sv/4NsnLkc=
-----END CERTIFICATE-----
"""
    private var der: Data {
        let base64 = pem.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return Data(base64Encoded: base64)!
    }
    private func accepts(_ data: Data, id: String? = "c42996fffec4b7fe", date: Date? = nil) throws -> Bool {
        let leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &trust), errSecSuccess)
        let value = try XCTUnwrap(trust)
        if let date { XCTAssertEqual(SecTrustSetVerifyDate(value, date as CFDate), errSecSuccess) }
        return HueTLS.validate(value, bridgeID: id, leaf: leaf,
                               subject: SecCertificateCopySubjectSummary(leaf) as String? ?? "")
    }
    func testBridgeProLongLivedCertificateIsAccepted() throws {
        XCTAssertTrue(try accepts(der))
        XCTAssertTrue(try accepts(der, id: nil))
    }
    func testWrongBridgeAndInvalidDatesAreRejected() throws {
        XCTAssertFalse(try accepts(der, id: "0000000000000000"))
        XCTAssertFalse(try accepts(der, date: Date(timeIntervalSince1970: 1_577_836_800))) // 2020
        XCTAssertFalse(try accepts(der, date: Date(timeIntervalSince1970: 2_208_988_800))) // 2040
    }
    func testAlteredSignatureIsRejected() throws {
        var changed = der
        changed[changed.count - 1] ^= 1
        XCTAssertFalse(try accepts(changed))
    }
    func testClientOnlyPurposeAndMalformedDERAreRejected() throws {
        var changed = der
        let serverAuth = Data([0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])
        let range = try XCTUnwrap(changed.range(of: serverAuth))
        changed[range.upperBound - 1] = 0x02 // TLS client auth instead of server auth
        XCTAssertFalse(HueTLS.hasServerUsage(changed))
        XCTAssertFalse(HueTLS.hasServerUsage(Data(der.dropLast())))
    }
}
