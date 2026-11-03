import Foundation
import Combine
import AVFoundation

@MainActor public final class ScenePreview: ObservableObject {
    @Published public private(set) var running = false
    @Published public private(set) var preparing = false
    @Published public var time = 0.0
    @Published public private(set) var status = L10n.value("Virtuelle Bühne · keine Geräte werden gesteuert")
    @Published public private(set) var speechDurations: [UUID: Double] = [:]
    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var generation = UUID()
    var audioIsPlaying: Bool { player?.isPlaying ?? false }
    var audioTime: Double? { player?.currentTime }
    public init() {}
    public func stop(reset: Bool = false) {
        if running || preparing { status = L10n.value("Vorschau pausiert · Geräte unverändert") }
        generation = UUID(); task?.cancel(); task = nil; player?.stop(); player = nil
        running = false; preparing = false
        if reset { time = 0 }
    }
    public func invalidate() { stop(); speechDurations = [:] }
    public func scrub(_ value: Double, duration: Double) { time = max(0, min(duration, value)); player?.currentTime = time }
    public func start(scene: HorrorScene, sounds: [String: URL], durations: [String: Double], audio: Bool, folder: URL, fromCurrentTime: Bool = false) {
        let initial = fromCurrentTime ? time : 0; stop(); let token = generation
        preparing = audio; status = audio ? L10n.value("Bereite Sound und Spukstimme vor …") : L10n.value("Live · virtuelle Lichtvorschau")
        task = Task {
            let temporary = folder.appendingPathComponent("preview-\(token.uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                var sources: [UUID: URL] = [:]; var spoken: [UUID: Double] = [:]
                if audio {
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                    for step in scene.steps where step.kind.usesRooms {
                        try Task.checkCancellation()
                        if step.kind == .sound { guard let file = sounds[step.soundID] else { throw AppFailure(L10n.value("Sound fehlt.")) }; sources[step.id] = file }
                        else { let file = try await SpeechRenderer().render(step.text, folder: temporary, language: step.speechLanguage, effect: step.voiceEffect ?? .ghost); try Task.checkCancellation(); sources[step.id] = file; spoken[step.id] = try AVAudioPlayer(contentsOf: file).duration }
                    }
                }
                try Task.checkCancellation(); guard generation == token else { return }
                let plan = SceneTimeline(scene: scene, soundDurations: durations, speechDurations: spoken)
                try plan.validate(scene: scene)
                let start = initial >= plan.duration ? 0 : max(0, initial)
                if audio, let file = try await Task.detached(operation: { try AudioTimelineMixer.render(entries: plan.entries, sources: sources, folder: temporary) }).value {
                    try Task.checkCancellation(); guard generation == token else { return }
                    #if os(iOS)
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                    #endif
                    player = try AVAudioPlayer(contentsOf: file); player?.volume = Float(scene.volume / 100)
                    player?.currentTime = start
                    player?.prepareToPlay()
                    guard player?.play() == true else { throw AppFailure(L10n.value("Der lokale Audioplayer konnte nicht starten.")) }
                }
                speechDurations = spoken; preparing = false; running = true
                status = audio ? L10n.value("Live · Ton auf diesem Gerät, Licht auf der Bühne") : L10n.value("Live · virtuelle Lichtvorschau")
                time = start
                let origin = ContinuousClock.now
                while time < plan.duration {
                    try await Task.sleep(for: .milliseconds(33)); try Task.checkCancellation()
                    let components = origin.duration(to: .now).components
                    let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1e18
                    let next = min(plan.duration, start + elapsed)
                    time = next
                }
                player?.stop(); player = nil; running = false; status = L10n.value("Vorschau beendet · Geräte unverändert")
            } catch is CancellationError { }
            catch { if generation == token { preparing = false; running = false; player?.stop(); player = nil; status = "Vorschau: \(error.localizedDescription)" } }
        }
    }
}
