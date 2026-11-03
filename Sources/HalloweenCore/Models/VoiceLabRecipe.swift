import Foundation

public enum VoiceLabEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural, ghost, demon, radio, reverseGhost
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .natural: return L10n.value("Original · ohne Effekt")
        case .ghost: return L10n.value("Geist · schwebendes Echo")
        case .demon: return L10n.value("Dämon · tiefe Doppelstimme")
        case .radio: return L10n.value("Verfluchtes Radio")
        case .reverseGhost: return L10n.value("Rückwärts-Spuk")
        }
    }
    public var pitchCents: Float { switch self { case .ghost: return -250; case .demon: return -700; default: return 0 } }
}

public struct VoiceLabRecipe: Codable, Sendable, Equatable {
    public var effect: VoiceLabEffect
    public var intensity: Double
    public var trimStart: Double
    public var trimEnd: Double
    public var text: String?
    public var voiceIdentifier: String?
    public var sourceFilename: String?
    public init(effect: VoiceLabEffect = .ghost, intensity: Double = 0.7, trimStart: Double = 0, trimEnd: Double = 0, text: String? = nil, voiceIdentifier: String? = nil, sourceFilename: String? = nil) {
        self.effect = effect; self.intensity = intensity; self.trimStart = trimStart; self.trimEnd = trimEnd
        self.text = text; self.voiceIdentifier = voiceIdentifier; self.sourceFilename = sourceFilename
    }
}
