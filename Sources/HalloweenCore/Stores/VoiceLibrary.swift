import AVFoundation
import Foundation

extension AppStore {
    public func voiceRecipe(for clip: SoundClip) -> VoiceLabRecipe? {
        guard UUID(uuidString: clip.id) != nil else { return nil }
        let url = directory.appendingPathComponent("VoiceSources/\(clip.id).json")
        return try? JSONDecoder().decode(VoiceLabRecipe.self, from: Data(contentsOf: url))
    }
    public func voiceSource(for recipe: VoiceLabRecipe) -> URL? {
        guard let name = recipe.sourceFilename, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let url = directory.appendingPathComponent("VoiceSources").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    @discardableResult public func saveVoice(name: String, audio: URL, source: URL, recipe: VoiceLabRecipe) throws -> SoundClip {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw AppFailure(L10n.value("Bitte einen Namen mit 1 bis 100 Zeichen eingeben.")) }
        let player = try AVAudioPlayer(contentsOf: audio)
        guard player.duration > 0, player.duration <= 65 else { throw AppFailure(L10n.value("Diese Audiodatei ist zu groß oder leer.")) }
        let id = UUID().uuidString, sourceFolder = directory.appendingPathComponent("VoiceSources")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent("Sounds/\(id).wav"), original = sourceFolder.appendingPathComponent("\(id).wav"), metadata = sourceFolder.appendingPathComponent("\(id).json")
        var stored = recipe; stored.sourceFilename = original.lastPathComponent
        let clip = SoundClip(id: id, name: name, filename: dest.lastPathComponent, duration: player.duration, symbol: "mic.fill", category: "Stimmenlabor")
        do {
            try FileManager.default.copyItem(at: audio, to: dest); try FileManager.default.copyItem(at: source, to: original)
            try JSONEncoder().encode(stored).write(to: metadata, options: .atomic)
            let next = sounds + [clip]
            try JSONEncoder().encode(next.filter { !$0.builtIn }).write(to: directory.appendingPathComponent("sounds.json"), options: .atomic)
            sounds = next
            return clip
        } catch {
            for url in [dest, original, metadata] { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
