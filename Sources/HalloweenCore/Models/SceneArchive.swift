import Foundation
import AVFoundation

public struct ArchivedSound: Codable, Sendable {
    public var clip: SoundClip
    public var data: Data
}
/// A portable scene with its own audio and disabled-on-import trigger definitions.
public struct SceneArchive: Codable, Sendable {
    public var version = 1
    public var scene: HorrorScene
    public var rules: [AutomationRule]
    public var sounds: [ArchivedSound]
    public init(scene: HorrorScene, rules: [AutomationRule] = [], sounds: [ArchivedSound] = []) { self.scene = scene; self.rules = rules; self.sounds = sounds }
    public static func decode(_ data: Data) throws -> SceneArchive {
        guard data.count <= 40_000_000 else { throw AppFailure(L10n.value("Ablaufpaket ist zu groß (maximal 40 MB).")) }
        let decoder = JSONDecoder()
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["version"] != nil {
            let archive = try decoder.decode(Self.self, from: data)
            guard archive.version == 1 else { throw AppFailure(L10n.value("Dieses Ablaufpaket benötigt eine neuere Haunt-Version.")) }
            try archive.validate(); return archive
        }
        let archive = SceneArchive(scene: try decoder.decode(HorrorScene.self, from: data)); try archive.validate(); return archive
    }
    public func validate() throws {
        guard (1...100).contains(scene.steps.count), (1...10).contains(scene.repetitions), scene.volume.isFinite, (0...100).contains(scene.volume),
              Set(scene.steps.map(\.id)).count == scene.steps.count, rules.count <= 50, sounds.count <= 100,
              Set(sounds.map { $0.clip.id }).count == sounds.count else { throw AppFailure(L10n.value("Ungültiges Ablaufpaket.")) }
        for step in scene.steps {
            guard step.seconds.isFinite, (0...600).contains(step.seconds), step.brightness.isFinite, (0...100).contains(step.brightness), step.hue.isFinite, (0...360).contains(step.hue),
                  step.startTime == nil || (step.startTime!.isFinite && (0...600).contains(step.startTime!)), step.text.count <= 300,
                  step.speechLanguage == nil || ["de-DE", "en-US", "en-GB"].contains(step.speechLanguage!) else { throw AppFailure(L10n.value("Ein Schritt enthält ungültige Werte.")) }
        }
        for rule in rules { try rule.validate(); guard rule.sceneID == scene.id else { throw AppFailure(L10n.value("Auslöser gehört zu einem anderen Ablauf.")) } }
        guard sounds.reduce(0, { $0 + $1.data.count }) <= 25_000_000 else { throw AppFailure(L10n.value("Eigene Sounds dürfen zusammen maximal 25 MB groß sein.")) }
        for sound in sounds {
            guard !sound.clip.builtIn, !sound.data.isEmpty, ["mp3", "wav"].contains(URL(fileURLWithPath: sound.clip.filename).pathExtension.lowercased()) else { throw AppFailure(L10n.value("Ungültiger Sound im Ablaufpaket.")) }
        }
    }
}
