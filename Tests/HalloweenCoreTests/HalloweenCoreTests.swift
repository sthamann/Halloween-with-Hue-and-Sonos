import XCTest
@testable import HalloweenCore

final class HalloweenCoreTests: XCTestCase {
    func testRangeRequestsDoNotReplayOrServeWrongBytes() {
        let data = Data((0..<100).map(UInt8.init))
        let part = HTTPAudioResponse.make(data: data, mime: "audio/wav", method: "GET", range: "bytes=10-19")
        XCTAssertEqual(part.status, 206); XCTAssertEqual(part.body, data.subdata(in: 10..<20)); XCTAssertEqual(part.headers["Content-Range"], "bytes 10-19/100")
        let suffix = HTTPAudioResponse.make(data: data, mime: "audio/wav", method: "GET", range: "bytes=-7")
        XCTAssertEqual(suffix.body, data.suffix(7))
        let open = HTTPAudioResponse.make(data: data, mime: "audio/wav", method: "GET", range: "bytes=97-")
        XCTAssertEqual(open.body, data.suffix(3))
    }
    func testInvalidRangesAndHead() {
        for range in ["bytes=1000-", "bytes=20-10", "bytes=-0", "bytes=0-1,4-5", "bytes=x-y", "items=2-3"] {
            XCTAssertEqual(HTTPAudioResponse.make(data: Data([1,2,3]), mime: "audio/wav", method: "GET", range: range).status, 416)
        }
        let head = HTTPAudioResponse.make(data: Data([1,2,3]), mime: "audio/wav", method: "HEAD", range: nil)
        XCTAssertTrue(head.body.isEmpty); XCTAssertEqual(head.headers["Content-Length"], "3")
        XCTAssertEqual(HTTPAudioResponse.make(data: Data([1]), mime: "audio/wav", method: "POST", range: nil).status, 405)
    }
    func testTopologyEmbeddedInSOAPIsDecodedWithoutLosingSatellites() throws {
        let source = "<s:Envelope xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'><s:Body><u:GetZoneGroupStateResponse xmlns:u='urn:schemas-upnp-org:service:ZoneGroupTopology:1'><ZoneGroupState>&lt;ZoneGroupState&gt;&lt;ZoneGroups&gt;&lt;ZoneGroup Coordinator='ARC'&gt;&lt;ZoneGroupMember UUID='ARC' ZoneName='Wohnzimmer'&gt;&lt;Satellite UUID='SUB'/&gt;&lt;/ZoneGroupMember&gt;&lt;/ZoneGroup&gt;&lt;/ZoneGroups&gt;&lt;/ZoneGroupState&gt;</ZoneGroupState></u:GetZoneGroupStateResponse></s:Body></s:Envelope>"
        let root = try XMLTree.parse(Data(source.utf8)); let topology = try XMLTree.parse(Data(root.value("ZoneGroupState").utf8))
        XCTAssertEqual(topology.all("ZoneGroupMember").count, 1); XCTAssertEqual(topology.all("Satellite").first?.attributes["UUID"], "SUB")
        XCTAssertThrowsError(try XMLTree.parse(Data("<invalid>".utf8)))
    }
    func testWaveFileHasCorrectPCMHeaderAndClampsSamples() {
        let data = WaveWriter.data(samples: [-2,0,2], sampleRate: 22050)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(data.count, 44 + 6); XCTAssertEqual(String(data: data.subdata(in: 36..<40), encoding: .ascii), "data")
        XCTAssertEqual(data.subdata(in: 40..<44), Data([6,0,0,0]))
    }
    func testAudioServerServesAnActualRangedRequestAndRejectsOtherPaths() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sound.wav"); let data = WaveWriter.data(samples: [0,0.1,-0.1], sampleRate: 22050); try data.write(to: file)
        let server = AudioServer(); try await server.start(); defer { server.stop() }
        let url = server.serve(file); var request = URLRequest(url: url); request.setValue("bytes=0-11", forHTTPHeaderField: "Range")
        let (body, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 206); XCTAssertEqual(body, data.prefix(12)); XCTAssertEqual(server.requestCount(url), 1)
        XCTAssertEqual(server.requestCount(url, from: LocalNetwork.hostAddress!), 1)
        let other = url.deletingLastPathComponent().appendingPathComponent("scenes.json"); let (_, rejected) = try await URLSession.shared.data(from: other)
        XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 404)
    }
    @MainActor func testSpeechIsRenderedToNetworkPlayableWaveWithoutPlayback() async throws {
        let url = try await SpeechRenderer().render("Jana", folder: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertGreaterThan(data.count, 44_000)
    }
    @MainActor func testSceneWithoutTargetsCannotStartPlayback() async throws {
        let runner = SceneRunner(); let scene = HorrorScene(steps: [SceneStep()])
        runner.start(scene, speakers: [], lights: [], bridges: [], sounds: [:], folder: FileManager.default.temporaryDirectory)
        for _ in 0..<20 { if !runner.running { break }; try await Task.sleep(nanoseconds: 30_000_000) }
        XCTAssertFalse(runner.running); XCTAssertTrue(runner.status.contains("auswählen"))
    }
    func testLiveNetworkReadOnly() async throws {
        guard ProcessInfo.processInfo.environment["HAUNT_LIVE_READONLY"] == "1" else { throw XCTSkip("Nur mit HAUNT_LIVE_READONLY=1: lokale Geräte lesen, keine Wiedergabe oder Lichtänderung.") }
        let sonos = SonosClient(); let hue = HueClient(); var found: [Speaker] = []; var bridges: [HueBridge] = []
        let hosts = LocalNetwork.hosts()
        for start in stride(from: 0, to: hosts.count, by: 32) {
            await withTaskGroup(of: (Speaker?, HueBridge?).self) { group in
                for ip in hosts[start..<min(start+32, hosts.count)] { group.addTask { async let s = sonos.probe(ip); async let h = hue.probe(ip); return await (s, h) } }
                for await (speaker, bridge) in group { if let speaker { found.append(speaker) }; if let bridge { bridges.append(bridge) } }
            }
        }
        XCTAssertFalse(found.isEmpty); let topology = try await sonos.topology(found); let rooms = topology.filter { !$0.isSatellite }
        for room in rooms { let state = try await sonos.state(room); XCTAssertFalse(state.isEmpty) }
        print("LIVE READONLY: \(topology.count) Sonos-Geräte / \(rooms.count) Räume; Hue: \(bridges.map { $0.name + "@" + $0.ip }.joined(separator: ", "))")
    }
}
