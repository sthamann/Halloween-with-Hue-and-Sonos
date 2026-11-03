import AVFoundation
import Combine
import Foundation

public struct AppleVoice: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: Int
    public let novelty: Bool
    public var title: String {
        let label = quality >= 3 ? "Premium" : quality >= 2 ? L10n.value("Erweitert") : "Standard"
        return "\(name) · \(language) · \(novelty ? L10n.value("Charakterstimme") : label)"
    }
}

@MainActor public final class VoiceLabStore: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public var name = ""
    @Published public var text = L10n.isEnglish ? "I am here. Behind you." : "Ich bin hier. Hinter dir."
    @Published public var language = L10n.speechLanguage
    @Published public var voiceID = ""
    @Published public var effect = VoiceLabEffect.ghost
    @Published public var intensity = 0.7
    @Published public var trimStart = 0.0
    @Published public var trimEnd = 0.0
    @Published public private(set) var source: URL?
    @Published public private(set) var rendered: URL?
    @Published public private(set) var recording = false
    @Published public private(set) var busy = false
    @Published public private(set) var playing = false
    @Published public private(set) var elapsed = 0.0
    @Published public private(set) var level: Float = 0
    @Published public private(set) var duration = 0.0
    @Published public var error: String?
    @Published public var status: String?
    public let voices: [AppleVoice]
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meter: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private let speech = SpeechRenderer()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("haunt-voice-\(UUID().uuidString)")
    private var sourceText: String?
    private var sourceVoice: String?
    private var closed = false
    public override init() {
        voices = AVSpeechSynthesisVoice.speechVoices().map { AppleVoice(id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue, novelty: $0.voiceTraits.contains(.isNoveltyVoice)) }.sorted { $0.quality == $1.quality ? $0.name < $1.name : $0.quality > $1.quality }
        super.init()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        chooseVoice()
    }
    public var matchingVoices: [AppleVoice] { voices.filter { $0.language.prefix(2) == language.prefix(2) } }
    public var speechNeedsUpdate: Bool {
        guard let sourceText else { return false }
        return text != sourceText || (voices.contains { $0.id == sourceVoice } && voiceID != sourceVoice)
    }
    public var recipe: VoiceLabRecipe { VoiceLabRecipe(effect: effect, intensity: intensity, trimStart: trimStart, trimEnd: trimEnd, text: sourceText, voiceIdentifier: sourceVoice) }
    public func chooseVoice() {
        if !matchingVoices.contains(where: { $0.id == voiceID }) {
            let regular = matchingVoices.filter { !$0.novelty }
            if let best = regular.first, best.quality >= 2 { voiceID = best.id }
            else if let defaultID = AVSpeechSynthesisVoice(language: language)?.identifier, regular.contains(where: { $0.id == defaultID }) { voiceID = defaultID }
            else { voiceID = regular.first?.id ?? matchingVoices.first?.id ?? "" }
        }
    }
    public func invalidate() { stopPreview(); rendered = nil; status = nil }
    public func load(source: URL, recipe: VoiceLabRecipe, name: String) {
        do {
            let raw = try VoiceLabAudio.read(source), dest = folder.appendingPathComponent("source-\(UUID().uuidString).wav")
            try WaveWriter.data(samples: raw.samples, sampleRate: raw.sampleRate).write(to: dest)
            self.source = dest; duration = Double(raw.samples.count) / Double(raw.sampleRate)
            self.name = name; effect = recipe.effect; intensity = recipe.intensity; trimStart = recipe.trimStart; trimEnd = recipe.trimEnd == 0 ? duration : recipe.trimEnd
            sourceText = recipe.text; sourceVoice = recipe.voiceIdentifier
            if let text = recipe.text { self.text = text }
            if let voice = voices.first(where: { $0.id == recipe.voiceIdentifier }) { language = voice.language.hasPrefix("de") ? "de-DE" : "en-US"; voiceID = voice.id }
            invalidate()
        } catch { self.error = error.localizedDescription }
    }
    public func importAudio(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        load(source: url, recipe: VoiceLabRecipe(), name: url.deletingPathExtension().lastPathComponent)
    }
    public func startRecording() async {
        guard !recording, !busy else { return }; stopPreview(); busy = true; error = nil
        #if os(iOS)
        let allowed = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        #else
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        defer { busy = false }
        guard !closed else { return }
        guard allowed else { error = L10n.value("Mikrofonzugriff fehlt. Bitte Haunt in den Systemeinstellungen den Zugriff erlauben."); return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let url = folder.appendingPathComponent("recording-\(UUID().uuidString).wav")
            let record = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            record.delegate = self; record.isMeteringEnabled = true
            guard record.prepareToRecord(), record.record(forDuration: 60) else { throw AppFailure(L10n.value("Die Aufnahme konnte nicht gestartet werden.")) }
            recorder = record; recording = true; elapsed = 0; level = 0; status = nil
            meter = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { return }
                    guard let self, let recorder = self.recorder, self.recording else { return }
                    if !recorder.isRecording { self.finishRecording(); return }
                    recorder.updateMeters(); self.elapsed = recorder.currentTime
                    self.level = max(0, min(1, pow(10, recorder.averagePower(forChannel: 0) / 20)))
                    if self.elapsed >= 60 { self.finishRecording(); return }
                }
            }
        } catch { self.error = error.localizedDescription; releaseSession() }
    }
    public func finishRecording() {
        guard let recorder, recording else { return }
        let url = recorder.url; recording = false; meter?.cancel(); recorder.stop(); self.recorder = nil; level = 0
        releaseSession()
        load(source: url, recipe: VoiceLabRecipe(), name: name.isEmpty ? L10n.value("Meine Spukstimme") : name)
    }
    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.finishRecording(); self.error = L10n.value("Die Aufnahme wurde unterbrochen. Bitte erneut aufnehmen.") }
    }
    private func releaseSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    public func createSpeech(sampleOnly: Bool = false) {
        guard !busy, !recording, !voiceID.isEmpty else { return }
        stopPreview(); error = nil; busy = true
        let chosenText = text, chosenVoice = voiceID
        var newRecipe = recipe; newRecipe.trimStart = 0; newRecipe.trimEnd = 0; newRecipe.text = chosenText; newRecipe.voiceIdentifier = chosenVoice
        work = Task { [weak self] in
            guard let self else { return }; defer { self.busy = false }
            do {
                let url = try await self.speech.render(chosenText, folder: self.folder, language: self.language, effect: .natural, voiceIdentifier: chosenVoice)
                try Task.checkCancellation()
                if sampleOnly { try self.play(url); return }
                self.load(source: url, recipe: newRecipe, name: self.name.isEmpty ? String(chosenText.prefix(45)) : self.name)
                // Preserve chosen effect when making a new spoken original.
                self.status = L10n.value("Text gerendert. Jetzt Effekt wählen und Vorschau starten.")
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    public func renderPreview() {
        guard !busy, !recording, !speechNeedsUpdate, let source else { return }
        stopPreview(); error = nil; busy = true
        let recipe = self.recipe, destination = folder.appendingPathComponent("effect-\(UUID().uuidString).wav")
        work = Task { [weak self] in
            guard let self else { return }; defer { self.busy = false }
            do {
                try await Task.detached(priority: .userInitiated) { try VoiceLabAudio.render(source: source, recipe: recipe, destination: destination) }.value
                try Task.checkCancellation(); self.rendered = destination; try self.play(destination)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    public func previewOriginal() { guard let source, !recording, !busy else { return }; do { try play(source) } catch { self.error = error.localizedDescription } }
    private func play(_ url: URL) throws {
        stopPreview()
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback); try AVAudioSession.sharedInstance().setActive(true)
        #endif
        let player = try AVAudioPlayer(contentsOf: url); player.volume = 0.6
        guard player.play() else { throw AppFailure(L10n.value("Die Hörprobe konnte nicht abgespielt werden.")) }
        self.player = player; playing = true
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if self.player?.isPlaying != true { self.playing = false; if !self.recording { self.releaseSession() }; return }
            }
        }
    }
    public func stopPreview() { meter?.cancel(); player?.stop(); player = nil; playing = false; if !recording { releaseSession() } }
    public func cleanup() {
        closed = true; work?.cancel(); meter?.cancel(); recorder?.stop(); recorder = nil; recording = false; stopPreview()
        try? FileManager.default.removeItem(at: folder)
    }
}
