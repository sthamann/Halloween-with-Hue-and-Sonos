import Foundation

public struct HueInventory: Sendable {
    public var inputs: [HueInput]
    public var baseline: [HueInputEvent]
    public var resourceCounts: [String: Int] = [:]
    public var motionAreaCount: Int { resourceCounts["motion_area_configuration", default: 0] }
    public var motionCandidateCount: Int { resourceCounts["motion_area_candidate", default: 0] }
}
/// Reads V2 resources and listens to the local server-sent event stream.
/// No rules or lamp configurations on the bridge are overwritten.
public struct HueEventClient: Sendable {
    private let bridge: HueBridge
    private let session: URLSession
    private let key: String?
    public init(bridge: HueBridge) { self.bridge = bridge; session = HueTLS.session(bridgeID: bridge.id, streaming: true); key = CredentialStore.read(bridge.id) }
    init(bridge: HueBridge, session: URLSession, key: String) { self.bridge = bridge; self.session = session; self.key = key }
    private func request(path: String) throws -> URLRequest {
        guard let key, let url = URL(string: "https://\(bridge.ip)\(path)") else { throw AppFailure(L10n.value("Bridge zuerst koppeln.")) }
        var req = URLRequest(url: url); req.setValue(key, forHTTPHeaderField: "hue-application-key"); return req
    }
    public func inventory() async throws -> HueInventory {
        var req = try request(path: "/clip/v2/resource"); req.timeoutInterval = 5
        let (data, response) = try await session.data(for: req)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw AppFailure(L10n.value("Hue-Eingänge konnten nicht gelesen werden.")) }
        return try Self.decodeInventory(data, bridgeID: bridge.id)
    }
    public func listen(connected: @escaping @Sendable () async -> Void = {}, deliver: @escaping @Sendable (HueInputEvent) async -> Void) async throws {
        var req = try request(path: "/eventstream/clip/v2"); req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let connection = HueEventStream(bridgeID: bridge.id)
        defer { connection.stop() }
        var decoder = HueSSEDecoder()
        for try await message in connection.open(req) {
            try Task.checkCancellation()
            switch message {
            case .connected: await connected()
            case .data(let bytes):
                for byte in bytes {
                    for payload in try decoder.append(byte) {
                        for event in try Self.decodeUpdates(payload, bridgeID: bridge.id) { await deliver(event) }
                    }
                }
            }
        }
        throw AppFailure(L10n.value("Hue-Verbindung unterbrochen."))
    }
    public static func decodeInventory(_ data: Data, bridgeID: String) throws -> HueInventory {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], (root["errors"] as? [Any] ?? []).isEmpty,
              let resources = root["data"] as? [[String: Any]] else { throw AppFailure(L10n.value("Ungültige Hue-Eingänge.")) }
        var names: [String: String] = [:]
        var motionAreas: Set<String> = []
        for r in resources {
            if let id = r["id"] as? String, let metadata = r["metadata"] as? [String: Any], let name = metadata["name"] as? String { names[id] = name }
            if r["type"] as? String == "motion_area_configuration" {
                if let id = r["id"] as? String, let name = r["name"] as? String { names[id] = name }
                for ref in r["services"] as? [[String: Any]] ?? [] {
                    if let rid = ref["rid"] as? String {
                        motionAreas.insert(rid)
                        if let name = r["name"] as? String { names[rid] = name }
                    }
                }
                for ref in r["motion_sensors"] as? [[String: Any]] ?? [] { if let rid = ref["rid"] as? String { motionAreas.insert(rid) } }
            }
        }
        var inputs: [HueInput] = []; var baseline: [HueInputEvent] = []
        for r in resources {
            guard let type = r["type"] as? String, let id = r["id"] as? String else { continue }
            let owner = r["owner"] as? [String: String] ?? [:]
            let name = names[id] ?? names[owner["rid"] ?? ""] ?? "Hue \(type)"
            let events: [String]
            switch type {
            case "motion", "grouped_motion", "convenience_area_motion", "security_area_motion": events = ["motion", "no_motion"]
            case "button": events = (r["button"] as? [String: Any])?["event_values"] as? [String] ?? ["initial_press", "short_release", "long_release", "double_short_release", "long_press"]
            case "relative_rotary": events = ["clock_wise", "counter_clock_wise"]
            case "contact": events = ["contact", "no_contact"]
            case "light_level", "grouped_light_level": events = ["dark", "bright"]
            default: continue
            }
            let control = (r["metadata"] as? [String: Any])?["control_id"] as? Int
            let area = motionAreas.contains(id) || type.hasSuffix("area_motion") || owner["rtype"] == "service_group" || owner["rtype"] == "motion_area_configuration"
            let label = name + (control.map { " · \($0)" } ?? "") + (area && events.contains("motion") ? " · MotionAware" : "")
            inputs.append(HueInput(bridgeID: bridgeID, resourceID: id, type: type, name: label, events: events))
            baseline.append(contentsOf: eventsForResource(r, bridgeID: bridgeID, token: "baseline"))
            // Prime buttons even if they have never been pressed.
            if !baseline.contains(where: { $0.sourceID == inputs.last?.id }) { baseline.append(HueInputEvent(sourceID: inputs.last!.id, event: "baseline", token: "baseline")) }
        }
        return HueInventory(inputs: inputs.sorted { $0.name < $1.name }, baseline: baseline,
                            resourceCounts: Dictionary(grouping: resources, by: { $0["type"] as? String ?? "unknown" }).mapValues(\.count))
    }
    public static func decodeUpdates(_ data: Data, bridgeID: String) throws -> [HueInputEvent] {
        guard let envelopes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw AppFailure(L10n.value("Ungültiges Hue-Ereignis.")) }
        return envelopes.filter { $0["type"] as? String == "update" }.flatMap { envelope in
            let token = envelope["id"] as? String ?? envelope["creationtime"] as? String ?? ""
            return (envelope["data"] as? [[String: Any]] ?? []).flatMap { eventsForResource($0, bridgeID: bridgeID, token: token) }
        }
    }
    private static func eventsForResource(_ r: [String: Any], bridgeID: String, token: String) -> [HueInputEvent] {
        guard let id = r["id"] as? String, let type = r["type"] as? String, r["enabled"] as? Bool != false else { return [] }
        let source = "\(bridgeID):\(type):\(id)"
        func event(_ name: String, _ value: Double? = nil, stamp: String? = nil) -> [HueInputEvent] { [HueInputEvent(sourceID: source, event: name, token: stamp ?? token, value: value)] }
        switch type {
        case "motion", "grouped_motion", "convenience_area_motion", "security_area_motion":
            guard let state = r["motion"] as? [String: Any], state["motion_valid"] as? Bool != false, let value = state["motion"] as? Bool else { return [] }
            return event(value ? "motion" : "no_motion", value ? 1 : 0)
        case "button":
            guard let state = r["button"] as? [String: Any], let report = state["button_report"] as? [String: Any], let value = report["event"] as? String else { return [] }
            return event(value, stamp: report["updated"] as? String ?? token)
        case "relative_rotary":
            guard let state = r["relative_rotary"] as? [String: Any], let report = state["rotary_report"] as? [String: Any], let rotation = report["rotation"] as? [String: Any], let direction = rotation["direction"] as? String else { return [] }
            return event(direction, stamp: report["updated"] as? String ?? token)
        case "contact":
            guard let state = r["contact_report"] as? [String: Any], let value = state["state"] as? String else { return [] }
            return event(value == "contact" ? "contact" : "no_contact", value == "contact" ? 1 : 0, stamp: state["changed"] as? String ?? token)
        case "light_level", "grouped_light_level":
            guard let state = r["light"] as? [String: Any], state["light_level_valid"] as? Bool != false, let value = state["light_level"] as? Double else { return [] }
            return event("light_level", pow(10, (value - 1) / 10_000))
        default: return []
        }
    }
}

/// Byte-based framing preserves empty lines (the SSE message delimiter).
public struct HueSSEDecoder: Sendable {
    private var line = Data()
    private var payload = Data()
    public init() {}
    public mutating func append(_ byte: UInt8) throws -> [Data] {
        if byte != 10 { line.append(byte); guard line.count + payload.count <= 1_048_576 else { throw AppFailure(L10n.value("Hue-Ereignis ist zu groß.")) }; return [] }
        if line.last == 13 { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            guard !payload.isEmpty else { return [] }
            let result = payload; payload.removeAll(keepingCapacity: true); return [result]
        }
        if line.starts(with: Data("data:".utf8)) {
            var value = line.dropFirst(5); if value.first == 32 { value = value.dropFirst() }
            if !payload.isEmpty { payload.append(10) }; payload.append(contentsOf: value)
        }
        return []
    }
}
