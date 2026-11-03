import Foundation

public enum TriggerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case once, time, interval, hue
    public var id: String { rawValue }
    public var title: String { switch self { case .once: return L10n.value("Datum & Uhrzeit"); case .time: return L10n.value("Uhrzeit & Wochentage"); case .interval: return L10n.value("Regelmäßig wiederholen"); case .hue: return L10n.value("Hue-Sensor oder Taster") } }
}
public struct AutomationRule: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name = L10n.value("Mein Auslöser")
    public var sceneID: UUID
    public var enabled = false
    public var kind: TriggerKind = .time
    public var date = Date().addingTimeInterval(300)
    public var hour = 20
    public var minute = 0
    /// Calendar weekday: 1 Sunday, 2 Monday ... 7 Saturday.
    public var weekdays: Set<Int> = Set(1...7)
    public var interval: Double = 300
    public var sourceID = ""
    public var event = "motion"
    public var threshold: Double = 10
    public var cooldown: Double = 30
    public var windowEnabled = false
    public var windowStart = 18 * 60
    public var windowEnd = 23 * 60
    public init(sceneID: UUID) { self.sceneID = sceneID }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...23).contains(hour), (0...59).contains(minute), weekdays.isSubset(of: Set(1...7)),
              interval.isFinite, (10...86_400).contains(interval), cooldown.isFinite, (5...86_400).contains(cooldown),
              threshold.isFinite, (0...100_000).contains(threshold), (0..<1440).contains(windowStart), (0..<1440).contains(windowEnd),
              date.timeIntervalSince1970.isFinite else { throw AppFailure(L10n.value("Ungültige Auslöser-Einstellungen.")) }
        if kind == .time && weekdays.isEmpty { throw AppFailure(L10n.value("Wähle mindestens einen Wochentag.")) }
        if kind == .hue && sourceID.isEmpty { throw AppFailure(L10n.value("Wähle einen Hue-Sensor oder Taster.")) }
    }
    public func isInsideWindow(_ now: Date, calendar: Calendar = .current) -> Bool {
        guard windowEnabled else { return true }
        let c = calendar.dateComponents([.hour, .minute], from: now), value = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return windowStart <= windowEnd ? value >= windowStart && value < windowEnd : value >= windowStart || value < windowEnd
    }
    public func occurrence(at now: Date, calendar: Calendar = .current) -> String? {
        guard enabled, (try? validate()) != nil, isInsideWindow(now, calendar: calendar) else { return nil }
        switch kind {
        case .hue: return nil
        case .once:
            // No delayed catch-up after restart/sleep/background.
            guard now >= date, now.timeIntervalSince(date) < 2 else { return nil }
            return "once"
        case .time:
            let c = calendar.dateComponents([.weekday, .hour, .minute, .second], from: now)
            guard weekdays.contains(c.weekday ?? 0), c.hour == hour, c.minute == minute, (c.second ?? 60) < 2 else { return nil }
            return "time:\(calendar.startOfDay(for: now).timeIntervalSince1970):\(hour):\(minute)"
        case .interval:
            let elapsed = now.timeIntervalSince(date)
            guard elapsed >= 0 else { return nil }
            let n = floor(elapsed / interval)
            guard elapsed - n * interval < 2 else { return nil }
            return "interval:\(date.timeIntervalSince1970):\(Int(n))"
        }
    }
}
public struct HueInput: Identifiable, Codable, Hashable, Sendable {
    public var id: String; public var bridgeID: String; public var resourceID: String; public var type: String; public var name: String
    public var events: [String]
    public init(bridgeID: String, resourceID: String, type: String, name: String, events: [String]) {
        self.id = "\(bridgeID):\(type):\(resourceID)"; self.bridgeID = bridgeID; self.resourceID = resourceID; self.type = type; self.name = name; self.events = events
    }
}
public struct HueInputEvent: Equatable, Sendable {
    public var sourceID: String; public var event: String; public var token: String; public var value: Double?
    public init(sourceID: String, event: String, token: String, value: Double? = nil) { self.sourceID = sourceID; self.event = event; self.token = token; self.value = value }
}
/// Stateful edge detection. A baseline/read or reconnect never plays a scene.
public struct TriggerGate: Sendable {
    private var occurrences: [UUID: String] = [:]
    private var lastFire: [UUID: Date] = [:]
    private var states: [String: Double] = [:]
    private var eventTokens: [String: String] = [:]
    public init() {}
    public mutating func prime(_ events: [HueInputEvent]) {
        for event in events { if let value = event.value { states[event.sourceID] = value }; eventTokens[event.sourceID] = event.token }
    }
    public mutating func scheduled(_ rules: [AutomationRule], now: Date, calendar: Calendar = .current) -> [AutomationRule] {
        rules.filter { rule in
            guard let occurrence = rule.occurrence(at: now, calendar: calendar), occurrences[rule.id] != occurrence else { return false }
            occurrences[rule.id] = occurrence
            return accept(rule, now: now)
        }
    }
    public mutating func receive(_ event: HueInputEvent, rules: [AutomationRule], now: Date) -> [AutomationRule] {
        let old = states[event.sourceID]
        if let value = event.value { states[event.sourceID] = value }
        let token = eventTokens[event.sourceID]; eventTokens[event.sourceID] = event.token
        guard token != nil, token != event.token else { return [] }
        return rules.filter { rule in
            guard rule.enabled, rule.kind == .hue, rule.sourceID == event.sourceID, rule.isInsideWindow(now), (try? rule.validate()) != nil else { return false }
            let matches: Bool
            switch rule.event {
            case "motion", "no_motion", "contact", "no_contact":
                let desired = rule.event.hasPrefix("no_") ? 0.0 : 1.0
                matches = old != nil && event.value == desired && old != desired
            case "dark", "bright":
                if let old, let value = event.value { matches = rule.event == "dark" ? old >= rule.threshold && value < rule.threshold : old <= rule.threshold && value > rule.threshold } else { matches = false }
            default: matches = event.event == rule.event
            }
            return matches && accept(rule, now: now)
        }
    }
    private mutating func accept(_ rule: AutomationRule, now: Date) -> Bool {
        guard now.timeIntervalSince(lastFire[rule.id] ?? .distantPast) >= rule.cooldown else { return false }
        lastFire[rule.id] = now; return true
    }
}
