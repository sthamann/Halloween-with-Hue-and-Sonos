import Foundation

public struct Speaker: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var ip: String
    public var parentID: String?
    public var groupID: String?
    public var isSatellite: Bool { parentID != nil }
    public init(id: String, name: String, model: String, ip: String, parentID: String? = nil, groupID: String? = nil) {
        self.id = id; self.name = name; self.model = model; self.ip = ip; self.parentID = parentID; self.groupID = groupID
    }
}
public struct HueBridge: Identifiable, Codable, Hashable, Sendable {
    public var id: String; public var ip: String; public var name: String
}
public struct HueLight: Identifiable, Codable, Hashable, Sendable {
    public var id: String; public var bridgeID: String; public var number: String; public var name: String
    public var reachable: Bool; public var color: Bool
    public var currentHue: Double? = nil
    public var currentSaturation: Double? = nil
}
public struct HueRoom: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var bridgeID: String
    public var name: String
    public var lightIDs: Set<String>
    public var isZone: Bool
}
public enum BridgeRegistry {
    public static func merging(_ known: [HueBridge], discovered: [HueBridge]) -> [HueBridge] {
        var byID: [String: HueBridge] = [:]
        for bridge in known + discovered { byID[bridge.id] = bridge }
        return byID.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}
public struct SoundClip: Identifiable, Codable, Hashable, Sendable {
    public var id: String; public var name: String; public var filename: String; public var duration: Double
    public var symbol: String; public var builtIn: Bool
    public var category: String?
    public var credit: SoundCredit?
    public init(id: String = UUID().uuidString, name: String, filename: String, duration: Double, symbol: String = "waveform", builtIn: Bool = false, category: String? = nil, credit: SoundCredit? = nil) {
        self.id = id; self.name = name; self.filename = filename; self.duration = duration; self.symbol = symbol; self.builtIn = builtIn; self.category = category; self.credit = credit
    }
}
public enum StepKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sound, speech, wait, color, flicker, blackout
    public var id: String { rawValue }
    public var title: String {
        switch self { case .sound: return "Sound"; case .speech: return L10n.value("Gruselige Stimme"); case .wait: return L10n.value("Warten"); case .color: return L10n.value("Lichtfarbe"); case .flicker: return L10n.value("Flackern"); case .blackout: return L10n.value("Licht aus") }
    }
    public var symbol: String {
        switch self { case .sound: return "waveform"; case .speech: return "quote.bubble"; case .wait: return "hourglass"; case .color: return "lightbulb.fill"; case .flicker: return "bolt.fill"; case .blackout: return "lightbulb.slash" }
    }
    public var usesRooms: Bool { self == .sound || self == .speech }
    public var usesLights: Bool { self == .color || self == .flicker || self == .blackout }
}
public struct SceneStep: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: StepKind = .sound
    public var soundID = "heartbeat"
    public var text = L10n.value("Wer ist da?")
    public var speechLanguage: String?
    public var voiceEffect: VoiceEffect?
    public var seconds: Double = 4
    public var brightness: Double = 60
    public var hue: Double = 28
    public var startTime: Double?
    public var useLampColor: Bool?
    public var saturation: Double?
    public var audioDuration: Double?
    public var hueEffect: HueEffectKind?
    public var waitForSound = false
    public var roomIDs: Set<String> = []
    public var lightIDs: Set<String> = []
    public init(kind: StepKind = .sound, soundID: String = "heartbeat", seconds: Double = 4) { self.kind = kind; self.soundID = soundID; self.seconds = seconds }
}
public extension SceneStep {
    func copied(startingAt time: Double) -> SceneStep {
        var result = self
        result.id = UUID()
        result.startTime = time
        return result
    }
}
public struct HorrorScene: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name = L10n.value("Meine Spukszene")
    public var symbol = "sparkles"
    public var updatedAt: Date?
    public var isFavorite: Bool?
    public var volume: Double = 25
    public var repetitions = 1
    public var roomIDs: Set<String> = []
    public var lightIDs: Set<String> = []
    public var steps: [SceneStep] = []
    public init(name: String = L10n.value("Meine Spukszene"), symbol: String = "sparkles", steps: [SceneStep] = []) { self.name = name; self.symbol = symbol; self.steps = steps }
    public static var presets: [HorrorScene] {
        var thunder = HorrorScene(name: L10n.value("Das Gewitter"), symbol: "cloud.bolt.rain.fill", steps: [SceneStep(kind: .sound, soundID: "storm"), SceneStep(kind: .flicker, seconds: 8)])
        thunder.steps[1].hue = 230
        var ghost = HorrorScene(name: L10n.value("Da ist jemand"), symbol: "door.left.hand.open", steps: [SceneStep(kind: .sound, soundID: "knocks"), SceneStep(kind: .wait, seconds: 3), SceneStep(kind: .speech), SceneStep(kind: .flicker, seconds: 4)])
        ghost.steps[2].text = L10n.isEnglish ? "I am here." : "Ich bin hier."; ghost.steps[2].speechLanguage = L10n.speechLanguage
        let heart = HorrorScene(name: L10n.value("Herzklopfen"), symbol: "heart.fill", steps: [SceneStep(kind: .color), SceneStep(kind: .sound, soundID: "heartbeat"), SceneStep(kind: .wait, seconds: 8)])
        return [thunder, ghost, heart]
    }
}
public struct AppFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum SceneLibrary {
    /// Legacy scenes keep their relative order until they are saved again.
    public static func sorted(_ scenes: [HorrorScene]) -> [HorrorScene] {
        scenes.enumerated().sorted {
            let left = $0.element.updatedAt ?? .distantPast
            let right = $1.element.updatedAt ?? .distantPast
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }
}
