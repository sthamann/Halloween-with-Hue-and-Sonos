import Foundation
import Security

/// Trust only Philips/Signify Hue roots and the selected bridge's certificate name.
/// Certificates: developers.meethue.com/develop/application-design-guidance/using-https/
final class HueTLS: NSObject, URLSessionDelegate, @unchecked Sendable {
    let bridgeID: String?
    init(bridgeID: String?) { self.bridgeID = bridgeID }
    static let rootsPEM = """
-----BEGIN CERTIFICATE-----
MIICMjCCAdigAwIBAgIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIw
OTELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRQwEgYDVQQDDAty
b290LWJyaWRnZTAiGA8yMDE3MDEwMTAwMDAwMFoYDzIwMzgwMTE5MDMxNDA3WjA5
MQswCQYDVQQGEwJOTDEUMBIGA1UECgwLUGhpbGlwcyBIdWUxFDASBgNVBAMMC3Jv
b3QtYnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjNw2tx2AplOf9x86
aTdvEcL1FU65QDxziKvBpW9XXSIcibAeQiKxegpq8Exbr9v6LBnYbna2VcaK0G22
jOKkTqOBuTCBtjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNV
HQ4EFgQUZ2ONTFrDT6o8ItRnKfqWKnHFGmQwdAYDVR0jBG0wa4AUZ2ONTFrDT6o8
ItRnKfqWKnHFGmShPaQ7MDkxCzAJBgNVBAYTAk5MMRQwEgYDVQQKDAtQaGlsaXBz
IEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2WCFDuxUi22sYpLlwJY81Wrqy11phcO
MAoGCCqGSM49BAMCA0gAMEUCIEBYYEOsa07TH7E5MJnGw557lVkORgit2Rm1h3B2
sFgDAiEA1Fj/C3AN5psFMjo0//mrQebo0eKd3aWRx+pQY08mk48=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIBzDCCAXOgAwIBAgICEAAwCgYIKoZIzj0EAwIwPDELMAkGA1UEBhMCTkwxFDAS
BgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9vdCBDQSAwMTAgFw0y
NTAyMjUwMDAwMDBaGA8yMDUwMTIzMTIzNTk1OVowPDELMAkGA1UEBhMCTkwxFDAS
BgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9vdCBDQSAwMTBZMBMG
ByqGSM49AgEGCCqGSM49AwEHA0IABFfOO0jfSAUXGQ9kjEDzyBrcMQ3ItyA5krE+
cyvb1Y3xFti7KlAad8UOnAx0FBLn7HZrlmIwm1QnX0fK3LPM13mjYzBhMB0GA1Ud
DgQWBBTF1pSpsCASX/z0VHLigxU2CAaqoTAfBgNVHSMEGDAWgBTF1pSpsCASX/z0
VHLigxU2CAaqoTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggq
hkjOPQQDAgNHADBEAiAk7duT+IHbOGO4UUuGLAEpyYejGZK9Z7V9oSfnvuQ5BQIg
IYSgwwxHXm73/JgcU9lAM6c8Bmu3UE3kBIUwBs1qXFw=
-----END CERTIFICATE-----
"""
    static let anchors: [SecCertificate] = {
        rootsPEM.components(separatedBy: "-----BEGIN CERTIFICATE-----").compactMap { block in
            guard let end = block.range(of: "-----END CERTIFICATE-----"), let data = Data(base64Encoded: String(block[..<end.lowerBound]), options: .ignoreUnknownCharacters) else { return nil }
            return SecCertificateCreateWithData(nil, data as CFData)
        }
    }()
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
              let subject = SecCertificateCopySubjectSummary(leaf) as String? else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        if Self.validate(trust, bridgeID: bridgeID, leaf: leaf, subject: subject) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func validate(_ trust: SecTrust, bridgeID: String?, leaf: SecCertificate, subject: String) -> Bool {
        let certificateID = subject.lowercased()
        guard certificateID.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
              bridgeID == nil || certificateID == bridgeID?.lowercased(),
              !anchors.isEmpty, hasServerUsage(SecCertificateCopyData(leaf) as Data),
              let key = SecCertificateCopyKey(leaf),
              let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              let bits = attributes[kSecAttrKeySizeInBits as String] as? Int,
              let type = attributes[kSecAttrKeyType as String] as? String,
              (type == (kSecAttrKeyTypeECSECPrimeRandom as String) && bits >= 256)
                || (type == (kSecAttrKeyTypeRSA as String) && bits >= 2048) else { return false }
        guard SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess else { return false }
        // Hue uses a private CA, bridge CNs (no DNS SAN) and device certificates
        // valid until 2038. Apple's web-server policy caps new private-CA leaves
        // at 825 days, incorrectly rejecting Bridge Pro. BasicX509 still verifies
        // chain, signatures, critical extensions and current validity. Above and
        // below we explicitly enforce bridge identity, strong keys and TLS use.
        var error: CFError?
        let valid = SecTrustEvaluateWithError(trust, &error)
        if !valid { NSLog("Hue certificate validation failed: %@", String(describing: error)) }
        return valid
    }

