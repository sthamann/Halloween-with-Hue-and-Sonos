import XCTest
@testable import HalloweenCore

final class EditorFlowTests: XCTestCase {
    func testVoiceEffectsAreDistinctBoundedAndBackwardCompatible() throws {
        let samples: [Float] = (0..<1000).map { Float(sin(Double($0) / 9)) * 0.8 }
        XCTAssertEqual(VoiceEffect.natural.process(samples, sampleRate: 1000), samples)
        let ghost = VoiceEffect.ghost.process(samples, sampleRate: 1000)
        let demon = VoiceEffect.demon.process(samples, sampleRate: 1000)
        XCTAssertNotEqual(ghost, demon)
        XCTAssertTrue(ghost.allSatisfy { $0.isFinite && abs($0) <= 0.95 })
        XCTAssertTrue(demon.allSatisfy { $0.isFinite && abs($0) <= 0.95 })
        var step = SceneStep(kind: .speech); step.voiceEffect = .demon
        XCTAssertEqual(try JSONDecoder().decode(SceneStep.self, from: JSONEncoder().encode(step)).voiceEffect, .demon)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(step)) as? [String: Any])
        legacy.removeValue(forKey: "voiceEffect")
        XCTAssertNil(try JSONDecoder().decode(SceneStep.self, from: JSONSerialization.data(withJSONObject: legacy)).voiceEffect)
    }
    func testMotionAwareCandidatesAreNotExposedAsConfiguredMotionInputs() throws {
        let data = Data(#"{"errors":[],"data":[{"id":"lamp-candidate","type":"motion_area_candidate","capabilities":["sensor","collector"]}]}"#.utf8)
        let inventory = try HueEventClient.decodeInventory(data, bridgeID: "pro")
        XCTAssertEqual(inventory.motionCandidateCount, 1)
        XCTAssertEqual(inventory.motionAreaCount, 0)
        XCTAssertTrue(inventory.inputs.isEmpty)
    }
    func testConfiguredMotionAwareAreaIsExposedWithNamedMotionInput() throws {
        let data = Data(#"{"errors":[],"data":[{"id":"area","type":"motion_area_configuration","name":"Hallway","services":[{"rid":"motion","rtype":"convenience_area_motion"}]},{"id":"motion","type":"convenience_area_motion","owner":{"rid":"area","rtype":"motion_area_configuration"},"motion":{"motion":false}}]}"#.utf8)
        let inventory = try HueEventClient.decodeInventory(data, bridgeID: "pro")
        XCTAssertEqual(inventory.motionAreaCount, 1)
        XCTAssertEqual(inventory.inputs.count, 1)
        XCTAssertEqual(inventory.inputs[0].name, "Hallway · MotionAware")
        XCTAssertEqual(inventory.baseline.first?.event, "no_motion")
    }
}
