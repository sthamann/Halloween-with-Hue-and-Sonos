import Foundation
import Combine
import AVFoundation

@MainActor public final class AppStore: ObservableObject {
    @Published public var language = AppLanguage.system { didSet { L10n.language = language; UserDefaults.standard.set(language.rawValue, forKey: "haunt.language") } }
    @Published public var rules: [AutomationRule] = []
    @Published public private(set) var lastStarts: [String: Date] = [:]
    @Published public var hueInputs: [HueInput] = []
    @Published public var inputStatus: [String: String] = [:]
    @Published public var automationEnabled = false
    public let automation = AutomationEngine()
    private var foreground = true
    @Published public var speakers: [Speaker] = []
    @Published public var bridges: [HueBridge] = []
    @Published public var lights: [HueLight] = []
    @Published public var hueRooms: [HueRoom] = []
    @Published public var bridgeStatus: [String: String] = [:]
    @Published public var scenes: [HorrorScene] = []
    @Published public var sounds: [SoundClip] = []
    @Published public private(set) var testingLightID: String?
    @Published public var scanning = false
    @Published public var message = L10n.value("Suche deine Geräte im lokalen Netzwerk.")
    @Published public var error: String?
    public let playback = PlaybackCoordinator()
    public var runner: SceneRunner { playback.latestRunner }
    private var playbackObservation: AnyCancellable?
    public let directory: URL
    private var preview: AVAudioPlayer?
    private var bundled: [String: URL] = [:]
    public var pairedBridgeCount: Int { bridges.filter { CredentialStore.read($0.id) != nil }.count }
    public var deviceSummary: String {
        L10n.value("\(speakers.count) Sonos-Geräte · \(rooms.count) Räume · \(pairedBridgeCount)/\(bridges.count) Hue-Bridges gekoppelt · \(lights.count) Lampen")
    }
    @Published public var hueInventory: [String: HueInventory] = [:]
    public var rooms: [Speaker] { speakers.filter { !$0.isSatellite } }
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HalloweenSonos", isDirectory: true)
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "haunt.language") ?? AppLanguage.system.rawValue) ?? .system
        L10n.language = language
        do {
            try FileManager.default.createDirectory(at: self.directory.appendingPathComponent("Sounds"), withIntermediateDirectories: true)
            let bridgeURL = self.directory.appendingPathComponent("bridges.json")
            if FileManager.default.fileExists(atPath: bridgeURL.path) { bridges = BridgeRegistry.merging([], discovered: try JSONDecoder().decode([HueBridge].self, from: Data(contentsOf: bridgeURL))) }
            let url = self.directory.appendingPathComponent("scenes.json")
            if FileManager.default.fileExists(atPath: url.path) { scenes = SceneLibrary.sorted(try JSONDecoder().decode([HorrorScene].self, from: Data(contentsOf: url))) } else { scenes = [] }
            let rulesURL = self.directory.appendingPathComponent("automations.json")
            if FileManager.default.fileExists(atPath: rulesURL.path) { rules = try JSONDecoder().decode([AutomationRule].self, from: Data(contentsOf: rulesURL)); for rule in rules { try rule.validate() } }
            let historyURL = self.directory.appendingPathComponent("execution-history.json")
            if FileManager.default.fileExists(atPath: historyURL.path) { lastStarts = try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: historyURL)) }
            let soundURL = self.directory.appendingPathComponent("sounds.json")
            if FileManager.default.fileExists(atPath: soundURL.path) { sounds = try JSONDecoder().decode([SoundClip].self, from: Data(contentsOf: soundURL)) }
        } catch { self.error = L10n.value("Gespeicherte Daten konnten nicht geladen werden: \(error.localizedDescription)") }
        playbackObservation = playback.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    public func configureSounds(_ urls: [String: URL], catalog: [BundledSound] = SoundLibrary.originals) {
        bundled = urls
        var missing: [String] = []
        let builtins = catalog.compactMap { entry -> SoundClip? in
            guard let url = urls[entry.id], let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { missing.append(entry.name); return nil }
            return SoundClip(id: entry.id, name: entry.name, filename: url.lastPathComponent, duration: player.duration, symbol: entry.symbol, builtIn: true, category: entry.category, credit: entry.credit)
        }
        if !missing.isEmpty { error = L10n.value("Diese eingebauten Sounds fehlen oder sind beschädigt: \(missing.joined(separator: ", "))") }
        sounds.removeAll { $0.builtIn }; sounds.insert(contentsOf: builtins, at: 0)
    }
    public func soundURL(_ clip: SoundClip) -> URL { clip.builtIn ? bundled[clip.id]! : self.directory.appendingPathComponent("Sounds").appendingPathComponent(clip.filename) }
    public var favoriteScenes: [HorrorScene] { scenes.filter { $0.isFavorite == true } }
    @discardableResult public func saveScene(_ scene: HorrorScene, at date: Date = Date()) -> Bool {
        var saved = scene
        saved.updatedAt = date
        saved.isFavorite = scenes.first(where: { $0.id == scene.id })?.isFavorite ?? scene.isFavorite ?? false
        var next = scenes.filter { $0.id != scene.id }; next.append(saved)
        next = SceneLibrary.sorted(next)
        do { try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("scenes.json"), options: .atomic); scenes = next; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    public func toggleFavorite(_ id: UUID) {
        var next = scenes
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].isFavorite = next[index].isFavorite != true
        do { try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("scenes.json"), options: .atomic); scenes = next }
        catch { self.error = error.localizedDescription }
    }
    public func save() {
        do { try JSONEncoder().encode(rules).write(to: directory.appendingPathComponent("automations.json"), options: .atomic); try JSONEncoder().encode(scenes).write(to: self.directory.appendingPathComponent("scenes.json"), options: .atomic); try JSONEncoder().encode(sounds.filter { !$0.builtIn }).write(to: self.directory.appendingPathComponent("sounds.json"), options: .atomic) }
        catch { self.error = L10n.value("Speichern fehlgeschlagen: \(error.localizedDescription)") }
    }
    public func previewSound(_ clip: SoundClip) {
        do { preview?.stop(); preview = try AVAudioPlayer(contentsOf: soundURL(clip)); preview?.volume = 0.45; preview?.play() } catch { self.error = error.localizedDescription }
    }
    public func stopPreview() { preview?.stop() }
    public func importSound(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard ["mp3", "wav", "m4a", "aiff", "aif"].contains(url.pathExtension.lowercased()) else { throw AppFailure(L10n.value("Bitte MP3, WAV, M4A oder AIFF wählen.")) }
            let name = UUID().uuidString + "." + url.pathExtension.lowercased(); let dest = self.directory.appendingPathComponent("Sounds").appendingPathComponent(name)
            // Sonos receives only MP3/WAV. Convert other imported formats to PCM WAV.
            let output: URL
            if ["mp3", "wav"].contains(url.pathExtension.lowercased()) { try FileManager.default.copyItem(at: url, to: dest); output = dest }
            else {
                let file = try AVAudioFile(forReading: url); guard file.length > 0, file.length < 44_100 * 600, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw AppFailure(L10n.value("Diese Audiodatei ist zu groß oder leer.")) }
                try file.read(into: buffer); guard let samples = buffer.floatChannelData?[0] else { throw AppFailure(L10n.value("Audioformat konnte nicht umgewandelt werden.")) }
                output = dest.deletingPathExtension().appendingPathExtension("wav"); try WaveWriter.data(samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))), sampleRate: Int(file.processingFormat.sampleRate)).write(to: output)
            }
            let player = try AVAudioPlayer(contentsOf: output); sounds.append(SoundClip(name: url.deletingPathExtension().lastPathComponent, filename: output.lastPathComponent, duration: player.duration)); save()
        } catch { self.error = error.localizedDescription }
    }
    public func scan() async {
        guard !scanning, !playback.running else { return }; scanning = true; defer { scanning = false }
        message = L10n.value("Sonos und Hue werden gesucht …")
        let hosts = LocalNetwork.hosts(); guard !hosts.isEmpty else { message = L10n.value("Kein lokales Netzwerk gefunden."); return }
        let sonos = SonosClient(); let hue = HueClient(); var found: [Speaker] = []; var foundBridges: [HueBridge] = []
        for start in stride(from: 0, to: hosts.count, by: 32) {
            let chunk = Array(hosts[start..<min(start + 32, hosts.count)])
            await withTaskGroup(of: (Speaker?, HueBridge?).self) { group in
                for ip in chunk { group.addTask { async let s = sonos.probe(ip); async let h = hue.probe(ip); return await (s, h) } }
                for await (speaker, bridge) in group { if let speaker { found.append(speaker) }; if let bridge { foundBridges.append(bridge) } }
            }
        }
        do { speakers = try await sonos.topology(found) } catch { speakers = []; self.error = L10n.value("Sonos-Geräte gefunden, aber ihre Raumzuordnung ist unklar: \(error.localizedDescription)") }
        bridges = BridgeRegistry.merging(bridges, discovered: foundBridges); saveBridges(); await refreshLights()
        message = speakers.isEmpty && foundBridges.isEmpty ? L10n.value("Keine Geräte gefunden. Prüfe WLAN und die lokale Netzwerkfreigabe für Haunt.") : L10n.value("\(speakers.count) Sonos-Geräte · \(rooms.count) Räume · \(bridges.count) Hue-Bridge(s)")
    }
    private func saveBridges() {
        do { try JSONEncoder().encode(bridges).write(to: self.directory.appendingPathComponent("bridges.json"), options: .atomic) }
        catch { self.error = L10n.value("Bridges konnten nicht gespeichert werden: \(error.localizedDescription)") }
    }
    public func refreshLights() async {
        var found: [HueLight] = []; var rooms: [HueRoom] = []; var statuses: [String: String] = [:]
        for bridge in bridges {
            guard CredentialStore.read(bridge.id) != nil else { statuses[bridge.id] = L10n.value("Noch nicht gekoppelt"); continue }
            do {
                let bridgeLights = try await HueClient().lights(bridge); found += bridgeLights
                statuses[bridge.id] = L10n.value("\(bridgeLights.count) Lampen verbunden")
                do { rooms += try await HueClient().rooms(bridge) }
                catch { statuses[bridge.id] = L10n.value("Lampen verbunden · Räume nicht abrufbar") }
            } catch { statuses[bridge.id] = L10n.value("Nicht erreichbar: \(error.localizedDescription)") }
        }
        lights = found; hueRooms = rooms; bridgeStatus = statuses
        await refreshInputs(); refreshAutomation()
    }
    public func addBridge(ip: String) async {
        guard let bridge = await HueClient().probe(ip.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = L10n.value("Unter dieser IP ist keine Hue-Bridge erreichbar."); return }
        bridges = BridgeRegistry.merging(bridges, discovered: [bridge]); saveBridges(); await refreshLights()
    }
    @discardableResult public func pair(_ bridge: HueBridge) async -> Bool {
        do { try await HueClient().pair(bridge); await refreshLights(); message = deviceSummary; return true } catch { self.error = error.localizedDescription; return false }
    }
    public func refreshInputs() async {
        var inputs: [HueInput] = []; var statuses: [String: String] = [:]
        for bridge in bridges where CredentialStore.read(bridge.id) != nil {
            do { let inventory = try await HueEventClient(bridge: bridge).inventory(); inputs += inventory.inputs; hueInventory[bridge.id] = inventory; statuses[bridge.id] = L10n.value("\(inventory.inputs.count) Eingänge verfügbar") }
            catch { statuses[bridge.id] = L10n.value("Eingänge nicht erreichbar: \(error.localizedDescription)") }
        }
        hueInputs = inputs; inputStatus = statuses
    }
    public func setForeground(_ active: Bool) {
        foreground = active; refreshAutomation()
    }
    public func setAutomation(_ enabled: Bool) { automationEnabled = enabled; refreshAutomation() }
    public func refreshAutomation() {
        automation.stop()
        guard automationEnabled, foreground else { return }
        automation.start(rules: { [weak self] in self?.rules ?? [] }, bridges: bridges) { [weak self] rule in
            guard let self, !self.scanning, let scene = self.scenes.first(where: { $0.id == rule.sceneID }), self.playback.conflict(for: scene) == nil else { return false }
            let started = self.run(scene)
            if started { self.recordStart(rule.id) }
            if started, rule.kind == .once, let i = self.rules.firstIndex(where: { $0.id == rule.id }) { self.rules[i].enabled = false; self.save() }
            return started
        }
    }
    public func testLight(_ light: HueLight) async {
        guard testingLightID == nil, !playback.running, !automationEnabled,
              light.reachable, let bridge = bridges.first(where: { $0.id == light.bridgeID }) else { return }
        testingLightID = light.id
        defer { testingLightID = nil }
        do {
            try await HueClient().identify(light, bridge: bridge)
            message = L10n.value("\(light.name) · kurzer Blinkimpuls gesendet")
            // Keep manual scene starts and repeated tests apart from the short alert.
            try await Task.sleep(for: .seconds(3))
        } catch { self.error = error.localizedDescription }
    }
    public func stopAll() { setAutomation(false); playback.stopAll(); stopPreview() }
    public func openSceneURL(_ url: URL) {
        guard url.scheme?.lowercased() == "haunt", url.host == "scene", let id = UUID(uuidString: url.lastPathComponent), let scene = scenes.first(where: { $0.id == id }) else { error = L10n.value("Dieser Ablauf wurde nicht gefunden."); return }
        guard foreground, !scanning else { error = L10n.value("Das Haus ist beschäftigt oder die App im Hintergrund."); return }
        run(scene)
    }
    public func archive(_ scene: HorrorScene) throws -> SceneArchive {
        let ids = Set(scene.steps.filter { $0.kind == .sound }.map(\.soundID))
        let own = try sounds.filter { ids.contains($0.id) && !$0.builtIn }.map { ArchivedSound(clip: $0, data: try Data(contentsOf: soundURL($0))) }
        let archive = SceneArchive(scene: scene, rules: rules.filter { $0.sceneID == scene.id }, sounds: own); try archive.validate(); return archive
    }
    @discardableResult public func importArchive(_ data: Data) throws -> HorrorScene {
        let archive = try SceneArchive.decode(data); var scene = archive.scene; scene.id = UUID()
        var newSounds: [SoundClip] = []; var written: [URL] = []
        do {
            for sound in archive.sounds {
                var clip = sound.clip; let oldID = clip.id; clip.id = UUID().uuidString
                clip.filename = clip.id + "." + URL(fileURLWithPath: clip.filename).pathExtension.lowercased()
                let url = directory.appendingPathComponent("Sounds").appendingPathComponent(clip.filename)
                try sound.data.write(to: url, options: .atomic); written.append(url)
                let player = try AVAudioPlayer(contentsOf: url); guard player.duration > 0, player.duration <= 600 else { throw AppFailure(L10n.value("Sound im Ablaufpaket ist ungültig oder zu lang.")) }; clip.duration = player.duration
                for i in scene.steps.indices where scene.steps[i].soundID == oldID { scene.steps[i].soundID = clip.id }
                newSounds.append(clip)
            }
        } catch { for url in written { try? FileManager.default.removeItem(at: url) }; throw error }
        scene.updatedAt = Date(); scene.isFavorite = false
        sounds += newSounds; scenes = SceneLibrary.sorted(scenes + [scene])
        for var rule in archive.rules { rule.id = UUID(); rule.sceneID = scene.id; rule.enabled = false; rules.append(rule) }
        save(); return scene
    }
    func recordStart(_ id: UUID) {
        lastStarts[id.uuidString] = Date()
        do { try JSONEncoder().encode(lastStarts).write(to: directory.appendingPathComponent("execution-history.json"), options: .atomic) }
        catch { self.error = L10n.value("Speichern fehlgeschlagen: \(error.localizedDescription)") }
    }
    public func lastStartLabel(_ id: UUID) -> String {
        guard let date = lastStarts[id.uuidString] else { return L10n.value("Noch kein Start aufgezeichnet") }
        return L10n.value("Zuletzt gestartet") + ": " + date.formatted(date: .abbreviated, time: .standard)
    }
    public func deleteScene(_ id: UUID) { playback.removeScene(id); scenes.removeAll { $0.id == id }; rules.removeAll { $0.sceneID == id }; save() }
    @discardableResult public func run(_ scene: HorrorScene) -> Bool {
        guard testingLightID == nil else { error = L10n.value("Der Lampentest läuft noch kurz. Bitte gleich erneut starten."); return false }
        if let conflict = playback.conflict(for: scene) { error = L10n.value("Dieser Ablauf oder eines seiner Geräte wird bereits von „\(conflict.scene.name)“ verwendet. Stoppe diesen Ablauf oder wähle andere Geräte."); return false }
        stopPreview()
        let urls = Dictionary(uniqueKeysWithValues: sounds.map { ($0.id, soundURL($0)) })
        let started = playback.start(scene, speakers: speakers, lights: lights, bridges: bridges, sounds: urls, folder: self.directory.appendingPathComponent("Sounds")) != nil
        if started { recordStart(scene.id) }
        return started
    }
}
