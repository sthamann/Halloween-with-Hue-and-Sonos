import XCTest
import AVFoundation
@testable import HalloweenCore

final class TimelineTests: XCTestCase {
    func testMigrationKeepsConcurrentLightAndExplicitWaitOffsetsAndRoundTrip() throws {
        var audio = SceneStep(kind: .sound); audio.waitForSound = false
        let light = SceneStep(kind: .flicker, seconds: 3)
        let speech = SceneStep(kind: .speech)
        let scene = HorrorScene(steps: [audio, light, SceneStep(kind: .wait, seconds: 2), speech])
        let migrated = SceneTimeline.migrating(scene, soundDurations: ["heartbeat": 8])
        XCTAssertEqual(migrated.steps.map { $0.startTime! }, [0, 0, 3, 5])
        XCTAssertEqual(try JSONDecoder().decode(HorrorScene.self, from: JSONEncoder().encode(migrated)), migrated)
        let legacy = try JSONDecoder().decode(HorrorScene.self, from: JSONEncoder().encode(scene))
        XCTAssertTrue(legacy.steps.allSatisfy { $0.startTime == nil && $0.hueEffect == nil })
    }
    func testLampOverlapIsRejectedButDifferentBridgeLightsAndAudioOverlapAreAllowed() throws {
        var a = SceneStep(kind: .flicker, seconds: 5); a.startTime = 0; a.lightIDs = ["bridgeA:1"]
        var b = a; b.id = UUID(); b.startTime = 1; b.lightIDs = ["bridgeB:1"]
        var scene = HorrorScene(steps: [a, b])
        XCTAssertNoThrow(try SceneTimeline(scene: scene, soundDurations: [:]).validate(scene: scene))
        scene.steps[1].lightIDs = ["bridgeA:1"]
        XCTAssertThrowsError(try SceneTimeline(scene: scene, soundDurations: [:]).validate(scene: scene))
        var audio = SceneStep(); audio.startTime = 0
        var other = audio; other.id = UUID(); other.startTime = 0.5
        scene = HorrorScene(steps: [audio, other])
        XCTAssertNoThrow(try SceneTimeline(scene: scene, soundDurations: ["heartbeat": 4]).validate(scene: scene))
        scene.steps[1].startTime = .nan
        XCTAssertThrowsError(try SceneTimeline(scene: scene, soundDurations: [:]).validate(scene: scene))
    }
    func testSixEffectPatternsAreBoundedAndPreviewUsesExactScheduledSamples() {
        for effect in HueEffectKind.allCases {
            let frames = effect.frames(duration: 12, brightness: 70, hue: effect.defaultHue)
            XCTAssertGreaterThan(frames.count, 5)
            for frame in frames {
                XCTAssertTrue((0...100).contains(frame.brightness)); XCTAssertTrue((0...360).contains(frame.hue)); XCTAssertTrue((0...100).contains(frame.saturation))
                XCTAssertEqual(frame, effect.sampledFrame(at: frame.time + 0.1, brightness: 70, hue: effect.defaultHue))
            }
        }
        let flashes = HueEffectKind.lightning.frames(duration: 12, brightness: 70, hue: 230)
        XCTAssertTrue(flashes.contains { $0.saturation == 0 && $0.brightness == 70 })
        XCTAssertTrue(flashes.contains { $0.brightness == 3 })
        XCTAssertTrue(HueEffectKind.heartbeat.frames(duration: 2.4, brightness: 70, hue: 0).filter { $0.brightness == 70 }.count >= 2)
    }
    func testEveryComboUsesBundledSoundsAndHasConcurrentAudioAndLight() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/HalloweenApp/Resources/Sounds")
        let catalog = try SoundLibrary.decode(Data(contentsOf: folder.appendingPathComponent("sound-catalog.json")))
        let durations = try Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, try AVAudioPlayer(contentsOf: folder.appendingPathComponent($0.filename)).duration) })
        for scene in EffectCombos.scenes {
            XCTAssertTrue(scene.steps.filter { $0.kind == .sound }.allSatisfy { durations[$0.soundID] != nil })
            XCTAssertTrue(scene.steps.contains { $0.kind == .sound && $0.startTime == 0 })
            XCTAssertTrue(scene.steps.contains { $0.kind == .flicker && $0.startTime == 0 })
            try SceneTimeline(scene: scene, soundDurations: durations).validate(scene: scene)
        }
    }
    func testMixerPlacesAudioAtAbsoluteOffsetsMixesOverlapAndAvoidsClipping() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("test.wav")
        try WaveWriter.data(samples: [Float](repeating: 0.8, count: 22_050), sampleRate: 22_050).write(to: source)
        var a = SceneStep(); a.startTime = 0.5
        var b = SceneStep(); b.startTime = 1.0
        let scene = HorrorScene(steps: [a, b]), plan = SceneTimeline(scene: scene, soundDurations: ["heartbeat": 1])
        let url = try XCTUnwrap(AudioTimelineMixer.render(entries: plan.entries, sources: [a.id: source, b.id: source], folder: folder))
        let file = try AVAudioFile(forReading: url); let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer); let pcm = buffer.floatChannelData![0]
        XCTAssertEqual(pcm[1000], 0, accuracy: 0.0001)
        let single = pcm[Int(0.75 * 22_050)], overlap = pcm[Int(1.25 * 22_050)]
        XCTAssertGreaterThan(single, 0.3); XCTAssertEqual(overlap, single * 2, accuracy: 0.002)
        XCTAssertLessThan(overlap, 0.91)
        XCTAssertEqual(pcm[Int(2.2 * 22_050)], 0, accuracy: 0.0001)
    }
    @MainActor func testSchedulerStartsConcurrentCuesAndCancellationPreventsFutureActions() async throws {
        var a = SceneStep(kind: .wait, seconds: 0.1); a.startTime = 0
        var b = SceneStep(kind: .wait, seconds: 0.1); b.startTime = 0
        var late = SceneStep(kind: .wait, seconds: 0.1); late.startTime = 0.35
        let plan = SceneTimeline(scene: HorrorScene(steps: [a, b, late]), soundDurations: [:])
        var starts: [UUID: ContinuousClock.Instant] = [:]
        let task = Task { try await TimelineScheduler.run(plan, origin: .now) { entry in starts[entry.id] = .now; try await Task.sleep(for: .milliseconds(200)) } }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { try await task.value; XCTFail("Cancellation was ignored") } catch is CancellationError { }
        XCTAssertNotNil(starts[a.id]); XCTAssertNotNil(starts[b.id]); XCTAssertNil(starts[late.id])
        let delta = starts[a.id]!.duration(to: starts[b.id]!).components
        XCTAssertEqual(delta.seconds, 0); XCTAssertLessThan(abs(Double(delta.attoseconds) / 1e18), 0.1)
    }
    @MainActor func testSpeechRenderingCancellationFinishesPromptly() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let renderer = SpeechRenderer()
        let task = Task { try await renderer.render(String(repeating: "Hallo Jana. ", count: 20), folder: folder) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled speech was rendered") } catch is CancellationError { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
    func testHorrorFlickerHasIrregularGapsDarkoutsAndDifferentLampPatterns() {
        let frames = HueEffectKind.ghostFlicker.frames(duration: 30, brightness: 70, hue: 230)
        let gaps = zip(frames, frames.dropFirst()).map { $1.time - $0.time }
        XCTAssertGreaterThan(Set(gaps.map { Int($0 * 100) }).count, 8)
        XCTAssertTrue(gaps.contains { $0 > 1.3 })
        XCTAssertTrue(frames.contains { $0.brightness == 0 })
        XCTAssertTrue(frames.contains { $0.brightness == 70 })
        let other = HueEffectKind.ghostFlicker.frames(duration: 30, brightness: 70, hue: 230, seed: HueEffectKind.seed(for: "other-lamp"))
        XCTAssertEqual(frames.map(\.time), other.map(\.time))
        XCTAssertNotEqual(frames.map(\.brightness), other.map(\.brightness))
        for effect in HueEffectKind.allCases { XCTAssertTrue(effect.frames(duration: 2, brightness: 0, hue: 0).allSatisfy { $0.brightness == 0 }) }
    }
    func testTrimmingAudioActuallyRemovesSamplesAfterTheClipEnd() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("tone.wav")
        try WaveWriter.data(samples: [Float](repeating: 0.5, count: 22050), sampleRate: 22050).write(to: source)
        var step = SceneStep(kind: .sound, soundID: "tone"); step.startTime = 0; step.audioDuration = 0.25
        let plan = SceneTimeline(scene: HorrorScene(steps: [step]), soundDurations: ["tone": 1])
        XCTAssertEqual(plan.entries[0].duration, 0.25)
        let url = try XCTUnwrap(AudioTimelineMixer.render(entries: plan.entries, sources: [step.id: source], folder: folder))
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let values = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertGreaterThan(values[2000], 0.4)
        XCTAssertEqual(values[9000], 0, accuracy: 0.0001)
    }
    @MainActor func testPreviewReplayStartsAudioAndLightClockTogetherAfterCompletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sound = folder.appendingPathComponent("tone.wav")
        try WaveWriter.data(samples: (0..<11025).map { Float(sin(Double($0) * 0.1) * 0.2) }, sampleRate: 22050).write(to: sound)
        var audio = SceneStep(kind: .sound, soundID: "tone"); audio.startTime = 0
        var light = SceneStep(kind: .flicker, seconds: 1); light.startTime = 0
        var scene = HorrorScene(steps: [audio, light]); scene.volume = 0
        let preview = ScenePreview()
        for cycle in 0..<2 {
            // A paused/scrubbed playhead must not turn a fresh Preview into a silent tail.
            if cycle == 0 { preview.scrub(0.8, duration: 1) }
            preview.start(scene: scene, sounds: ["tone": sound], durations: ["tone": 0.5], audio: true, folder: folder)
            for _ in 0..<100 { if preview.running { break }; try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(preview.running, preview.status)
            try await Task.sleep(for: .milliseconds(70))
            XCTAssertTrue(preview.audioIsPlaying, "Cycle \(cycle): audio must actually play from the start")
            XCTAssertLessThan(try XCTUnwrap(preview.audioTime), 0.4, "Audio must restart at zero before play()")
            XCTAssertLessThan(preview.time, 0.4, "Light clock must restart too")
            for _ in 0..<150 { if !preview.running { break }; try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(preview.running)
            XCTAssertEqual(preview.time, 1, accuracy: 0.05)
        }
        preview.scrub(0.25, duration: 1)
        preview.start(scene: scene, sounds: ["tone": sound], durations: ["tone": 0.5], audio: true, folder: folder, fromCurrentTime: true)
        for _ in 0..<100 { if preview.running { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(preview.running, preview.status)
        XCTAssertEqual(preview.time, 0.25, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(preview.audioTime), 0.25, accuracy: 0.1)
        preview.stop()
    }
    @MainActor func testPreviewRunsWithoutHardwareAndStopFreezesPlayhead() async throws {
        var step = SceneStep(kind: .flicker, seconds: 2); step.startTime = 0
        let preview = ScenePreview()
        preview.start(scene: HorrorScene(steps: [step]), sounds: [:], durations: [:], audio: false, folder: FileManager.default.temporaryDirectory)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(preview.running); XCTAssertGreaterThan(preview.time, 0)
        preview.stop(); let position = preview.time
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(preview.running); XCTAssertEqual(position, preview.time)
        preview.scrub(1.5, duration: 2); XCTAssertEqual(preview.time, 1.5)
    }
}