    /// Read only the signed X.509 extension structure, never search raw bytes for OIDs.
    /// Require digital-signature usage, TLS server authentication and a non-CA leaf.
    static func hasServerUsage(_ certificate: Data) -> Bool {
        guard let outer = DER.read(Array(certificate)), outer.count == 1, outer[0].tag == 0x30,
              let fields = DER.read(outer[0].value), fields.count == 3, fields[0].tag == 0x30,
              fields[1].tag == 0x30, let algorithm = DER.read(fields[1].value),
              let signatureOID = algorithm.first, signatureOID.tag == 0x06,
              // ECDSA with SHA-256, SHA-384 or SHA-512 (both official Hue roots are EC).
              [[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02], [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03],
               [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x04]].contains(signatureOID.value),
              let tbs = DER.read(fields[0].value),
              let wrapped = tbs.last, wrapped.tag == 0xa3,
              let sequence = DER.read(wrapped.value), sequence.count == 1, sequence[0].tag == 0x30,
              let extensions = DER.read(sequence[0].value) else { return false }
        var values: [[UInt8]: [UInt8]] = [:]
        for item in extensions {
            guard item.tag == 0x30, let parts = DER.read(item.value),
                  (2...3).contains(parts.count), parts[0].tag == 0x06,
                  let value = parts.last, value.tag == 0x04,
                  values.updateValue(value.value, forKey: parts[0].value) == nil else { return false }
        }
        guard let usageData = values[[0x55, 0x1d, 0x0f]], let usage = DER.read(usageData),
              usage.count == 1, usage[0].tag == 0x03, usage[0].value.count >= 2,
              usage[0].value[0] <= 7, usage[0].value[1] & 0x80 != 0,
              let ekuData = values[[0x55, 0x1d, 0x25]], let eku = DER.read(ekuData),
              eku.count == 1, eku[0].tag == 0x30, let purposes = DER.read(eku[0].value),
              purposes.contains(where: { $0.tag == 0x06 && $0.value == [0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01] }),
              let basicData = values[[0x55, 0x1d, 0x13]], let basic = DER.read(basicData),
              basic.count == 1, basic[0].tag == 0x30, let constraints = DER.read(basic[0].value),
              constraints.isEmpty || (constraints.count == 1 && constraints[0].tag == 0x01
                                     && constraints[0].value == [0]) else { return false }
        return true
    }

    private struct DER {
        let tag: UInt8
        let value: [UInt8]
        static func read(_ bytes: [UInt8]) -> [DER]? {
            var result: [DER] = [], offset = 0
            while offset < bytes.count {
                guard bytes.count - offset >= 2 else { return nil }
                let tag = bytes[offset], first = bytes[offset + 1]; offset += 2
                var length = Int(first)
                if first & 0x80 != 0 {
                    let count = Int(first & 0x7f)
                    guard (1...4).contains(count), bytes.count - offset >= count,
                          bytes[offset] != 0 else { return nil }
                    length = 0
                    for byte in bytes[offset..<(offset + count)] { length = length * 256 + Int(byte) }
                    offset += count
                    guard length >= 128 else { return nil }
                }
                guard length <= bytes.count - offset else { return nil }
                result.append(DER(tag: tag, value: Array(bytes[offset..<(offset + length)])))
                offset += length
            }
            return result
        }
    }
    private static let sessionLock = NSLock()
    private static var sessions: [String: URLSession] = [:]
    static func session(bridgeID: String?, streaming: Bool = false) -> URLSession {
        // Reuse the TLS connection for animation frames, keyed by verified bridge identity.
        if !streaming {
            sessionLock.lock(); defer { sessionLock.unlock() }
            let key = bridgeID?.lowercased() ?? "discovery"
            if let existing = sessions[key] { return existing }
            let created = makeSession(bridgeID: bridgeID, streaming: false)
            if sessions.count >= 32 { sessions.removeAll() }
            sessions[key] = created
            return created
        }
        return makeSession(bridgeID: bridgeID, streaming: true)
    }
    private static func makeSession(bridgeID: String?, streaming: Bool) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = streaming ? 90 : 5
        config.timeoutIntervalForResource = streaming ? 86_400 : 8
        return URLSession(configuration: config, delegate: HueTLS(bridgeID: bridgeID), delegateQueue: nil)
    }
}
