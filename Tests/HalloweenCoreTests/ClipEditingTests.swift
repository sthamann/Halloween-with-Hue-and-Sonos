import XCTest
@testable import HalloweenCore
final class ClipEditingTests: XCTestCase {
    func testRepeatedCopiesChainAtTrimmedAudioEndAndKeepTargets() throws {
        var step = SceneStep(kind: .sound, soundID: "custom-voice")
        step.startTime = 2; step.audioDuration = 3; step.roomIDs = ["labor"]
        var scene = HorrorScene(steps: [step])
        for _ in 0..<4 {
            let plan = SceneTimeline(scene: scene, soundDurations: ["custom-voice": 12])
            let last = try XCTUnwrap(plan.entries.last)
            // Same Codable round-trip used by the app clipboard.
            let copied = try JSONDecoder().decode(SceneStep.self, from: JSONEncoder().encode(last.step))
            scene.steps.append(copied.copied(startingAt: last.end))
        }
        XCTAssertEqual(scene.steps.map { $0.startTime! }, [2, 5, 8, 11, 14])
        XCTAssertEqual(Set(scene.steps.map(\.id)).count, 5)
        XCTAssertTrue(scene.steps.allSatisfy { $0.roomIDs == ["labor"] && $0.audioDuration == 3 })
        try SceneTimeline(scene: scene, soundDurations: ["custom-voice": 12]).validate(scene: scene)
    }
    func testLightCopyPreservesEffectAndColor() {
        var step = SceneStep(kind: .flicker, seconds: 8)
        step.lightIDs = ["lamp1"]; step.hueEffect = .ghostFlicker; step.useLampColor = true
        let copy = step.copied(startingAt: 8)
        XCTAssertNotEqual(step.id, copy.id)
        XCTAssertEqual(copy.lightIDs, step.lightIDs)
        XCTAssertEqual(copy.hueEffect, step.hueEffect)
        XCTAssertEqual(copy.useLampColor, true)
        XCTAssertEqual(copy.seconds, 8)
    }
}
