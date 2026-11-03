import XCTest
@testable import HalloweenCore

final class FreeAccessTests: XCTestCase {
    @MainActor func testUnlimitedScenesAndImportsPersistWithoutPurchase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(directory: folder)
        for number in 0..<12 { XCTAssertTrue(store.saveScene(HorrorScene(name: "Scene \(number)"))) }
        let imported = try store.importArchive(JSONEncoder().encode(SceneArchive(scene: HorrorScene(name: "Imported", steps: [SceneStep(kind: .flicker, seconds: 1)]))))
        let restored = AppStore(directory: folder)
        XCTAssertEqual(restored.scenes.count, 13)
        XCTAssertTrue(restored.scenes.contains { $0.id == imported.id })
        var edited = restored.scenes[0]; edited.name = "Edited"
        XCTAssertTrue(restored.saveScene(edited))
        XCTAssertEqual(AppStore(directory: folder).scenes.first?.name, "Edited")
    }
    func testAudioURLUsesOSRouteForSelectedSpeaker() {
        XCTAssertEqual(LocalNetwork.routedAddress(to: "127.0.0.1"), "127.0.0.1")
        XCTAssertNil(LocalNetwork.routedAddress(to: "invalid"))
        let server = AudioServer()
        let url = URL(string: "http://192.0.2.1:1234/token.wav")!
        let routed = server.reachableURL(url, for: "127.0.0.1")
        XCTAssertEqual(routed.host, "127.0.0.1"); XCTAssertEqual(routed.port, 1234); XCTAssertEqual(routed.path, "/token.wav")
    }
    func testSubnetDiscoveryUsesMaskAndBoundsLargeNetworks() {
        let small = LocalNetwork.subnetHosts(address: "192.168.1.10", mask: "255.255.255.248")
        XCTAssertEqual(small, ["192.168.1.9", "192.168.1.11", "192.168.1.12", "192.168.1.13", "192.168.1.14"])
        XCTAssertEqual(LocalNetwork.subnetHosts(address: "192.168.1.10", mask: "255.255.254.0").count, 509)
        XCTAssertEqual(LocalNetwork.subnetHosts(address: "10.0.1.10", mask: "255.0.0.0").count, 253)
        XCTAssertTrue(LocalNetwork.subnetHosts(address: "bad", mask: "255.255.255.0").isEmpty)
        XCTAssertTrue(LocalNetwork.subnetHosts(address: "192.168.1.10", mask: "255.0.255.0").isEmpty)
    }
}
