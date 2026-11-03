import XCTest
@testable import HalloweenCore

private final class HueProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var failures = 0
    static var writeDelay = 0.0
    static func delayWrites(_ seconds: Double) { lock.lock(); defer { lock.unlock() }; writeDelay = seconds }
    static func failNext(_ count: Int) { lock.lock(); defer { lock.unlock() }; failures = count }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasPrefix("192.0.2.") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static func reset() { lock.lock(); defer { lock.unlock() }; requests = []; failures = 0; writeDelay = 0 }
    static func recorded() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let delay = Self.writeDelay; let fail = Self.failures > 0; if fail { Self.failures -= 1 }; Self.lock.unlock()
        if request.httpMethod == "PUT", delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let body = fail ? "[{\"error\":{\"type\":901,\"description\":\"Internal error, 404\"}}]" : request.httpMethod == "PUT" ? "[{\"success\":{\"ok\":true}}]" : "{\"state\":{\"on\":true,\"bri\":91,\"reachable\":true,\"colormode\":\"hs\",\"hue\":4000,\"sat\":180}}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class MultiBridgeTests: XCTestCase {
    func testDiscoveryMergeRemembersMissingBridgesAndUpdatesChangedIP() throws {
        let a = HueBridge(id: "A", ip: "192.0.2.1", name: "Hue")
        let b = HueBridge(id: "B", ip: "192.0.2.2", name: "Hue")
        let changed = HueBridge(id: "A", ip: "192.0.2.9", name: "Hue")
        let merged = BridgeRegistry.merging([a,b], discovered: [changed,changed])
        XCTAssertEqual(merged.count, 2); XCTAssertEqual(merged.first { $0.id == "A" }?.ip, changed.ip)
        XCTAssertEqual(try JSONDecoder().decode([HueBridge].self, from: JSONEncoder().encode(merged)), merged)
    }
    func testHueRoomsAndRepeatedLocalLightIDsRemainBridgeQualified() {
        let a = HueBridge(id: "A", ip: "192.0.2.1", name: "Hue"); let b = HueBridge(id: "B", ip: "192.0.2.2", name: "Hue")
        let fixture: [String: [String: Any]] = ["1": ["name": "Lounge", "type": "Room", "lights": ["1","2"]], "2": ["name": "Etage", "type": "Zone", "lights": ["1"]], "3": ["type": "Entertainment", "lights": ["1"]]]
        let roomsA = HueClient.decodeRooms(fixture, bridge: a); let roomsB = HueClient.decodeRooms(fixture, bridge: b)
        XCTAssertEqual(roomsA.count, 2); XCTAssertEqual(roomsA.first { !$0.isZone }?.lightIDs, ["A:1","A:2"])
        XCTAssertTrue(Set(roomsA.map(\.id)).isDisjoint(with: roomsB.map(\.id)))
        let lights = ["1": ["name": "Spot", "state": ["reachable": true, "hue": 0]]] as [String: [String: Any]]
        XCTAssertNotEqual(HueClient.decodeLights(lights, bridge: a).first?.id, HueClient.decodeLights(lights, bridge: b).first?.id)
    }
    func testDimmableLightDoesNotInheritSyntheticColorFields() {
        let bridge = HueBridge(id: "A", ip: "192.0.2.1", name: "A")
        let records: [String: [String: Any]] = [
            "1": ["type": "Dimmable light", "state": ["hue": 0, "xy": [0.0, 0.0]]],
            "2": ["type": "Extended color light", "state": ["hue": 0]],
            "3": ["type": "Color temperature light", "state": ["ct": 350]]]
        let lights = HueClient.decodeLights(records, bridge: bridge)
        XCTAssertEqual(lights.first { $0.number == "1" }?.color, false)
        XCTAssertEqual(lights.first { $0.number == "2" }?.color, true)
        XCTAssertEqual(lights.first { $0.number == "3" }?.color, false)
    }
    func testIdentifyUsesOnlyOneShotAlertOnEachLightsOwnBridge() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { "test-key-\($0)" })
        for (id, host) in [("A", "192.0.2.1"), ("B", "192.0.2.2")] {
            let bridge = HueBridge(id: id, ip: host, name: id)
            let light = HueLight(id: "\(id):7", bridgeID: id, number: "7", name: "Spot", reachable: true, color: true)
            try await client.identify(light, bridge: bridge)
        }
        let requests = HueProtocol.recorded()
        XCTAssertEqual(requests.count, 2)
        for (request, id) in zip(requests, ["A", "B"]) {
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.host, id == "A" ? "192.0.2.1" : "192.0.2.2")
            XCTAssertEqual(request.url?.path, "/api/test-key-\(id)/lights/7/state")
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 256)
                let count = stream.read(&bytes, maxLength: bytes.count); data = Data(bytes.prefix(max(0, count)))
            }
            XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: String], ["alert": "select"], "Never overwrite on/off, brightness or color during identification")
        }
        let wrong = HueLight(id: "B:7", bridgeID: "B", number: "7", name: "Spot", reachable: true, color: true)
        do { try await client.identify(wrong, bridge: HueBridge(id: "A", ip: "192.0.2.1", name: "A")); XCTFail("Wrong bridge must be rejected") } catch { }
        XCTAssertEqual(HueProtocol.recorded().count, 2)
    }
    func testTransientInternalErrorRetriesButPersistentFailureSurfaces() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { _ in "test-key" })
        let bridge = HueBridge(id: "A", ip: "192.0.2.1", name: "A")
        let light = HueLight(id: "A:1", bridgeID: "A", number: "1", name: "Spot", reachable: true, color: true)
        HueProtocol.failNext(1)
        try await client.set(light, bridge: bridge, on: false)
        XCTAssertEqual(HueProtocol.recorded().count, 2)
        HueProtocol.reset(); HueProtocol.failNext(3)
        do { try await client.set(light, bridge: bridge, on: false); XCTFail("A persistent bridge failure must remain visible") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Internal error")) }
        XCTAssertEqual(HueProtocol.recorded().count, 3)
    }
    func testBlackoutOmitsColorAndOffRestoreRestoresValuesBeforePower() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { _ in "test-key" })
        let bridge = HueBridge(id: "A", ip: "192.0.2.1", name: "A")
        let light = HueLight(id: "A:1", bridgeID: "A", number: "1", name: "Spot", reachable: true, color: true)
        try await client.set(light, bridge: bridge, on: false, brightness: 0, hue: 180)
        let original: [String: Any] = ["on": false, "bri": 91, "ct": 350, "alert": "none", "transitiontime": 0]
        try await client.restore(HueSnapshot(light: light, bridge: bridge, key: "test-key", state: original))
        let bodies = try HueProtocol.recorded().map { request -> [String: Any] in
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&bytes, maxLength: bytes.count); data = Data(bytes.prefix(max(0, count)))
            }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[0]["on"] as? Bool, false)
        for body in bodies where body["on"] as? Bool == false {
            for field in ["bri", "hue", "sat", "ct", "xy", "effect"] { XCTAssertNil(body[field], "Hue rejects value changes while off") }
        }
        XCTAssertEqual(bodies[1]["on"] as? Bool, true)
        XCTAssertEqual(bodies[1]["bri"] as? Int, 91)
        XCTAssertEqual(bodies[1]["ct"] as? Int, 350)
        XCTAssertEqual(bodies[2]["on"] as? Bool, false)
    }
    func testCommandsAndRestoreUseEachBridgesOwnHostAndCredential() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { "test-key-\($0)" })
        for bridgeID in ["A","B"] {
            let bridge = HueBridge(id: bridgeID, ip: bridgeID == "A" ? "192.0.2.1" : "192.0.2.2", name: "Hue")
            let light = HueLight(id: "\(bridgeID):1", bridgeID: bridgeID, number: "1", name: "Spot", reachable: true, color: true)
            let snapshot = try await client.snapshot(light, bridge: bridge)
            try await client.set(light, bridge: bridge, on: true, brightness: 40, hue: 0)
            try await client.restore(snapshot)
        }
        let requests = HueProtocol.recorded()
        XCTAssertEqual(requests.count, 6)
        for (index, bridgeID) in ["A","B"].enumerated() {
            let own = Array(requests[(index*3)..<(index*3+3)])
            XCTAssertTrue(own.allSatisfy { $0.url?.host == (bridgeID == "A" ? "192.0.2.1" : "192.0.2.2") && $0.url!.path.contains("test-key-\(bridgeID)/lights/1") })
            XCTAssertEqual(own.map { $0.httpMethod! }, ["GET","PUT","PUT"])
        }
    }
}

