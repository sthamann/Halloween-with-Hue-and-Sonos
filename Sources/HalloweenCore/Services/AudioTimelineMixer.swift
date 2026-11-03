import Foundation
import AVFoundation

public enum AudioTimelineMixer {
    public static let sampleRate = 22_050
    public static func render(entries: [TimelineEntry], sources: [UUID: URL], folder: URL) throws -> URL? {
        let audio = entries.filter { $0.step.kind.usesRooms }
        guard !audio.isEmpty else { return nil }
        guard audio.allSatisfy({ $0.start.isFinite && (0...600).contains($0.start) && $0.duration.isFinite && (0.1...600).contains($0.duration) }) else { throw AppFailure(L10n.value("Die Audiospur enthält ungültige Zeiten.")) }
        let end = audio.map(\.end).max() ?? 0
        guard end.isFinite, end <= 1200 else { throw AppFailure(L10n.value("Die Audiospur ist zu lang.")) }
        var mixed = [Float](repeating: 0, count: Int(ceil(end * Double(sampleRate))) + sampleRate / 2)
        for entry in audio {
            try Task.checkCancellation()
            guard let url = sources[entry.id] else { throw AppFailure(L10n.value("Eine Audiodatei für die Zeitleiste fehlt.")) }
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0, file.length <= AVAudioFramePosition(file.processingFormat.sampleRate * 600),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw AppFailure(L10n.value("Ungültige Audiodatei.")) }
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { throw AppFailure(L10n.value("Audio konnte nicht dekodiert werden.")) }
            let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
            let ratio = buffer.format.sampleRate / Double(sampleRate)
            let length = min(Int(Double(count) / ratio), Int(entry.duration * Double(sampleRate))), offset = Int((entry.start * Double(sampleRate)).rounded())
            for i in 0..<length where i + offset < mixed.count {
                if i % 22_050 == 0 { try Task.checkCancellation() }
                let position = Double(i) * ratio, index = min(count - 1, Int(position)), next = min(count - 1, index + 1)
                let fraction = Float(position - Double(index))
                var value: Float = 0
                for channel in 0..<channelCount { value += channels[channel][index] * (1 - fraction) + channels[channel][next] * fraction }
                guard value.isFinite else { throw AppFailure(L10n.value("Die Audiodatei enthält ungültige Samples.")) }
                mixed[i + offset] += value / Float(channelCount)
            }
        }
        let peak = mixed.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0.9 { let gain = 0.9 / peak; for i in mixed.indices { mixed[i] *= gain } }
        try Task.checkCancellation()
        let url = folder.appendingPathComponent("timeline-\(UUID().uuidString).wav")
        try WaveWriter.data(samples: mixed, sampleRate: sampleRate).write(to: url)
        return url
    }
}
