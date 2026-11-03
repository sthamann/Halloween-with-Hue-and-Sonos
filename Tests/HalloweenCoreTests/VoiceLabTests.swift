import XCTest
import AVFoundation
@testable import HalloweenCore

final class VoiceLabTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func fixture(_ directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("original.wav")
        let samples = (0..<44100).map { Float(sin(Double($0) * 2 * .pi * 440 / 44100)) * 0.35 }
        try WaveWriter.data(samples: samples, sampleRate: 44100).write(to: url); return url
    }
    func testEveryEffectRendersNonSilentBoundedAudioAndTrimRejectsInvalidRange() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try fixture(dir)
        var rendered: [[Float]] = []
        for effect in VoiceLabEffect.allCases {
            let url = dir.appendingPathComponent(effect.rawValue + ".wav")
            try VoiceLabAudio.render(source: original, recipe: VoiceLabRecipe(effect: effect, intensity: 0.8, trimStart: 0.1, trimEnd: 0.9), destination: url)
            let result = try VoiceLabAudio.read(url)
            XCTAssertTrue(result.samples.allSatisfy(\.isFinite)); XCTAssertGreaterThan(result.samples.map(abs).max() ?? 0, 0.05)
            XCTAssertLessThanOrEqual(result.samples.map(abs).max() ?? 1, 0.93)
            XCTAssertEqual(result.sampleRate, 44100)
            rendered.append(result.samples)
        }
        XCTAssertNotEqual(rendered[1], rendered[2]); XCTAssertNotEqual(rendered[3], rendered[4])
        XCTAssertThrowsError(try VoiceLabAudio.render(source: original, recipe: VoiceLabRecipe(trimStart: 0.9, trimEnd: 0.2), destination: dir.appendingPathComponent("bad.wav")))
        XCTAssertThrowsError(try VoiceLabAudio.render(source: original, recipe: VoiceLabRecipe(intensity: .nan), destination: dir.appendingPathComponent("bad.wav")))
    }
    @MainActor func testSavedVoiceSurvivesRestartCreatesIndependentVariantsAndTravelsWithScene() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try fixture(dir), rendered = dir.appendingPathComponent("demon.wav")
        let recipe = VoiceLabRecipe(effect: .demon, intensity: 0.6, trimStart: 0.1, trimEnd: 0.8, text: "Hallo", voiceIdentifier: "test-voice")
        try VoiceLabAudio.render(source: original, recipe: recipe, destination: rendered)
        let store = AppStore(directory: dir.appendingPathComponent("library"))
        let clip = try store.saveVoice(name: "Dämon", audio: rendered, source: original, recipe: recipe)
        let restored = AppStore(directory: store.directory), saved = try XCTUnwrap(restored.voiceRecipe(for: clip))
        XCTAssertEqual(saved.effect, .demon); XCTAssertEqual(saved.text, "Hallo")
        let retainedOriginal = try XCTUnwrap(restored.voiceSource(for: saved))
        XCTAssertEqual(try Data(contentsOf: retainedOriginal), try Data(contentsOf: original))
        let variant = try restored.saveVoice(name: "Variante", audio: rendered, source: retainedOriginal, recipe: saved)
        XCTAssertNotEqual(variant.id, clip.id); XCTAssertEqual(restored.sounds.count, 2)
        let scene = HorrorScene(name: "Scene", steps: [SceneStep(kind: .sound, soundID: clip.id)])
        let archive = try restored.archive(scene)
        XCTAssertEqual(archive.sounds.count, 1); XCTAssertEqual(archive.sounds[0].data, try Data(contentsOf: rendered))
        XCTAssertNotEqual(archive.sounds[0].data, try Data(contentsOf: original))
        let second = AppStore(directory: dir.appendingPathComponent("import"))
        let imported = try second.importArchive(JSONEncoder().encode(archive))
        let importedClip = try XCTUnwrap(second.sounds.first)
        XCTAssertEqual(imported.steps[0].soundID, importedClip.id)
        XCTAssertEqual(try Data(contentsOf: second.soundURL(importedClip)), try Data(contentsOf: rendered))
        XCTAssertNil(second.voiceRecipe(for: importedClip)) // Original recordings are not exported.
    }
    @MainActor func testMissingSourceAndBadNamesDoNotChangeLibrary() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try fixture(dir), store = AppStore(directory: dir.appendingPathComponent("library"))
        XCTAssertThrowsError(try store.saveVoice(name: " ", audio: original, source: original, recipe: VoiceLabRecipe()))
        XCTAssertThrowsError(try store.saveVoice(name: "Broken", audio: original, source: dir.appendingPathComponent("missing.wav"), recipe: VoiceLabRecipe()))
        XCTAssertTrue(store.sounds.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.directory.appendingPathComponent("Sounds").path).isEmpty)
    }
    @MainActor func testChangedTextRequiresRerenderWithoutLosingOriginal() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try fixture(dir), lab = VoiceLabStore(); defer { lab.cleanup() }
        lab.load(source: original, recipe: VoiceLabRecipe(text: "Hallo"), name: "Test")
        XCTAssertFalse(lab.speechNeedsUpdate)
        lab.text = "Anderer Text"
        XCTAssertTrue(lab.speechNeedsUpdate); XCTAssertNotNil(lab.source)
        lab.text = "Hallo"; XCTAssertFalse(lab.speechNeedsUpdate)
    }
    @MainActor func testVoiceSaveAndVariationsAreFreeAndPersistAcrossRestart() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try fixture(dir), library = dir.appendingPathComponent("library")
        let store = AppStore(directory: library)
        let clip = try store.saveVoice(name: "Ghost", audio: original, source: original, recipe: VoiceLabRecipe())
        let reopened = AppStore(directory: library)
        XCTAssertEqual(reopened.sounds.map(\.id), [clip.id])
        XCTAssertNoThrow(try AVAudioPlayer(contentsOf: reopened.soundURL(clip)))
        let variation = try reopened.saveVoice(name: "Variant", audio: original, source: original, recipe: VoiceLabRecipe(effect: .ghost))
        let restored = AppStore(directory: library)
        XCTAssertEqual(Set(restored.sounds.map(\.id)), Set([clip.id, variation.id]))
        XCTAssertNotNil(restored.voiceRecipe(for: variation))
    }
}