extension MultiBridgeTests {
    @MainActor func testSlowBridgeDoesNotReplayFlickerBacklogBeyondClipEnd() async throws {
        HueProtocol.reset(); HueProtocol.delayWrites(0.06)
        defer { HueProtocol.reset() }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { _ in "test-key" })
        let bridge = HueBridge(id: "A", ip: "192.0.2.1", name: "A")
        let lights = (1...3).map { HueLight(id: "A:\($0)", bridgeID: "A", number: "\($0)", name: "Light", reachable: true, color: true) }
        var flicker = SceneStep(kind: .flicker, seconds: 0.4); flicker.startTime = 0; flicker.hueEffect = .ghostFlicker
        var blackout = SceneStep(kind: .blackout, seconds: 0.1); blackout.startTime = 0.5
        var scene = HorrorScene(steps: [flicker, blackout]); scene.lightIDs = Set(lights.map(\.id))
        let runner = SceneRunner(hue: client)
        runner.start(scene, speakers: [], lights: lights, bridges: [bridge], sounds: [:], folder: FileManager.default.temporaryDirectory)
        for _ in 0..<100 { if !runner.running { break }; try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertFalse(runner.running, "Expired flicker frames must not prolong playback on a slow bridge")
        if runner.running { runner.stop() }
    }
    @MainActor func testKeepLampColorChangesBrightnessWithoutAnyColorCommandAndRestoresBothBridges() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { "test-key-\($0)" })
        let runner = SceneRunner(hue: client)
        let bridges = [HueBridge(id: "A", ip: "192.0.2.1", name: "A"), HueBridge(id: "B", ip: "192.0.2.2", name: "B")]
        let lights = bridges.map { HueLight(id: "\($0.id):1", bridgeID: $0.id, number: "1", name: "Spot", reachable: true, color: true) }
        var step = SceneStep(kind: .flicker, seconds: 0.65); step.startTime = 0; step.useLampColor = true; step.hueEffect = .ghostFlicker
        var scene = HorrorScene(steps: [step]); scene.lightIDs = Set(lights.map(\.id))
        runner.start(scene, speakers: [], lights: lights, bridges: bridges, sounds: [:], folder: FileManager.default.temporaryDirectory)
        for _ in 0..<150 { if !runner.running { break }; try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertFalse(runner.running)
        for host in ["192.0.2.1", "192.0.2.2"] {
            let commands = HueProtocol.recorded().filter { $0.url?.host == host && $0.httpMethod == "PUT" }
            XCTAssertGreaterThan(commands.count, 1)
            for request in commands.dropLast() {
                let data: Data
                if let body = request.httpBody { data = body }
                else { let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 4096); let n = stream.read(&bytes, maxLength: bytes.count); data = Data(bytes.prefix(max(0, n))) }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertNotNil(body["on"])
                if body["on"] as? Bool == true { XCTAssertNotNil(body["bri"]) }
                for colorField in ["hue", "sat", "xy", "ct"] { XCTAssertNil(body[colorField], "Must preserve each lamp's own color") }
            }
        }
    }
    @MainActor func testParallelBridgeScenesPauseAndRemoveRestoreOnlyTheirOwnLight() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { "test-key-\($0)" })
        let playback = PlaybackCoordinator(makeRunner: { SceneRunner(hue: client) })
        let bridges = [HueBridge(id: "A", ip: "192.0.2.1", name: "A"), HueBridge(id: "B", ip: "192.0.2.2", name: "B")]
        let lights = bridges.map { HueLight(id: "\($0.id):1", bridgeID: $0.id, number: "1", name: "Spot", reachable: true, color: true) }
        var effect = SceneStep(kind: .flicker, seconds: 2); effect.startTime = 0; effect.hueEffect = .heartbeat
        var a = HorrorScene(name: "A", steps: [effect]); a.lightIDs = ["A:1"]
        var b = a; b.id = UUID(); b.name = "B"; b.lightIDs = ["B:1"]
        let first = try XCTUnwrap(playback.start(a, speakers: [], lights: lights, bridges: bridges, sounds: [:], folder: FileManager.default.temporaryDirectory))
        let second = try XCTUnwrap(playback.start(b, speakers: [], lights: lights, bridges: bridges, sounds: [:], folder: FileManager.default.temporaryDirectory))
        try await Task.sleep(for: .milliseconds(90)); first.runner.pause()
        try await Task.sleep(for: .milliseconds(70))
        let frozen = HueProtocol.recorded().filter { $0.url?.host == "192.0.2.1" && $0.httpMethod == "PUT" }.count
        var conflict = a; conflict.id = UUID()
        XCTAssertNil(playback.start(conflict, speakers: [], lights: lights, bridges: bridges, sounds: [:], folder: FileManager.default.temporaryDirectory))
        for _ in 0..<150 { if !second.runner.running { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(second.runner.running); XCTAssertTrue(first.runner.running); XCTAssertTrue(first.runner.paused)
        XCTAssertEqual(HueProtocol.recorded().filter { $0.url?.host == "192.0.2.1" && $0.httpMethod == "PUT" }.count, frozen)
        let completedB = HueProtocol.recorded().filter { $0.url?.host == "192.0.2.2" }.count
        first.runner.resume()
        for _ in 0..<60 { if HueProtocol.recorded().filter({ $0.url?.host == "192.0.2.1" && $0.httpMethod == "PUT" }).count > frozen { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertGreaterThan(HueProtocol.recorded().filter { $0.url?.host == "192.0.2.1" && $0.httpMethod == "PUT" }.count, frozen)
        first.runner.pause(); try await Task.sleep(for: .milliseconds(40))
        let beforeRemove = HueProtocol.recorded().filter { $0.url?.host == "192.0.2.1" && $0.httpMethod == "PUT" }.count
        playback.remove(first.id)
        for _ in 0..<80 { if !first.runner.running { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(first.runner.running)
        XCTAssertEqual(HueProtocol.recorded().filter { $0.url?.host == "192.0.2.2" }.count, completedB)
        XCTAssertEqual(HueProtocol.recorded().filter { $0.url?.host == "192.0.2.1" && $0.httpMethod == "PUT" }.count, beforeRemove + 1, "Only state restoration after removal")
    }
    @MainActor func testTimelineRunnerSendsWhiteFlashesToTwoBridgesAndRestoresBoth() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let client = HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { "test-key-\($0)" })
        let runner = SceneRunner(hue: client)
        let bridges = [HueBridge(id: "A", ip: "192.0.2.1", name: "A"), HueBridge(id: "B", ip: "192.0.2.2", name: "B")]
        let lights = bridges.map { HueLight(id: "\($0.id):1", bridgeID: $0.id, number: "1", name: "Spot", reachable: true, color: true) }
        var flash = SceneStep(kind: .flicker, seconds: 1.6); flash.startTime = 0; flash.hueEffect = .lightning; flash.hue = 230
        var scene = HorrorScene(steps: [flash]); scene.lightIDs = Set(lights.map(\.id))
        runner.start(scene, speakers: [], lights: lights, bridges: bridges, sounds: [:], folder: FileManager.default.temporaryDirectory)
        for _ in 0..<150 { if !runner.running { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(runner.running); XCTAssertTrue(runner.status.contains("beendet"), runner.status)
        let requests = HueProtocol.recorded()
        for host in ["192.0.2.1", "192.0.2.2"] {
            let own = requests.filter { $0.url?.host == host }
            XCTAssertEqual(own.first?.httpMethod, "GET")
            let bodies = try own.filter { $0.httpMethod == "PUT" }.map { request -> [String: Any] in
                let data: Data
                if let body = request.httpBody { data = body }
                else { let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 4096); let count = stream.read(&bytes, maxLength: bytes.count); data = Data(bytes.prefix(max(0, count))) }
                return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            }
            XCTAssertTrue(bodies.dropLast().contains { ($0["sat"] as? Int) == 0 && ($0["bri"] as? Int) == 152 })
            XCTAssertEqual(bodies.last?["bri"] as? Int, 91); XCTAssertEqual(bodies.last?["hue"] as? Int, 4000)
        }
    }
    @MainActor func testTimelineStopRestoresAndDoesNotSendFutureLightCue() async throws {
        HueProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HueProtocol.self]
        let runner = SceneRunner(hue: HueClient(network: NetworkClient(session: URLSession(configuration: config)), credential: { "test-key-\($0)" }))
        let bridge = HueBridge(id: "A", ip: "192.0.2.1", name: "A"), light = HueLight(id: "A:1", bridgeID: "A", number: "1", name: "Spot", reachable: true, color: true)
        var flicker = SceneStep(kind: .flicker, seconds: 5); flicker.startTime = 0
        var future = SceneStep(kind: .blackout, seconds: 1); future.startTime = 6
        var scene = HorrorScene(steps: [flicker, future]); scene.lightIDs = [light.id]
        runner.start(scene, speakers: [], lights: [light], bridges: [bridge], sounds: [:], folder: FileManager.default.temporaryDirectory)
        try await Task.sleep(for: .milliseconds(100)); runner.stop()
        for _ in 0..<100 { if !runner.running { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(runner.running); XCTAssertTrue(runner.status.contains("Gestoppt"), runner.status)
        XCTAssertEqual(HueProtocol.recorded().filter { $0.httpMethod == "PUT" }.count, 2, "Only first effect frame and state restoration should run")
    }
}
