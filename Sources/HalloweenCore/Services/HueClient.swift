import Foundation
import Security

public enum CredentialStore {
    private static let service = "de.hamann.halloweensonos.hue"
    private static let cacheLock = NSLock()
    private static let keychainLock = NSLock()
    private static var cached: [String: String] = [:]
    private static var checked: Set<String> = []
    // Rendering, polling and playback must never present authentication UI.
    public static func read(_ bridgeID: String) -> String? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if checked.contains(bridgeID) { return cached[bridgeID] }
        let value = read(bridgeID, allowInteraction: false)
        checked.insert(bridgeID); cached[bridgeID] = value
        return value
    }
    /// Only call in direct response to the user's unlock button.
    public static func requestAccess(_ bridgeID: String) -> Bool {
        let value = read(bridgeID, allowInteraction: true)
        cacheLock.lock(); defer { cacheLock.unlock() }
        checked.insert(bridgeID); cached[bridgeID] = value
        return value != nil
    }
    static func read(_ bridgeID: String, allowInteraction: Bool,
                     copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching) -> String? {
        keychainLock.lock(); defer { keychainLock.unlock() }
        #if os(macOS)
        // Legacy macOS keychains can still prompt despite kSecUseAuthenticationUIFail.
        // Disable interaction for this synchronous read and restore the prior policy.
        var wasAllowed = DarwinBoolean(true)
        let readPolicy = SecKeychainGetUserInteractionAllowed(&wasAllowed)
        if !allowInteraction { SecKeychainSetUserInteractionAllowed(false) }
        defer { if !allowInteraction, readPolicy == errSecSuccess { SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) } }
        #endif
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: bridgeID,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
        var item: CFTypeRef?
        guard copyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public static func save(_ value: String, bridgeID: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: bridgeID]
        let data = Data(value.utf8); let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
            var new = query; new[kSecValueData as String] = data; new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw AppFailure(L10n.value("Hue-Schlüssel konnte nicht im Schlüsselbund gespeichert werden.")) }
        } else if updated != errSecSuccess { throw AppFailure(L10n.value("Hue-Schlüssel konnte nicht aktualisiert werden.")) }
        cacheLock.lock(); defer { cacheLock.unlock() }
        checked.insert(bridgeID); cached[bridgeID] = value
    }
}
public struct HueSnapshot: @unchecked Sendable {
    let light: HueLight; let bridge: HueBridge; let key: String; let state: [String: Any]
}
public struct HueClient: Sendable {
    private let network: NetworkClient
    private let injected: Bool
    private let credential: @Sendable (String) -> String?
    public init() { network = NetworkClient(session: HueTLS.session(bridgeID: nil)); injected = false; credential = { CredentialStore.read($0) } }
    init(network: NetworkClient, credential: @escaping @Sendable (String) -> String?) { self.network = network; injected = true; self.credential = credential }

