import XCTest
@testable import HalloweenCore

final class AutomationTests: XCTestCase {
    @MainActor func testStartHistoryPersistsAndRejectedStartDoesNotCount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(directory: directory)
        let scene = HorrorScene(steps: [SceneStep(kind: .wait, seconds: 10)])
        XCTAssertNil(store.lastStarts[scene.id.uuidString])
        XCTAssertTrue(store.run(scene))
        let first = try XCTUnwrap(store.lastStarts[scene.id.uuidString])
        XCTAssertFalse(store.run(scene))
        XCTAssertEqual(store.lastStarts[scene.id.uuidString], first)
        let ruleID = UUID()
        store.recordStart(ruleID)
        let restored = AppStore(directory: directory)
        XCTAssertEqual(restored.lastStarts, store.lastStarts)
        store.playback.stopAll()
    }
    func testWeekdayClockIntervalOnceAndOvernightWindowDoNotCatchUpOrRepeat() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 20, minute: 0))!
        var rule = AutomationRule(sceneID: UUID()); rule.enabled = true; rule.weekdays = [2]; rule.hour = 20
        var gate = TriggerGate()
        XCTAssertEqual(gate.scheduled([rule], now: now, calendar: calendar).count, 1)
        XCTAssertTrue(gate.scheduled([rule], now: now.addingTimeInterval(0.6), calendar: calendar).isEmpty)
        XCTAssertTrue(gate.scheduled([rule], now: now.addingTimeInterval(86_400), calendar: calendar).isEmpty)
        rule.kind = .interval; rule.date = now; rule.interval = 60
        XCTAssertTrue(gate.scheduled([rule], now: now.addingTimeInterval(35), calendar: calendar).isEmpty)
        XCTAssertEqual(gate.scheduled([rule], now: now.addingTimeInterval(60), calendar: calendar).count, 1)
        XCTAssertTrue(gate.scheduled([rule], now: now.addingTimeInterval(60.5), calendar: calendar).isEmpty)
        rule.kind = .once; rule.date = now.addingTimeInterval(120)
        XCTAssertEqual(gate.scheduled([rule], now: rule.date, calendar: calendar).count, 1)
        XCTAssertTrue(gate.scheduled([rule], now: rule.date.addingTimeInterval(8), calendar: calendar).isEmpty)
        rule.windowEnabled = true; rule.windowStart = 22 * 60; rule.windowEnd = 2 * 60
        XCTAssertTrue(rule.isInsideWindow(now.addingTimeInterval(4 * 3600), calendar: calendar))
        XCTAssertFalse(rule.isInsideWindow(now, calendar: calendar))
    }
    func testMotionEdgesCooldownReconnectAndSameIDsOnTwoBridges() {
        let now = Date(); var a = AutomationRule(sceneID: UUID()); a.enabled = true; a.kind = .hue; a.sourceID = "A:motion:1"; a.cooldown = 5
        var b = a; b.id = UUID(); b.sourceID = "B:motion:1"
        var gate = TriggerGate(); gate.prime([HueInputEvent(sourceID: a.sourceID, event: "motion", token: "old", value: 0), HueInputEvent(sourceID: b.sourceID, event: "motion", token: "old", value: 0)])
        let move = HueInputEvent(sourceID: a.sourceID, event: "motion", token: "new", value: 1)
        XCTAssertEqual(gate.receive(move, rules: [a,b], now: now).map(\.id), [a.id])
        XCTAssertTrue(gate.receive(move, rules: [a,b], now: now.addingTimeInterval(1)).isEmpty)
        XCTAssertTrue(gate.receive(HueInputEvent(sourceID: a.sourceID, event: "motion", token: "true-again", value: 1), rules: [a], now: now.addingTimeInterval(6)).isEmpty)
        _ = gate.receive(HueInputEvent(sourceID: a.sourceID, event: "no_motion", token: "false", value: 0), rules: [a], now: now.addingTimeInterval(2))
        XCTAssertTrue(gate.receive(HueInputEvent(sourceID: a.sourceID, event: "motion", token: "quick", value: 1), rules: [a], now: now.addingTimeInterval(3)).isEmpty)
        gate.prime([HueInputEvent(sourceID: a.sourceID, event: "motion", token: "reconnect", value: 1)])
        XCTAssertTrue(gate.receive(HueInputEvent(sourceID: a.sourceID, event: "motion", token: "reconnected-true", value: 1), rules: [a], now: now.addingTimeInterval(20)).isEmpty)
        XCTAssertEqual(gate.receive(HueInputEvent(sourceID: b.sourceID, event: "motion", token: "b", value: 1), rules: [a,b], now: now).map(\.id), [b.id])
    }
    func testSSEFramesMotionAwareButtonsRotaryContactAndLightThresholds() throws {
        let resources: [[String: Any]] = [
            ["id": "area", "type": "service_group", "metadata": ["name": "Lounge"]],
            ["id": "config", "type": "motion_area_configuration", "motion_sensors": [["rid": "m", "rtype": "motion"]]],
            ["id": "m", "type": "motion", "owner": ["rid": "area", "rtype": "service_group"], "motion": ["motion": false, "motion_valid": true]],
            ["id": "b", "type": "button", "metadata": ["control_id": 2], "button": ["button_report": ["event": "short_release", "updated": "old"]]],
            ["id": "r", "type": "relative_rotary", "relative_rotary": ["rotary_report": ["updated": "old", "rotation": ["direction": "clock_wise"]]]],
            ["id": "c", "type": "contact", "contact_report": ["state": "contact", "changed": "old"]],
            ["id": "l", "type": "light_level", "light": ["light_level": 20_001, "light_level_valid": true]]
        ]
        let inventory = try HueEventClient.decodeInventory(JSONSerialization.data(withJSONObject: ["errors": [], "data": resources]), bridgeID: "A")
        XCTAssertEqual(inventory.inputs.count, 5); XCTAssertTrue(inventory.inputs.first { $0.resourceID == "m" }!.name.contains("MotionAware"))
        XCTAssertEqual(inventory.baseline.first { $0.sourceID == "A:light_level:l" }?.value, 100)
        var gate = TriggerGate(); gate.prime(inventory.baseline)
        var button = AutomationRule(sceneID: UUID()); button.kind = .hue; button.enabled = true; button.sourceID = "A:button:b"; button.event = "short_release"
        let update: [[String: Any]] = [["id": "event-1", "type": "update", "data": [["id": "b", "type": "button", "button": ["button_report": ["event": "short_release", "updated": "new"]]]]]]
        let payload = try JSONSerialization.data(withJSONObject: update)
        var decoder = HueSSEDecoder(); var frames: [Data] = []
        let wire = Data(": heartbeat\r\nid: event-1\r\ndata: ".utf8) + payload + Data("\r\n\r\n".utf8)
        for byte in wire { frames += try decoder.append(byte) }
        XCTAssertEqual(frames, [payload])
        let events = try HueEventClient.decodeUpdates(frames[0], bridgeID: "A")
        XCTAssertEqual(gate.receive(events[0], rules: [button], now: Date()).count, 1)
        XCTAssertTrue(gate.receive(events[0], rules: [button], now: Date().addingTimeInterval(31)).isEmpty)
        var dark = button; dark.id = UUID(); dark.sourceID = "A:light_level:l"; dark.event = "dark"; dark.threshold = 10
        XCTAssertEqual(gate.receive(HueInputEvent(sourceID: dark.sourceID, event: "light_level", token: "d", value: 5), rules: [dark], now: Date()).count, 1)
        XCTAssertTrue(gate.receive(HueInputEvent(sourceID: dark.sourceID, event: "light_level", token: "d2", value: 4), rules: [dark], now: Date().addingTimeInterval(31)).isEmpty)
    }
    func testBridgeProMotionAwareServicesWithoutPhysicalMotionSensor() throws {
        let resources: [[String: Any]] = [
            ["id": "config", "type": "motion_area_configuration", "name": "Lounge", "services": [["rid": "area", "rtype": "convenience_area_motion"]]],
            ["id": "area", "type": "convenience_area_motion", "owner": ["rid": "config", "rtype": "motion_area_configuration"], "enabled": true, "motion": ["motion": false, "motion_valid": true]],
            ["id": "unavailable", "type": "security_area_motion", "enabled": false]
        ]
        let inventory = try HueEventClient.decodeInventory(JSONSerialization.data(withJSONObject: ["errors": [], "data": resources]), bridgeID: "PRO")
        XCTAssertEqual(inventory.inputs.first { $0.resourceID == "area" }?.name, "Lounge · MotionAware")
        var rule = AutomationRule(sceneID: UUID()); rule.enabled = true; rule.kind = .hue; rule.sourceID = "PRO:convenience_area_motion:area"
        var gate = TriggerGate(); gate.prime(inventory.baseline)
        let update: [[String: Any]] = [["id": "event", "type": "update", "data": [["id": "area", "type": "convenience_area_motion", "motion": ["motion": true, "motion_valid": true]]]]]
        let events = try HueEventClient.decodeUpdates(JSONSerialization.data(withJSONObject: update), bridgeID: "PRO")
        XCTAssertEqual(gate.receive(events[0], rules: [rule], now: Date()).map(\.id), [rule.id])
        XCTAssertTrue(gate.receive(events[0], rules: [rule], now: Date().addingTimeInterval(60)).isEmpty)
    }
    @MainActor func testActualTimerStartsSavedSceneOnceAndStopsOnForegroundLoss() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(directory: directory)
        store.scenes = [HorrorScene(name: "Clock test", steps: [SceneStep(kind: .wait, seconds: 0.1)])]
        var rule = AutomationRule(sceneID: store.scenes[0].id); rule.kind = .once; rule.enabled = true; rule.date = Date().addingTimeInterval(0.2)
        store.rules = [rule]; store.save(); store.setAutomation(true)
        for _ in 0..<60 { if !store.automation.log.isEmpty && !store.runner.running { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.automation.log.count, 1); XCTAssertFalse(store.rules[0].enabled)
        XCTAssertTrue(store.runner.status.contains("beendet") || store.runner.status.contains("finished"), store.runner.status)
        store.setForeground(false); XCTAssertFalse(store.automation.active)
        store.setForeground(true); XCTAssertTrue(store.automation.active)
        store.stopAll(); XCTAssertFalse(store.automationEnabled); XCTAssertFalse(store.automation.active)
        store.openSceneURL(URL(string: "haunt://scene/\(store.scenes[0].id.uuidString)")!)
        XCTAssertTrue(store.runner.running, "A Shortcuts URL must reach the actual saved-scene runner")
        for _ in 0..<30 { if !store.runner.running { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(store.runner.running)
    }
    @MainActor func testPortableArchiveIncludesCustomAudioRulesAndRestoresAfterColdLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(directory: directory)
        var speech = SceneStep(kind: .speech); speech.text = "Jana, I am here."; speech.speechLanguage = "en-US"; speech.startTime = 2
        let clip = SoundClip(id: "own", name: "My sound", filename: "own.wav", duration: 0.1)
        let data = WaveWriter.data(samples: [Float](repeating: 0.1, count: 2205), sampleRate: 22050)
        try data.write(to: directory.appendingPathComponent("Sounds/own.wav")); store.sounds = [clip]
        var scene = HorrorScene(name: "Portable", steps: [SceneStep(kind: .sound, soundID: clip.id), speech]); scene.roomIDs = ["room"]; scene.lightIDs = ["A:1", "B:1"]
        var rule = AutomationRule(sceneID: scene.id); rule.enabled = true; rule.kind = .hue; rule.sourceID = "B:motion:1"
        store.scenes = [scene]; store.rules = [rule]; store.save()
        let archived = try store.archive(scene); XCTAssertEqual(archived.sounds[0].data, data)
        let imported = try store.importArchive(JSONEncoder().encode(archived))
        XCTAssertNotEqual(imported.id, scene.id); XCTAssertEqual(imported.lightIDs, scene.lightIDs); XCTAssertEqual(imported.steps[1].speechLanguage, "en-US")
        let importedRule = try XCTUnwrap(store.rules.first { $0.sceneID == imported.id }); XCTAssertFalse(importedRule.enabled); XCTAssertEqual(importedRule.sourceID, rule.sourceID)
        XCTAssertNotEqual(imported.steps[0].soundID, clip.id)
        let restored = AppStore(directory: directory)
        XCTAssertEqual(restored.scenes, store.scenes); XCTAssertEqual(restored.rules, store.rules); XCTAssertFalse(restored.automationEnabled)
        XCTAssertEqual(try Data(contentsOf: restored.soundURL(restored.sounds.first { $0.id == imported.steps[0].soundID }!)), data)
        XCTAssertEqual(try SceneArchive.decode(JSONEncoder().encode(scene)).scene, scene, "Old plain JSON remains importable")
    }
    func testImportRejectsInvalidDurationsAndUnknownPackageVersion() throws {
        var scene = HorrorScene(steps: [SceneStep()]); scene.steps[0].startTime = -1
        XCTAssertThrowsError(try SceneArchive(scene: scene).validate())
        var archive = SceneArchive(scene: HorrorScene(steps: [SceneStep()])); archive.version = 99
        XCTAssertThrowsError(try SceneArchive.decode(JSONEncoder().encode(archive)))
    }
    func testBothLanguagesInterpolationAndSpeechDefaults() {
        let previous = L10n.language; defer { L10n.language = previous }
        L10n.language = .english
        XCTAssertEqual(L10n.value("Sonos-Räume · \(3) ausgewählt"), "Sonos rooms · 3 selected")
        XCTAssertEqual(L10n.text("Geisterhaftes Flackern"), "Ghostly flicker")
        XCTAssertEqual(L10n.speechLanguage, "en-US")
        XCTAssertEqual(L10n.value("\("%@") / \("second")"), "%@ / second")
        L10n.language = .german
        XCTAssertEqual(L10n.text("Automation off"), "Automatik ausgeschaltet")
        XCTAssertEqual(L10n.value("Sonos-Räume · \(3) ausgewählt"), "Sonos-Räume · 3 ausgewählt")
        XCTAssertEqual(L10n.speechLanguage, "de-DE")
        XCTAssertEqual(HueTLS.anchors.count, 2)
    }
}
