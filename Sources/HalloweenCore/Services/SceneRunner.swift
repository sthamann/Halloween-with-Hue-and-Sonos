import Foundation
import Combine
import AVFoundation

@MainActor public final class SceneRunner: ObservableObject {
    @Published public private(set) var running = false
    @Published public private(set) var paused = false
    @Published public private(set) var stopping = false
    @Published public private(set) var controlBusy = false
    @Published public private(set) var elapsed = 0.0
    @Published public private(set) var currentStep: UUID?
    @Published public private(set) var status = L10n.value("Bereit für die Nacht.")
    @Published public private(set) var log: [String] = []
    private var task: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private let clock = PlaybackClock()
    private var commandsInFlight = 0
    private var audioRooms: [String: Speaker] = [:]
    private var pausedRooms: [Speaker] = []
    private let hueClient: HueClient
    public init() { hueClient = HueClient() }
    init(hue: HueClient) { hueClient = hue }
    public func stop() {
        guard running else { return }
        stopping = true; task?.cancel(); controlTask?.cancel(); clock.resume(); paused = false
        status = L10n.value("Stoppe und stelle Geräte wieder her …")
    }
    public func pause() {
        guard running, !paused, !stopping, !controlBusy else { return }
        clock.pause(); elapsed = clock.elapsed; paused = true; controlBusy = true; status = L10n.value("Pausiert")
        controlTask = Task {
            defer { self.controlBusy = false }
            do {
                while self.commandsInFlight > 0 { try await Task.sleep(for: .milliseconds(20)) }
                let sonos = SonosClient()
                for room in self.audioRooms.values {
                    try Task.checkCancellation()
                    if try await sonos.state(room) == "PLAYING" { try Task.checkCancellation(); try await sonos.pause(room); self.pausedRooms.append(room) }
                }
            } catch is CancellationError { }
            catch { self.note(L10n.value("Pausieren fehlgeschlagen: \(error.localizedDescription)")); self.stop() }
        }
    }
    public func resume() {
        guard running, paused, !stopping, !controlBusy else { return }
        controlBusy = true
        controlTask = Task {
            defer { self.controlBusy = false }
            do {
                let sonos = SonosClient()
                for room in self.pausedRooms { try Task.checkCancellation(); try await sonos.resume(room) }
                try Task.checkCancellation(); self.pausedRooms = []; self.clock.resume(); self.paused = false; self.status = L10n.value("Ablauf läuft weiter")
            } catch is CancellationError { }
            catch { self.note(L10n.value("Fortsetzen fehlgeschlagen: \(error.localizedDescription)")); self.stop() }
        }
    }
    private func command(_ operation: @MainActor () async throws -> Void) async throws {
        try await clock.checkpoint(); commandsInFlight += 1; defer { commandsInFlight -= 1 }
        try await operation()
    }
    public func start(_ scene: HorrorScene, speakers: [Speaker], lights: [HueLight], bridges: [HueBridge], sounds: [String: URL], folder: URL) {
        guard !running else { return }; running = true; paused = false; stopping = false; controlBusy = false; clock.reset(); audioRooms = [:]; pausedRooms = []; elapsed = 0; log = []; status = L10n.value("Prüfe Geräte …")
        task = Task { await execute(scene, speakers: speakers, lights: lights, bridges: bridges, sounds: sounds, folder: folder) }
    }
    private static func lightFrame(_ frame: HueEffectFrame, step: SceneStep, light: HueLight) -> HueEffectFrame {
        guard step.hueEffect == .ghostFlicker || (step.kind == .flicker && step.hueEffect == nil) else { return frame }
        return HueEffectKind.ghostFlicker.sampledFrame(at: frame.time, brightness: step.brightness, hue: step.hue, seed: HueEffectKind.seed(for: light.id))
    }
    private func note(_ value: String) { status = value; log.append(value); if log.count > 100 { log.removeFirst() } }
    private func pause(_ seconds: Double) async throws { try await clock.wait(until: clock.elapsed + max(0, min(600, seconds))) }
    private func execute(_ scene: HorrorScene, speakers: [Speaker], lights: [HueLight], bridges: [HueBridge], sounds: [String: URL], folder: URL) async {
        let sonos = SonosClient(); let hue = hueClient; let server = AudioServer()
        var roomSnapshots: [SonosSnapshot] = []; var lightSnapshots: [HueSnapshot] = []; var touchedRooms: Set<String> = []; var touchedLights: Set<String> = []; var temporary: [URL] = []
        var failure: String?; var cancelled = false
        let ticker = Task { @MainActor in
            while !Task.isCancelled { let position = self.clock.elapsed; if abs(position - self.elapsed) > 0.02 { self.elapsed = position }; try? await Task.sleep(for: .milliseconds(30)) }
        }
        defer { ticker.cancel() }
        do {
            guard !scene.steps.isEmpty else { throw AppFailure(L10n.value("Füge mindestens einen Schritt hinzu.")) }
            guard (1...10).contains(scene.repetitions), scene.volume.isFinite, (0...100).contains(scene.volume) else { throw AppFailure(L10n.value("Ungültige Szeneneinstellungen.")) }
            var targets: [UUID: [Speaker]] = [:]; var lightTargets: [UUID: [(HueLight, HueBridge)]] = [:]; var rendered: [UUID: URL] = [:]
            for step in scene.steps {
                try Task.checkCancellation()
                guard step.seconds.isFinite, (0...600).contains(step.seconds), step.brightness.isFinite, (0...100).contains(step.brightness), step.hue.isFinite, (0...360).contains(step.hue) else { throw AppFailure(L10n.value("Ein Schritt enthält ungültige Werte.")) }
                if step.kind.usesRooms {
                    let ids = step.roomIDs.isEmpty ? scene.roomIDs : step.roomIDs
                    let selected = try await sonos.validatedTargets(ids, known: speakers)
                    targets[step.id] = selected
                    for room in selected where !roomSnapshots.contains(where: { $0.speaker.id == room.id }) { roomSnapshots.append(try await sonos.snapshot(room)) }
                    if step.kind == .sound { guard let url = sounds[step.soundID], FileManager.default.fileExists(atPath: url.path) else { throw AppFailure(L10n.value("Ein Sound fehlt. Wähle ihn im Szeneneditor erneut aus.")) }; rendered[step.id] = url }
                    else { let url = try await SpeechRenderer().render(step.text, folder: folder, language: step.speechLanguage, effect: step.voiceEffect ?? .ghost); temporary.append(url); rendered[step.id] = url }
                }
                if step.kind.usesLights {
                    let ids = step.lightIDs.isEmpty ? scene.lightIDs : step.lightIDs
                    guard !ids.isEmpty else { throw AppFailure(L10n.value("Für \(step.kind.title) bitte Hue-Lampen auswählen und die Bridge koppeln.")) }
                    var pairs: [(HueLight, HueBridge)] = []
                    for id in ids {
                        guard let light = lights.first(where: { $0.id == id }), let bridge = bridges.first(where: { $0.id == light.bridgeID }) else { throw AppFailure(L10n.value("Eine ausgewählte Hue-Lampe fehlt. Suche die Geräte erneut.")) }
                        pairs.append((light, bridge))
                        if !lightSnapshots.contains(where: { $0.light.id == id }) { lightSnapshots.append(try await hue.snapshot(light, bridge: bridge)) }
                    }
                    lightTargets[step.id] = pairs
                }
            }
            if !roomSnapshots.isEmpty { try await server.start() }
            try Task.checkCancellation()
            if scene.steps.contains(where: { $0.startTime != nil }) {
                var durations: [String: Double] = [:]; var speechDurations: [UUID: Double] = [:]
                for step in scene.steps where step.kind.usesRooms {
                    guard let file = rendered[step.id] else { throw AppFailure(L10n.value("Audiodatei fehlt.")) }
                    let duration = try AVAudioPlayer(contentsOf: file).duration
                    if step.kind == .sound { durations[step.soundID] = duration } else { speechDurations[step.id] = duration }
                }
                let plan = SceneTimeline(scene: scene, soundDurations: durations, speechDurations: speechDurations)
                try plan.validate(scene: scene)
                var tracks: [(Speaker, URL, Double)] = []
                for snapshot in roomSnapshots {
                    let room = snapshot.speaker
                    let entries = plan.entries.filter { targets[$0.id]?.contains(where: { $0.id == room.id }) == true }
                    if let file = try await Task.detached(operation: { try AudioTimelineMixer.render(entries: entries, sources: rendered, folder: folder) }).value {
                        temporary.append(file); tracks.append((room, file, try AVAudioPlayer(contentsOf: file).duration))
                    }
                }
                for repetition in 1...scene.repetitions {
                    try Task.checkCancellation(); note(L10n.value("Zeitleiste · Durchlauf \(repetition) von \(scene.repetitions)"))
                    clock.reset(paused: paused)
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (room, file, duration) in tracks {
                            let url = server.serve(file); touchedRooms.insert(room.id)
                            group.addTask { @MainActor in
                                try Task.checkCancellation()
                                try await self.command { self.audioRooms[room.id] = room; try await sonos.play(room, url: server.reachableURL(url, for: room.ip), volume: Int(scene.volume)) }
                                try await self.pause(0.2)
                                guard try await sonos.state(room) == "PLAYING", server.requestCount(url, from: room.ip) > 0 else { throw AppFailure(L10n.value("\(room.name) konnte die Zeitleisten-Audiospur nicht bestätigen.")) }
                                self.note(L10n.value("Wiedergabe bestätigt: \(room.name)"))
                                try await self.pause(duration)
                            }
                        }
                        group.addTask { @MainActor in
                            try await TimelineScheduler.run(plan, clock: self.clock) { entry in
                                self.currentStep = entry.id
                                if !entry.step.kind.usesLights { return }
                                let step = entry.step
                                let frames = step.kind == .flicker ? (step.hueEffect ?? .ghostFlicker).frames(duration: entry.duration, brightness: step.brightness, hue: step.hue) : [HueEffectFrame(time: 0, brightness: step.brightness, hue: step.hue, saturation: step.saturation ?? 100)]
                                for (frameIndex, frame) in frames.enumerated() {
                                    try await self.clock.wait(until: entry.start + frame.time)
                                    // Slow bridges must not replay overdue frames after the next cue
                                    // (e.g. send flicker colors after a blackout has switched lights off).
                                    if step.kind == .flicker {
                                        if self.clock.elapsed >= entry.start + entry.duration { break }
                                        if frameIndex + 1 < frames.count,
                                           self.clock.elapsed >= entry.start + frames[frameIndex + 1].time { continue }
                                    }
                                    for (light, bridge) in lightTargets[step.id] ?? [] {
                                        if step.kind == .flicker, self.clock.elapsed >= entry.start + entry.duration { break }
                                        try Task.checkCancellation(); touchedLights.insert(light.id)
                                        let applied = Self.lightFrame(frame, step: step, light: light)
                                        try await self.command { try await hue.set(light, bridge: bridge, on: step.kind != .blackout && applied.brightness > 0, brightness: applied.brightness, hue: step.kind == .blackout || step.useLampColor == true ? nil : applied.hue, saturation: step.saturation ?? applied.saturation, transition: applied.transition) }
                                        if frame.time == 0 { self.note(L10n.value("Lichtbefehl bestätigt: \(light.name) · \(bridge.name)")) }
                                    }
                                }
                            }
                        }
                        try await group.waitForAll()
                    }
                }
            } else {
            clock.reset(paused: paused)
            var soundEnds: [String: Double] = [:]
            for repetition in 1...scene.repetitions {
                if scene.repetitions > 1 { note(L10n.value("Durchlauf \(repetition) von \(scene.repetitions)")) }
                for (index, step) in scene.steps.enumerated() {
                    try await clock.checkpoint(); currentStep = step.id; note("\(index + 1)/\(scene.steps.count) · \(step.kind.title)")
                    switch step.kind {
                    case .sound, .speech:
                        guard let file = rendered[step.id] else { throw AppFailure(L10n.value("Sounddatei fehlt.")) }
                        let duration = try AVAudioPlayer(contentsOf: file).duration; let url = server.serve(file)
                        let rooms = targets[step.id] ?? []
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            for room in rooms {
                                touchedRooms.insert(room.id)
                                group.addTask { @MainActor in try await self.command { self.audioRooms[room.id] = room; try await sonos.play(room, url: server.reachableURL(url, for: room.ip), volume: Int(scene.volume)) } }
                            }
                            try await group.waitForAll()
                        }
                        for room in rooms { soundEnds[room.id] = clock.elapsed + duration + 0.5 }
                        try await pause(0.2)
                        for room in rooms { guard try await sonos.state(room) == "PLAYING" else { throw AppFailure(L10n.value("\(room.name) hat die Wiedergabe nicht bestätigt.")) } }
                        for room in rooms { guard server.requestCount(url, from: room.ip) > 0 else { throw AppFailure(L10n.value("\(room.name) konnte die Sounddatei nicht vom Gerät abrufen. Prüfe WLAN und Firewall.")) } }
                        log.append(L10n.value("Wiedergabe bestätigt: \(rooms.map(\.name).joined(separator: ", "))"))
                        if step.waitForSound { try await pause(duration) }
                    case .wait: try await pause(step.seconds)
                    case .color, .blackout:
                        for (light, bridge) in lightTargets[step.id] ?? [] { try Task.checkCancellation(); touchedLights.insert(light.id); try await command { try await hue.set(light, bridge: bridge, on: step.kind != .blackout && step.brightness > 0, brightness: step.brightness, hue: step.kind == .blackout || step.useLampColor == true ? nil : step.hue, saturation: step.saturation ?? 100) } }
                    case .flicker:
                        let origin = clock.elapsed
                        for frame in (step.hueEffect ?? .ghostFlicker).frames(duration: step.seconds, brightness: step.brightness, hue: step.hue) {
                            try await clock.wait(until: origin + frame.time)
                            for (light, bridge) in lightTargets[step.id] ?? [] { try Task.checkCancellation(); touchedLights.insert(light.id); let applied = Self.lightFrame(frame, step: step, light: light); try await command { try await hue.set(light, bridge: bridge, on: applied.brightness > 0, brightness: applied.brightness, hue: step.kind == .blackout || step.useLampColor == true ? nil : applied.hue, saturation: step.saturation ?? applied.saturation, transition: applied.transition) } }
                        }
                        try await clock.wait(until: origin + step.seconds)
                    }
                }
                if let end = soundEnds.values.max() { try await clock.wait(until: end); soundEnds.removeAll() }
            }
            }
        } catch is CancellationError { cancelled = true }
        catch { failure = error.localizedDescription }
        stopping = true; controlTask?.cancel(); await controlTask?.value; clock.resume(); paused = false
        note(L10n.value("Stelle vorherige Zustände wieder her …")); currentStep = nil
        let roomCleanup = roomSnapshots.filter { touchedRooms.contains($0.speaker.id) }; let lightCleanup = lightSnapshots.filter { touchedLights.contains($0.light.id) }
        let restoreErrors = await Task.detached { () -> [String] in
            var errors: [String] = []
            for snapshot in roomCleanup { do { try await sonos.restore(snapshot) } catch { errors.append(error.localizedDescription) } }
            for snapshot in lightCleanup { do { try await hue.restore(snapshot) } catch { errors.append(error.localizedDescription) } }
            return errors
        }.value
        server.stop(); temporary.forEach { try? FileManager.default.removeItem(at: $0) }
        if let failure { note(L10n.value("Abgebrochen: \(failure)")) }
        else if cancelled { note(L10n.value("Gestoppt. Vorherige Zustände wiederhergestellt.")) }
        else { note(L10n.value("\(scene.name) beendet. Vorherige Zustände wiederhergestellt.")) }
        if !restoreErrors.isEmpty { note(L10n.value("Wiederherstellung unvollständig: \(restoreErrors.joined(separator: " · "))")) }
        running = false; stopping = false; controlBusy = false; task = nil; controlTask = nil
    }
}
