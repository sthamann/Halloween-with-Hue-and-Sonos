import Foundation

public struct HueEffectFrame: Equatable, Sendable {
    public var time: Double
    public var brightness: Double
    public var hue: Double
    public var saturation: Double
    public var transition: Double
    public init(time: Double, brightness: Double, hue: Double, saturation: Double = 100, transition: Double = 0) { self.time = time; self.brightness = brightness; self.hue = hue; self.saturation = saturation; self.transition = transition }
}
public enum HueEffectKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case ghostFlicker, lightning, heartbeat, candle, hauntedPulse, colorSweep
    public var id: String { rawValue }
    public var title: String {
        switch self { case .ghostFlicker: return L10n.value("Geisterhaftes Flackern"); case .lightning: return L10n.value("Gewitterblitze"); case .heartbeat: return L10n.value("Blutroter Herzschlag"); case .candle: return L10n.value("Verfluchte Kerze"); case .hauntedPulse: return L10n.value("Spuklicht"); case .colorSweep: return L10n.value("Geisterportal") }
    }
    public var symbol: String {
        switch self { case .ghostFlicker: return "wind"; case .lightning: return "cloud.bolt.fill"; case .heartbeat: return "heart.fill"; case .candle: return "flame.fill"; case .hauntedPulse: return "moon.haze.fill"; case .colorSweep: return "sparkles" }
    }
    public var defaultHue: Double { switch self { case .ghostFlicker: return 180; case .lightning: return 230; case .heartbeat: return 0; case .candle: return 28; case .hauntedPulse: return 280; case .colorSweep: return 110 } }
    public var detail: String {
        switch self { case .ghostFlicker: return L10n.value("Stotternde Lichtstöße, plötzliche Aussetzer und lange dunkle Pausen."); case .lightning: return L10n.value("Weiße Blitze über dunkelblauer Nacht."); case .heartbeat: return L10n.value("Zwei rote Pulse, dann eine dunkle Pause."); case .candle: return L10n.value("Warm und flackernd wie eine alte Kerze."); case .hauntedPulse: return L10n.value("Violettes Licht atmet langsam auf und ab."); case .colorSweep: return L10n.value("Ein wanderndes Portal aus Grün, Blau und Violett.") }
    }
    public func frame(at time: Double, brightness: Double, hue: Double, seed: UInt64 = 0) -> HueEffectFrame {
        let t = max(0, time); let level = max(0, min(100, brightness))
        if level == 0 { return HueEffectFrame(time: t, brightness: 0, hue: hue) }
        switch self {
        case .ghostFlicker:
            return Self.horrorFrames(duration: t + 0.00001, brightness: level, hue: hue, seed: seed).last ?? HueEffectFrame(time: 0, brightness: level, hue: hue)
        case .lightning:
            let phase = t.truncatingRemainder(dividingBy: 4)
            let flash = phase >= 1 - 0.000001 && phase < 1.4 - 0.000001
            return HueEffectFrame(time: t, brightness: flash ? level : 3, hue: hue, saturation: flash ? 0 : 85)
        case .heartbeat:
            let phase = t.truncatingRemainder(dividingBy: 2.4)
            return HueEffectFrame(time: t, brightness: phase < 0.35 || (phase >= 0.8 && phase < 1.15) ? level : 4, hue: hue, transition: 0.1)
        case .candle:
            return HueEffectFrame(time: t, brightness: level * (0.6 + 0.4 * abs(sin(t * 3.2) * cos(t * 1.9))), hue: hue, saturation: 85, transition: 0.3)
        case .hauntedPulse:
            return HueEffectFrame(time: t, brightness: level * (0.08 + 0.92 * (sin(t * .pi / 3 - .pi / 2) + 1) / 2), hue: hue, saturation: 90, transition: 0.5)
        case .colorSweep:
            return HueEffectFrame(time: t, brightness: level * 0.8, hue: (hue + t * 22).truncatingRemainder(dividingBy: 360), transition: 0.5)
        }
    }
    public func sampledFrame(at time: Double, brightness: Double, hue: Double, seed: UInt64 = 0) -> HueEffectFrame {
        if self == .ghostFlicker { return frame(at: time, brightness: brightness, hue: hue, seed: seed) }
        if self == .lightning {
            let t = max(0, time), cycle = floor(t / 4) * 4, phase = t - cycle
            return frame(at: cycle + (phase >= 1.4 ? 1.4 : phase >= 1 ? 1 : 0), brightness: brightness, hue: hue)
        }
        let interval = self == .heartbeat ? 0.4 : 0.6
        return frame(at: floor(max(0, time) / interval + 0.000001) * interval, brightness: brightness, hue: hue)
    }
    public func frames(duration: Double, brightness: Double, hue: Double, seed: UInt64 = 0) -> [HueEffectFrame] {
        guard duration.isFinite, (0...600).contains(duration) else { return [] }
        if self == .ghostFlicker { return Self.horrorFrames(duration: duration, brightness: brightness, hue: hue, seed: seed) }
        if self == .lightning {
            return stride(from: 0.0, to: duration, by: 4).flatMap { cycle in [0.0, 1.0, 1.4].map { cycle + $0 }.filter { $0 < duration }.map { frame(at: $0, brightness: brightness, hue: hue) } }
        }
        let interval = self == .heartbeat ? 0.4 : 0.6
        return stride(from: 0.0, to: max(0.1, duration), by: interval).map { frame(at: $0, brightness: brightness, hue: hue) }
    }
    public static func seed(for id: String) -> UInt64 {
        id.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    private static func noise(_ index: Int, _ salt: UInt64) -> Double {
        var x = UInt64(index) &* 0x9E3779B97F4A7C15 &+ salt &+ 0x517CC1B727220A95
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return Double((x ^ (x >> 31)) >> 11) / 9007199254740992
    }
    private static func horrorFrames(duration: Double, brightness: Double, hue: Double, seed: UInt64) -> [HueEffectFrame] {
        let level = max(0, min(100, brightness))
        var result: [HueEffectFrame] = []; var time = 0.0; var index = 0
        while time < duration {
            let r = noise(index, seed)
            let gap = index % 11 == 7
            let intensity = gap ? 0.0 : r < 0.28 ? 0.01 : r < 0.48 ? 0.07 : r < 0.65 ? 0.28 : r < 0.82 ? 0.65 : 1.0
            result.append(HueEffectFrame(time: time, brightness: level * intensity, hue: hue, saturation: 65, transition: 0))
            // Broken ballast: short sputtering bursts, irregular holds and long blackouts.
            let jitter = noise(index, 71)
            time += gap ? 1.3 + jitter * 0.8 : (1...3).contains(index % 7) ? 0.18 + jitter * 0.14 : 0.25 + jitter * 0.7
            index += 1
        }
        return result
    }

}
public enum EffectCombos {
    public static var scenes: [HorrorScene] {
        [combo(L10n.value("Defekte Spuklampe"), "bolt.trianglebadge.exclamationmark.fill", "electric-crackle", .ghostFlicker, 12),
         combo(L10n.value("Gewitternacht"), "cloud.bolt.rain.fill", "storm", .lightning, 12),
         combo(L10n.value("Das Geisterhaus"), "house.fill", "cc0-ghost-3", .ghostFlicker, 12),
         combo(L10n.value("Herz der Dunkelheit"), "heart.fill", "heartbeat", .heartbeat, 12),
         combo(L10n.value("Verfluchte Kerze"), "flame.fill", "creak", .candle, 14),
         combo(L10n.value("Das Monsterportal"), "sparkles", "cc0-ambient-horror", .colorSweep, 24)]
    }
    private static func combo(_ name: String, _ symbol: String, _ sound: String, _ effect: HueEffectKind, _ duration: Double) -> HorrorScene {
        var audio = SceneStep(kind: .sound, soundID: sound); audio.startTime = 0
        var light = SceneStep(kind: .flicker, seconds: duration); light.startTime = 0; light.hueEffect = effect; light.hue = effect.defaultHue; light.brightness = 70
        if sound == "electric-crackle" { light.useLampColor = true }
        var scene = HorrorScene(name: name, symbol: symbol, steps: [audio, light])
        if name == L10n.value("Das Geisterhaus") { var speech = SceneStep(kind: .speech); speech.text = L10n.isEnglish ? "Jana. I am here." : "Jana. Ich bin hier."; speech.speechLanguage = L10n.speechLanguage; speech.startTime = 6; scene.steps.append(speech) }
        return scene
    }
}
