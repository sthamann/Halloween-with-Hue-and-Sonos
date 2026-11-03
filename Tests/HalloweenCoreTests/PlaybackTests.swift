import XCTest
@testable import HalloweenCore

final class PlaybackTests: XCTestCase {
    @MainActor func testIndependentRunsPauseResumeStopAndRemoveWithoutAffectingOtherRun() async throws {
        let playback = PlaybackCoordinator()
        let a = HorrorScene(name: "A", steps: [SceneStep(kind: .wait, seconds: 0.7)])
        let b = HorrorScene(name: "B", steps: [SceneStep(kind: .wait, seconds: 1.2)])
        let first = try XCTUnwrap(playback.start(a, speakers: [], lights: [], bridges: [], sounds: [:], folder: FileManager.default.temporaryDirectory))
        let second = try XCTUnwrap(playback.start(b, speakers: [], lights: [], bridges: [], sounds: [:], folder: FileManager.default.temporaryDirectory))
        XCTAssertEqual(playback.active.count, 2)
        XCTAssertNil(playback.start(a, speakers: [], lights: [], bridges: [], sounds: [:], folder: FileManager.default.temporaryDirectory))
        try await Task.sleep(for: .milliseconds(100)); first.runner.pause()
        try await Task.sleep(for: .milliseconds(60)); let frozen = first.runner.elapsed
        try await Task.sleep(for: .milliseconds(240))
        XCTAssertTrue(first.runner.paused); XCTAssertEqual(first.runner.elapsed, frozen, accuracy: 0.02)
        XCTAssertGreaterThan(second.runner.elapsed, frozen + 0.15)
        first.runner.resume(); try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(first.runner.paused); XCTAssertGreaterThan(first.runner.elapsed, frozen)
        first.runner.pause(); try await Task.sleep(for: .milliseconds(50)); playback.remove(first.id)
        for _ in 0..<40 { if !playback.sessions.contains(where: { $0.id == first.id }) { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(playback.sessions.contains { $0.id == first.id }); XCTAssertTrue(second.runner.running)
        playback.stopAll()
        for _ in 0..<40 { if !playback.running { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(playback.running)
        playback.remove(second.id); XCTAssertTrue(playback.sessions.isEmpty)
    }
    func testReservationsUseActualStepTargetsAndBridgeQualifiedLampIDs() {
        var audio = SceneStep(kind: .sound); audio.roomIDs = ["Lounge"]
        var light = SceneStep(kind: .flicker); light.lightIDs = ["A:1"]
        var a = HorrorScene(steps: [audio, light]); a.roomIDs = ["UnusedRoom"]; a.lightIDs = ["UnusedLight"]
        let resources = SceneResources(scene: a)
        XCTAssertEqual(resources.rooms, ["Lounge"]); XCTAssertEqual(resources.lights, ["A:1"])
        var b = a; b.id = UUID(); b.steps[0].roomIDs = ["Kitchen"]; b.steps[1].lightIDs = ["B:1"]
        XCTAssertFalse(resources.overlaps(SceneResources(scene: b)))
        b.steps[0].roomIDs = ["Lounge"]; XCTAssertTrue(resources.overlaps(SceneResources(scene: b)))
        b.steps[0].roomIDs = ["Kitchen"]; b.steps[1].lightIDs = ["A:1"]; XCTAssertTrue(resources.overlaps(SceneResources(scene: b)))
    }
    @MainActor func testPauseAwareSchedulerDoesNotSendFutureCueOrCatchUpOnResume() async throws {
        let clock = PlaybackClock(); clock.reset()
        var a = SceneStep(kind: .wait, seconds: 0.01); a.startTime = 0.02
        var b = SceneStep(kind: .wait, seconds: 0.01); b.startTime = 0.25
        let plan = SceneTimeline(scene: HorrorScene(steps: [a,b]), soundDurations: [:])
        var events: [UUID] = []
        let task = Task { try await TimelineScheduler.run(plan, clock: clock) { events.append($0.id) } }
        try await Task.sleep(for: .milliseconds(80)); clock.pause(); let position = clock.elapsed
        try await Task.sleep(for: .milliseconds(300)); XCTAssertEqual(events, [a.id]); XCTAssertEqual(clock.elapsed, position)
        clock.resume(); try await Task.sleep(for: .milliseconds(70)); XCTAssertEqual(events, [a.id])
        try await task.value; XCTAssertEqual(events, [a.id,b.id])
    }
    @MainActor func testTwoClockTriggersStartTogetherAndDeleteStopsOnlyRelatedScene() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(directory: directory)
        let a = HorrorScene(name: "A", steps: [SceneStep(kind: .wait, seconds: 2)])
        let b = HorrorScene(name: "B", steps: [SceneStep(kind: .wait, seconds: 2)])
        store.scenes = [a,b]
        let due = Date().addingTimeInterval(0.1)
        store.rules = store.scenes.map { scene in var rule = AutomationRule(sceneID: scene.id); rule.kind = .once; rule.enabled = true; rule.date = due; return rule }
        store.setAutomation(true)
        for _ in 0..<40 { if store.playback.active.count == 2 { break }; try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(store.playback.active.count, 2); XCTAssertEqual(store.automation.log.count, 2)
        store.deleteScene(a.id)
        for _ in 0..<40 { if store.playback.runner(for: a.id) == nil { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(store.playback.runner(for: a.id)); XCTAssertNotNil(store.playback.runner(for: b.id))
        XCTAssertFalse(store.rules.contains { $0.sceneID == a.id })
        store.stopAll()
    }
}
