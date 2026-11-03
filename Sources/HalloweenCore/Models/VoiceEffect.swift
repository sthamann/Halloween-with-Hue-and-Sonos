import Foundation

public enum VoiceEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case ghost, demon, natural
    public var id: String { rawValue }
    public var title: String { switch self { case .ghost: return L10n.value("Geist · mit Echo"); case .demon: return L10n.value("Dämon · tief & verzerrt"); case .natural: return L10n.value("Klare Ansage") } }
    public var pitch: Float { switch self { case .ghost: return 0.65; case .demon: return 0.5; case .natural: return 1 } }
    public var rate: Float { self == .natural ? 0.45 : 0.32 }
    public func process(_ input: [Float], sampleRate: Int) -> [Float] {
        guard sampleRate > 0 else { return input }
        if self == .natural { return input }
        var output = [Float](repeating: 0, count: input.count + sampleRate)
        for i in input.indices {
            let value: Float = self == .demon ? tanh(input[i] * 2.5) * (0.7 + 0.3 * Float(sin(Double(i) * 2 * .pi * 24 / Double(sampleRate)))) : input[i]
            output[i] += value * 0.72
            for (delay, gain) in [(0.18, Float(0.25)), (0.43, Float(0.16)), (0.78, Float(0.09))] { output[i + Int(Double(sampleRate) * delay)] += value * gain }
        }
        return output.map { max(-0.95, min(0.95, $0)) }
    }
}
