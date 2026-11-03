import AVFoundation
import Foundation

public enum VoiceLabAudio {
    public static func read(_ url: URL) throws -> (samples: [Float], sampleRate: Int) {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard file.length > 0 else { throw AppFailure(L10n.value("Die Aufnahme enthält keine Audiodaten. Bitte Mikrofon und Audioverbindung prüfen und erneut aufnehmen.")) }
        guard (8000...96000).contains(rate), file.processingFormat.channelCount <= 2, Double(file.length) / rate <= 61,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw AppFailure(L10n.value("Bitte eine Aufnahme mit höchstens 60 Sekunden verwenden.")) }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw AppFailure(L10n.value("Audioformat konnte nicht umgewandelt werden.")) }
        let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        var samples = [Float](repeating: 0, count: count)
        for c in 0..<channelCount { for i in 0..<count { samples[i] += channels[c][i] / Float(channelCount) } }
        guard samples.allSatisfy(\.isFinite) else { throw AppFailure(L10n.value("Diese Audiodatei ist beschädigt.")) }
        return (samples, Int(rate))
    }

    public static func render(source: URL, recipe: VoiceLabRecipe, destination: URL) throws {
        let raw = try read(source)
        let rate = raw.sampleRate, duration = Double(raw.samples.count) / Double(rate)
        let end = recipe.trimEnd == 0 ? duration : recipe.trimEnd
        guard recipe.intensity.isFinite, (0...1).contains(recipe.intensity), recipe.trimStart.isFinite, end.isFinite,
              recipe.trimStart >= 0, end <= duration + 0.02, end - recipe.trimStart >= 0.1 else { throw AppFailure(L10n.value("Der Ausschnitt muss mindestens 0,1 Sekunden lang sein.")) }
        let first = Int(recipe.trimStart * Double(rate)), last = min(raw.samples.count, Int(end * Double(rate)))
        var samples = Array(raw.samples[first..<last])
        if recipe.effect.pitchCents != 0 && recipe.intensity > 0 {
            samples = try pitch(samples, sampleRate: rate, cents: recipe.effect.pitchCents * Float(recipe.intensity))
        }
        let result = process(samples, sampleRate: rate, effect: recipe.effect, intensity: recipe.intensity)
        try WaveWriter.data(samples: result, sampleRate: rate).write(to: destination, options: .atomic)
    }

    // Offline time-pitch keeps the recording's duration and words intact.
    private static func pitch(_ samples: [Float], sampleRate: Int, cents: Float) throws -> [Float] {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), pitch = AVAudioUnitTimePitch()
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        engine.attach(player); engine.attach(pitch); pitch.pitch = cents; pitch.rate = 1
        engine.connect(player, to: pitch, format: format); engine.connect(pitch, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let paddedCount = samples.count + sampleRate
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(paddedCount))!
        input.frameLength = AVAudioFrameCount(paddedCount)
        for i in 0..<paddedCount { input.floatChannelData![0][i] = i < samples.count ? samples[i] : 0 }
        player.scheduleBuffer(input); try engine.start(); player.play()
        defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
        let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var result: [Float] = [], stalls = 0
        while result.count < samples.count {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(4096, samples.count - result.count))
            switch try engine.renderOffline(count, to: output) {
            case .success:
                result.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))); stalls = 0
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                stalls += 1; if stalls > 100 { throw AppFailure(L10n.value("Der Stimmeffekt konnte nicht berechnet werden.")) }
            case .error: throw AppFailure(L10n.value("Der Stimmeffekt konnte nicht berechnet werden."))
            @unknown default: throw AppFailure(L10n.value("Der Stimmeffekt konnte nicht berechnet werden."))
            }
        }
        return result
    }

    public static func process(_ input: [Float], sampleRate: Int, effect: VoiceLabEffect, intensity: Double) -> [Float] {
        guard sampleRate > 0, intensity > 0, effect != .natural else { return input }
        let strength = Float(max(0, min(1, intensity)))
        var output = [Float](repeating: 0, count: input.count + sampleRate * 2)
        var low: Float = 0, high: Float = 0, previous: Float = 0
        var random: UInt64 = 0x726164696f
        for i in input.indices {
            var value = input[i]
            switch effect {
            case .demon:
                value = tanh(value * (1 + 2 * strength)) * (1 - 0.25 * strength + 0.25 * strength * Float(sin(Double(i) * 2 * .pi * 22 / Double(sampleRate))))
            case .radio:
                low += min(1, Float(2 * .pi * 2800 / Double(sampleRate))) * (value - low)
                high = 0.94 * (high + low - previous); previous = low
                random = random &* 6364136223846793005 &+ 1
                let noise = (Float((random >> 40) & 0xffff) / 32768 - 1) * 0.025 * strength
                let dropout = (i / max(1, sampleRate / 17)) % 29 == 7 ? 1 - 0.95 * strength : 1
                value = (value * (1 - strength) + (tanh(high * 2) + noise) * strength) * dropout
            default: break
            }
            output[i] += value * 0.72
            if effect == .ghost || effect == .demon {
                for (delay, gain) in [(0.17, Float(0.32)), (0.39, Float(0.23)), (0.71, Float(0.15)), (1.27, Float(0.07))] {
                    output[i + Int(Double(sampleRate) * delay)] += value * gain * strength
                }
            }
            if effect == .reverseGhost {
                // A rising pre-echo before each word; pad the original so the intro isn't cut off.
                let lead = sampleRate / 2
                output[i] -= value * 0.72; output[i + lead] += value * 0.72
                for (delay, gain) in [(0.12, Float(0.16)), (0.28, Float(0.23)), (0.44, Float(0.31))] {
                    output[max(0, i + lead - Int(Double(sampleRate) * delay))] += value * gain * strength
                }
            }
        }
        let peak = output.map { abs($0) }.max() ?? 0
        let gain: Float = peak > 0.92 ? 0.92 / peak : 1
        return output.map { $0 * gain }
    }
}
