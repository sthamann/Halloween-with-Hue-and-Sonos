import XCTest
@testable import HalloweenCore

final class HueDiscoveryLiveTests: XCTestCase {
    func testRealHueTLSDiscoveryReadOnly() async throws {
        guard let ip = ProcessInfo.processInfo.environment["HAUNT_LIVE_HUE_IP"] else { throw XCTSkip("Opt-in HAUNT_LIVE_HUE_IP: only public bridge configuration over verified HTTPS") }
        let network = NetworkClient(session: HueTLS.session(bridgeID: nil))
        let data = try await network.request("https://\(ip)/api/config", timeout: 5)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let id = try XCTUnwrap(config["bridgeid"] as? String)
        let bridge = await HueClient().probe(ip); XCTAssertNotNil(bridge)
        do {
            _ = try await NetworkClient(session: HueTLS.session(bridgeID: "0000000000000000")).request("https://\(ip)/api/config", timeout: 3)
            XCTFail("A valid Hue certificate for the wrong bridge must be rejected")
        } catch { /* expected identity mismatch */ }
        print("LIVE HUE TLS DISCOVERY: \(id)")
    }
}
