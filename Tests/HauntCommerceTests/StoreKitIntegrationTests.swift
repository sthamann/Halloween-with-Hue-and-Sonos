import XCTest
import AVFoundation
import HalloweenCore

@MainActor final class VoiceRecordingIntegrationTests: XCTestCase {
    func testPreviewToRecordingKeepsAudioSessionAndAllEffectsSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("fixture.wav")
        try WaveWriter.data(samples: (0..<44100).map { Float(sin(Double($0) * 2 * .pi * 440 / 44100)) * 0.2 }, sampleRate: 44100).write(to: fixture)
        let lab = VoiceLabStore(); defer { lab.cleanup() }
        lab.load(source: fixture, recipe: VoiceLabRecipe(), name: "Recording QA")
        lab.previewOriginal()
        await lab.startRecording()
        XCTAssertTrue(lab.recording, lab.error ?? "Recorder did not start")
        try await Task.sleep(for: .seconds(2))
        lab.finishRecording()
        XCTAssertNil(lab.error)
        let source = try XCTUnwrap(lab.source)
        let raw = try VoiceLabAudio.read(source)
        XCTAssertGreaterThan(raw.samples.count, 44100)
        let store = HalloweenCore.AppStore(directory: directory.appendingPathComponent("library"))
        for effect in VoiceLabEffect.allCases {
            let output = directory.appendingPathComponent(effect.rawValue + ".wav")
            let recipe = VoiceLabRecipe(effect: effect, trimStart: 0, trimEnd: Double(raw.samples.count) / Double(raw.sampleRate))
            try VoiceLabAudio.render(source: source, recipe: recipe, destination: output)
            let clip = try store.saveVoice(name: effect.rawValue, audio: output, source: source, recipe: recipe)
            XCTAssertGreaterThan(clip.duration, 1)
            XCTAssertNoThrow(try AVAudioPlayer(contentsOf: store.soundURL(clip)))
        }
        let reopened = HalloweenCore.AppStore(directory: store.directory)
        XCTAssertEqual(reopened.sounds.count, VoiceLabEffect.allCases.count)
    }
}
