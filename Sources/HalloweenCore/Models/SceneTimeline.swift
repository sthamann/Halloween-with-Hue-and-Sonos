import Foundation

public struct TimelineEntry: Identifiable, Sendable {
    public var id: UUID { step.id }
    public let step: SceneStep
    public let start: Double
    public let duration: Double
    public let estimatedDuration: Bool
    public var end: Double { start + duration }
}
public struct SceneTimeline: Sendable {
    public let entries: [TimelineEntry]
    public var duration: Double { max(1, entries.map(\.end).max() ?? 1) }
    public init(scene: HorrorScene, soundDurations: [String: Double], speechDurations: [UUID: Double] = [:]) {
        let absolute = scene.steps.contains { $0.startTime != nil }
        var cursor = 0.0; var result: [TimelineEntry] = []
        for step in scene.steps {
            let duration: Double
            switch step.kind {
            case .sound: duration = min(soundDurations[step.soundID] ?? max(1, step.seconds), step.audioDuration ?? .infinity)
            case .speech: duration = min(speechDurations[step.id] ?? Self.estimatedSpeechDuration(step.text), step.audioDuration ?? .infinity)
            default: duration = max(0.1, step.seconds)
            }
            let start = absolute ? (step.startTime ?? cursor) : cursor
            result.append(TimelineEntry(step: step, start: start, duration: duration, estimatedDuration: step.kind == .speech && speechDurations[step.id] == nil))
            if absolute { cursor = max(cursor, start + duration) }
            else if step.kind == .wait || step.kind == .flicker { cursor += duration }
            else if step.kind.usesRooms && step.waitForSound { cursor += duration }
        }
        entries = result.enumerated().sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }.map(\.element)
    }
    public static func estimatedSpeechDuration(_ text: String) -> Double { max(2, Double(text.count) / 9 + 1.5) }
    public static func migrating(_ scene: HorrorScene, soundDurations: [String: Double]) -> HorrorScene {
        guard !scene.steps.contains(where: { $0.startTime != nil }) else { return scene }
        let plan = SceneTimeline(scene: scene, soundDurations: soundDurations)
        var copy = scene
        for index in copy.steps.indices { copy.steps[index].startTime = plan.entries.first { $0.id == copy.steps[index].id }?.start ?? 0 }
        return copy
    }
    public func validate(scene: HorrorScene) throws {
        guard scene.volume.isFinite, (0...100).contains(scene.volume), (1...10).contains(scene.repetitions),
              entries.allSatisfy({ $0.step.seconds.isFinite && (0...600).contains($0.step.seconds) && $0.step.brightness.isFinite && (0...100).contains($0.step.brightness) && $0.step.hue.isFinite && (0...360).contains($0.step.hue) && $0.step.text.count <= 300 }),
              entries.count <= 100, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ $0.start.isFinite && (0...600).contains($0.start) && $0.duration.isFinite && (0.1...600).contains($0.duration) }), duration <= 1200 else { throw AppFailure(L10n.value("Die Zeitleiste enthält ungültige Zeiten oder zu viele Clips.")) }
        guard scene.steps.allSatisfy({ step in
            (step.audioDuration.map { $0.isFinite && (0.1...600).contains($0) } ?? true) &&
            (step.saturation.map { $0.isFinite && (0...100).contains($0) } ?? true)
        }) else { throw AppFailure(L10n.value("Ungültige Clip-Dauer oder Farbe.")) }
        let lightEntries = entries.filter { $0.step.kind.usesLights }
        for (index, a) in lightEntries.enumerated() {
            let aTargets = a.step.lightIDs.isEmpty ? scene.lightIDs : a.step.lightIDs
            for b in lightEntries.dropFirst(index + 1) where a.start < b.end - 0.01 && b.start < a.end - 0.01 {
                let bTargets = b.step.lightIDs.isEmpty ? scene.lightIDs : b.step.lightIDs
                if !aTargets.isDisjoint(with: bTargets) || (aTargets.isEmpty && bTargets.isEmpty) { throw AppFailure(L10n.value("Zwei Lichtclips überlagern sich auf denselben Lampen. Verschiebe einen Clip oder wähle unterschiedliche Lampen.")) }
            }
        }
    }
}
