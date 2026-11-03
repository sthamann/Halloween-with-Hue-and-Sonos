import XCTest
import Security
@testable import HalloweenCore

final class CredentialStoreTests: XCTestCase {
    func testDeniedAccessNeverPromptsOnSubsequentBackgroundReads() {
        var interactiveCalls = 0
        var silentCalls = 0
        let denied: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = { query, _ in
            let values = query as NSDictionary
            if values[kSecUseAuthenticationUI] as? String == kSecUseAuthenticationUIAllow as String {
                interactiveCalls += 1
                return errSecUserCanceled
            }
            XCTAssertEqual(values[kSecUseAuthenticationUI] as? String, kSecUseAuthenticationUIFail as String)
            silentCalls += 1
            return errSecInteractionNotAllowed
        }
        XCTAssertNil(CredentialStore.read("test-bridge", allowInteraction: true, copyMatching: denied))
        for _ in 0..<100 {
            XCTAssertNil(CredentialStore.read("test-bridge", allowInteraction: false, copyMatching: denied))
        }
        XCTAssertEqual(interactiveCalls, 1)
        XCTAssertEqual(silentCalls, 100)
    }

    func testAuthorizedKeyRemainsAvailableWithoutPrompting() {
        let value = CredentialStore.read("test-bridge", allowInteraction: false) { query, result in
            XCTAssertEqual((query as NSDictionary)[kSecUseAuthenticationUI] as? String, kSecUseAuthenticationUIFail as String)
            result?.pointee = Data("test-only-key".utf8) as CFData
            return errSecSuccess
        }
        XCTAssertEqual(value, "test-only-key")
    }
}
