import Foundation
import Combine

public struct SceneResources: Equatable, Sendable {
    public var rooms: Set<String> = []
    public var lights: Set<String> = []
    public init(scene: HorrorScene) {
        for step in scene.steps {
            if step.kind.usesRooms { rooms.formUnion(step.roomIDs.isEmpty ? scene.roomIDs : step.roomIDs) }
            if step.kind.usesLights { lights.formUnion(step.lightIDs.isEmpty ? scene.lightIDs : step.lightIDs) }
        }
    }
    public func overlaps(_ other: SceneResources) -> Bool { !rooms.isDisjoint(with: other.rooms) || !lights.isDisjoint(with: other.lights) }
}

@MainActor public final class PlaybackSession: ObservableObject, Identifiable {
    public let id = UUID()
    public let scene: HorrorScene
    public let runner: SceneRunner
    public let resources: SceneResources
    public init(scene: HorrorScene, runner: SceneRunner) { self.scene = scene; self.runner = runner; resources = SceneResources(scene: scene) }
}

@MainActor public final class PlaybackCoordinator: ObservableObject {
    @Published public private(set) var sessions: [PlaybackSession] = []
    public private(set) var latestRunner = SceneRunner()
    private var observers: [UUID: AnyCancellable] = [:]
    private var pendingRemoval: Set<UUID> = []
    private let makeRunner: () -> SceneRunner
    public init(makeRunner: (() -> SceneRunner)? = nil) { self.makeRunner = makeRunner ?? { SceneRunner() } }
    public var active: [PlaybackSession] { sessions.filter { $0.runner.running } }
    public var running: Bool { !active.isEmpty }
    public func runner(for sceneID: UUID) -> SceneRunner? { active.last { $0.scene.id == sceneID }?.runner }
    public func conflict(for scene: HorrorScene) -> PlaybackSession? {
        let resources = SceneResources(scene: scene)
        return active.first { $0.scene.id == scene.id || resources.overlaps($0.resources) }
    }
    @discardableResult public func start(_ scene: HorrorScene, speakers: [Speaker], lights: [HueLight], bridges: [HueBridge], sounds: [String: URL], folder: URL) -> PlaybackSession? {
        guard conflict(for: scene) == nil else { return nil }
        let runner = makeRunner(); let session = PlaybackSession(scene: scene, runner: runner)
        latestRunner = runner; sessions.insert(session, at: 0)
        observers[session.id] = runner.$running.dropFirst().removeDuplicates().sink { [weak self] _ in
            // Deliver after @Published has committed its new value.
            Task { @MainActor [weak self] in self?.refresh() }
        }
        runner.start(scene, speakers: speakers, lights: lights, bridges: bridges, sounds: sounds, folder: folder)
        return session
    }
    private func refresh() {
        for session in sessions where !session.runner.running && pendingRemoval.contains(session.id) { discard(session.id) }
        let completed = sessions.filter { !$0.runner.running }
        for session in completed.dropFirst(30) { discard(session.id) }
        objectWillChange.send()
    }
    private func discard(_ id: UUID) { sessions.removeAll { $0.id == id }; observers.removeValue(forKey: id); pendingRemoval.remove(id) }
    public func remove(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if session.runner.running { pendingRemoval.insert(id); session.runner.stop() } else { discard(id) }
    }
    public func removeScene(_ id: UUID) { for session in sessions.filter({ $0.scene.id == id }) { remove(session.id) } }
    public func stopAll() { for session in active { session.runner.stop() } }
    public func pauseAll() { for session in active { session.runner.pause() } }
    public func resumeAll() { for session in active { session.runner.resume() } }
}