    public func probe(_ ip: String) async -> HueBridge? {
        guard let data = try? await network.request("https://\(ip)/api/config", timeout: 1), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = obj["bridgeid"] as? String, let model = obj["modelid"] as? String, model.hasPrefix("BSB") else { return nil }
        if !injected {
            let verified = NetworkClient(session: HueTLS.session(bridgeID: id))
            guard let confirmed = try? await verified.request("https://\(ip)/api/config", timeout: 3),
                  let config = try? JSONSerialization.jsonObject(with: confirmed) as? [String: Any],
                  (config["bridgeid"] as? String)?.lowercased() == id.lowercased() else { return nil }
        }
        return HueBridge(id: id, ip: ip, name: obj["name"] as? String ?? "Hue Bridge")
    }
    private func json(_ bridge: HueBridge, path: String, method: String = "GET", body: [String: Any]? = nil, retries: Int = 2) async throws -> Any {
        let transport = injected ? network : NetworkClient(session: HueTLS.session(bridgeID: bridge.id))
        let data = try await transport.request("https://\(bridge.ip)/api\(path)", method: method, body: try body.map { try JSONSerialization.data(withJSONObject: $0) }, headers: ["Content-Type": "application/json"])
        let obj = try JSONSerialization.jsonObject(with: data)
        if let array = obj as? [[String: Any]] {
            for item in array {
                if let error = item["error"] as? [String: Any] {
                    // Idempotent state writes may hit the bridge's transient internal
                    // resource error. Retry briefly; persistent errors still abort visibly.
                    if method == "PUT", retries > 0,
                       error["description"] as? String == "Internal error, 404" {
                        try await Task.sleep(for: .milliseconds(250 * (3 - retries)))
                        return try await json(bridge, path: path, method: method, body: body, retries: retries - 1)
                    }
                    if error["type"] as? Int == 101 { throw AppFailure(L10n.value("Drücke den runden Knopf auf der Hue-Bridge und tippe innerhalb von 30 Sekunden erneut auf Koppeln.")) }
                    throw AppFailure("Hue \(bridge.name) \(path.split(separator: "/").dropFirst().joined(separator: "/")): \(error["description"] as? String ?? "Anfrage abgelehnt")")
                }
            }
        }
        return obj
    }
    public func pair(_ bridge: HueBridge) async throws {
        let obj = try await json(bridge, path: "", method: "POST", body: ["devicetype": "HalloweenSonos#Apple"])
        guard let array = obj as? [[String: Any]], let success = array.first?["success"] as? [String: Any], let key = success["username"] as? String else { throw AppFailure(L10n.value("Hue hat keinen App-Schlüssel zurückgegeben.")) }
        try CredentialStore.save(key, bridgeID: bridge.id)
    }
    private func key(_ bridge: HueBridge) throws -> String { guard let key = credential(bridge.id) else { throw AppFailure(L10n.value("\(bridge.name) zuerst mit dem Bridge-Knopf koppeln.")) }; return key }
    public func lights(_ bridge: HueBridge) async throws -> [HueLight] {
        let key = try key(bridge); guard let obj = try await json(bridge, path: "/\(key)/lights") as? [String: [String: Any]] else { throw AppFailure(L10n.value("Hue-Lampen konnten nicht gelesen werden.")) }
        return Self.decodeLights(obj, bridge: bridge)
    }
    static func decodeLights(_ obj: [String: [String: Any]], bridge: HueBridge) -> [HueLight] {
        obj.map { number, light in
            let state = light["state"] as? [String: Any] ?? [:]
            let type = light["type"] as? String
            let supportsColor = type.map { $0.localizedCaseInsensitiveContains("color light") || $0.localizedCaseInsensitiveContains("color and color temperature") } ?? (state["hue"] != nil || state["xy"] != nil)
            return HueLight(id: "\(bridge.id):\(number)", bridgeID: bridge.id, number: number, name: light["name"] as? String ?? L10n.value("Lampe \(number)"), reachable: state["reachable"] as? Bool ?? true, color: supportsColor, currentHue: (state["hue"] as? Double).map { $0 / 65535 * 360 } ?? (state["ct"] != nil ? 30 : nil), currentSaturation: (state["sat"] as? Double).map { $0 / 254 * 100 } ?? (state["ct"] != nil ? 35 : nil))
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
    public func rooms(_ bridge: HueBridge) async throws -> [HueRoom] {
        let key = try key(bridge)
        guard let obj = try await json(bridge, path: "/\(key)/groups") as? [String: [String: Any]] else { throw AppFailure(L10n.value("Hue-Räume konnten nicht gelesen werden.")) }
        return Self.decodeRooms(obj, bridge: bridge)
    }
    static func decodeRooms(_ obj: [String: [String: Any]], bridge: HueBridge) -> [HueRoom] {
        obj.compactMap { number, group in
            guard let type = group["type"] as? String, ["Room", "Zone"].contains(type), let numbers = group["lights"] as? [String] else { return nil }
            return HueRoom(id: "\(bridge.id):group:\(number)", bridgeID: bridge.id, name: group["name"] as? String ?? L10n.value("Raum \(number)"), lightIDs: Set(numbers.map { "\(bridge.id):\($0)" }), isZone: type == "Zone")
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
    /// Hue's one-shot identify alert does not overwrite on/off, brightness or color.
    public func identify(_ light: HueLight, bridge: HueBridge) async throws {
        guard light.bridgeID == bridge.id else { throw AppFailure(L10n.value("Lampe und Bridge passen nicht zusammen.")) }
        guard light.reachable else { throw AppFailure(L10n.value("\(light.name) ist nicht erreichbar.")) }
        let key = try key(bridge)
        _ = try await json(bridge, path: "/\(key)/lights/\(light.number)/state", method: "PUT", body: ["alert": "select"])
    }
    public func snapshot(_ light: HueLight, bridge: HueBridge) async throws -> HueSnapshot {
        let key = try key(bridge); guard let obj = try await json(bridge, path: "/\(key)/lights/\(light.number)") as? [String: Any], let state = obj["state"] as? [String: Any], state["reachable"] as? Bool != false else { throw AppFailure(L10n.value("\(light.name) ist nicht erreichbar.")) }
        var restored: [String: Any] = [:]
        for field in ["on", "bri"] { restored[field] = state[field] }
        if let effect = state["effect"] as? String, effect != "none" { restored["effect"] = effect }
        switch state["colormode"] as? String { case "xy": restored["xy"] = state["xy"]; case "ct": restored["ct"] = state["ct"]; case "hs": restored["hue"] = state["hue"]; restored["sat"] = state["sat"]; default: break }
        restored["transitiontime"] = 0
        return HueSnapshot(light: light, bridge: bridge, key: key, state: restored)
    }
    public func set(_ light: HueLight, bridge: HueBridge, on: Bool, brightness: Double = 60, hue: Double? = nil, saturation: Double = 100, transition: Double = 0) async throws {
        let key = try key(bridge); var body: [String: Any] = ["on": on]
        if on { body["transitiontime"] = Int(max(0, min(60, transition)) * 10) }
        if on { body["bri"] = max(1, min(254, Int(brightness / 100 * 254))) }
        if on, let hue, light.color { body["hue"] = max(0, min(65535, Int(hue / 360 * 65535))); body["sat"] = max(0, min(254, Int(saturation / 100 * 254))) }
        _ = try await json(bridge, path: "/\(key)/lights/\(light.number)/state", method: "PUT", body: body)
    }
    public func restore(_ snapshot: HueSnapshot) async throws {
        let path = "/\(snapshot.key)/lights/\(snapshot.light.number)/state"
        // Hue rejects brightness/color writes in the same request as on:false.
        // Restore the remembered values while on, then switch off separately.
        var state = snapshot.state
        let wasOff = state["on"] as? Bool == false
        if wasOff { state["on"] = true }
        do {
            _ = try await json(snapshot.bridge, path: path, method: "PUT", body: state)
        } catch {
            if wasOff { _ = try? await json(snapshot.bridge, path: path, method: "PUT", body: ["on": false]) }
            throw error
        }
        if wasOff { _ = try await json(snapshot.bridge, path: path, method: "PUT", body: ["on": false]) }
    }
}
