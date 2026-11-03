import AVFoundation
import Foundation

public enum WaveWriter {
    public static func data(samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(); pcm.reserveCapacity(samples.count * 2)
        for value in samples { var v = Int16(max(-1, min(1, value)) * 32_000).littleEndian; withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) } }
        var data = Data()
        func word(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func long(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); long(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8)); long(16); word(1); word(1); long(UInt32(sampleRate)); long(UInt32(sampleRate * 2)); word(2); word(16); data.append(Data("data".utf8)); long(UInt32(pcm.count)); data.append(pcm); return data
    }
}
@MainActor public final class SpeechRenderer {
    private var synthesizer: AVSpeechSynthesizer?
    private var cancelRendering: (() -> Void)?
    public init() {}
    public func render(_ text: String, folder: URL, language: String? = nil, effect: VoiceEffect = .ghost, voiceIdentifier: String? = nil) async throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 300 else { throw AppFailure(L10n.value("Der Spuktext muss zwischen 1 und 300 Zeichen lang sein.")) }
        let synth = AVSpeechSynthesizer(); synthesizer = synth
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier {
            guard let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) else { throw AppFailure(L10n.value("Diese Apple-Stimme ist nicht mehr installiert.")) }
            utterance.voice = voice
        } else { utterance.voice = AVSpeechSynthesisVoice(language: language ?? L10n.speechLanguage) }
        utterance.rate = effect.rate; utterance.pitchMultiplier = effect.pitch; utterance.volume = 0.9
        var samples: [Float] = []; var rate = 22_050.0
        let raw: ([Float], Double) = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
            var complete = false
            cancelRendering = {
                guard !complete else { return }; complete = true
                synth.stopSpeaking(at: .immediate)
                continuation.resume(throwing: CancellationError())
            }
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                let count = Int(pcm.frameLength); let sampleRate = pcm.format.sampleRate
                var values: [Float] = []
                if let channels = pcm.floatChannelData, count > 0 { values = Array(UnsafeBufferPointer(start: channels[0], count: count)) }
                else if let channels = pcm.int16ChannelData, count > 0 { values = (0..<count).map { Float(channels[0][$0]) / 32768 } }
                Task { @MainActor in
                    guard !complete else { return }
                    if count == 0 {
                        complete = true; self.cancelRendering = nil
                        if samples.isEmpty { continuation.resume(throwing: AppFailure(L10n.value("Die deutsche Sprachstimme konnte nicht gerendert werden. Bitte eine deutsche Stimme in den Systemeinstellungen laden."))) }
                        else { continuation.resume(returning: (samples, rate)) }
                    } else { samples.append(contentsOf: values); rate = sampleRate }
                }
            }
        }
        }, onCancel: { Task { @MainActor in self.cancelRendering?(); self.cancelRendering = nil } })
        synthesizer = nil
        try Task.checkCancellation()
        let sampleRate = Int(raw.1)
        let effected = effect.process(raw.0, sampleRate: sampleRate)
        let url = folder.appendingPathComponent("speech-\(UUID().uuidString).wav")
        try WaveWriter.data(samples: effected, sampleRate: sampleRate).write(to: url)
        return url
    }
}
