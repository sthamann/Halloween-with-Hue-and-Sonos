import Foundation

public struct SonosSnapshot: Sendable {
    public let speaker: Speaker
    let volume: String; let mute: String; let mode: String; let uri: String; let metadata: String; let track: String; let position: String; let state: String
}
public struct SonosClient: Sendable {
    private let network = NetworkClient()
    public init() {}
    func soap(_ ip: String, _ service: String, _ action: String, _ args: [String: String] = [:]) async throws -> XMLNode {
        let values = args.sorted { $0.key < $1.key }.map { "<\($0.key)>\(xmlEscape($0.value))</\($0.key)>" }.joined()
        let urn = "urn:schemas-upnp-org:service:\(service):1"
        let body = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:\(action) xmlns:u=\"\(urn)\">\(values)</u:\(action)></s:Body></s:Envelope>"
        let prefix = service == "ZoneGroupTopology" ? "" : "MediaRenderer/"
        let data = try await network.request("http://\(ip):1400/\(prefix)\(service)/Control", method: "POST", body: Data(body.utf8), headers: ["Content-Type": "text/xml; charset=utf-8", "SOAPACTION": "\"\(urn)#\(action)\""])
        let root = try XMLTree.parse(data)
        if let fault = root.all("Fault").first { throw AppFailure("Sonos: \(fault.value("faultstring")) \(fault.value("errorCode"))") }
        return root
    }
    public func probe(_ ip: String) async -> Speaker? {
        guard let data = try? await network.request("http://\(ip):1400/xml/device_description.xml", timeout: 1.1), let root = try? XMLTree.parse(data), root.value("manufacturer").lowercased().contains("sonos") else { return nil }
        return Speaker(id: root.value("UDN").replacingOccurrences(of: "uuid:", with: ""), name: root.value("roomName"), model: root.value("modelName"), ip: ip)
    }
    public func topology(_ speakers: [Speaker]) async throws -> [Speaker] {
        guard let first = speakers.first else { return [] }
        let response = try await soap(first.ip, "ZoneGroupTopology", "GetZoneGroupState")
        let root = try XMLTree.parse(Data(response.value("ZoneGroupState").utf8)); var devices = speakers
        for group in root.all("ZoneGroup") {
            let coordinator = group.attributes["Coordinator"]
            for member in group.children where member.name == "ZoneGroupMember" {
                let id = member.attributes["UUID"] ?? ""
                if let i = devices.firstIndex(where: { $0.id == id }) { devices[i].groupID = coordinator }
                for satellite in member.all("Satellite") {
                    if let i = devices.firstIndex(where: { $0.id == satellite.attributes["UUID"] }) { devices[i].parentID = id; devices[i].groupID = coordinator }
                }
            }
        }
        return devices.sorted { ($0.name, $0.model, $0.id) < ($1.name, $1.model, $1.id) }
    }
    public func validatedTargets(_ selected: Set<String>, known: [Speaker]) async throws -> [Speaker] {
        let latest = try await topology(known)
        let rooms = latest.filter { !$0.isSatellite && selected.contains($0.id) }
        guard rooms.count == selected.count, !rooms.isEmpty else { throw AppFailure(L10n.value("Bitte erreichbare Sonos-Räume auswählen und bei Bedarf erneut suchen.")) }
        for room in rooms {
            let members = latest.filter { !$0.isSatellite && $0.groupID == room.groupID }
            guard members.count <= 1 else { throw AppFailure(L10n.value("\(room.name) ist mit anderen Räumen gruppiert. Trenne die Raumgruppe zuerst in Sonos. Heimkino-Satelliten können verbunden bleiben.")) }
        }
        let coordinatorIDs = Set(rooms.map { $0.groupID ?? $0.id })
        return latest.filter { coordinatorIDs.contains($0.id) && !$0.isSatellite }
    }
    public func snapshot(_ room: Speaker) async throws -> SonosSnapshot {
        let volume = try await soap(room.ip, "RenderingControl", "GetVolume", ["InstanceID": "0", "Channel": "Master"])
        let mute = try await soap(room.ip, "RenderingControl", "GetMute", ["InstanceID": "0", "Channel": "Master"])
        let settings = try await soap(room.ip, "AVTransport", "GetTransportSettings", ["InstanceID": "0"])
        let media = try await soap(room.ip, "AVTransport", "GetMediaInfo", ["InstanceID": "0"])
        let position = try await soap(room.ip, "AVTransport", "GetPositionInfo", ["InstanceID": "0"])
        let state = try await soap(room.ip, "AVTransport", "GetTransportInfo", ["InstanceID": "0"])
        return SonosSnapshot(speaker: room, volume: volume.value("CurrentVolume"), mute: mute.value("CurrentMute"), mode: settings.value("PlayMode"), uri: media.value("CurrentURI"), metadata: media.value("CurrentURIMetaData"), track: position.value("Track"), position: position.value("RelTime"), state: state.value("CurrentTransportState"))
    }
    public func play(_ room: Speaker, url: URL, volume: Int) async throws {
        _ = try await soap(room.ip, "RenderingControl", "SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": String(min(100, max(0, volume)))])
        _ = try await soap(room.ip, "RenderingControl", "SetMute", ["InstanceID": "0", "Channel": "Master", "DesiredMute": "0"])
        _ = try await soap(room.ip, "AVTransport", "SetPlayMode", ["InstanceID": "0", "NewPlayMode": "NORMAL"])
        _ = try await soap(room.ip, "AVTransport", "SetAVTransportURI", ["InstanceID": "0", "CurrentURI": url.absoluteString, "CurrentURIMetaData": ""])
        _ = try await soap(room.ip, "AVTransport", "Play", ["InstanceID": "0", "Speed": "1"])
    }
    public func state(_ room: Speaker) async throws -> String { try await soap(room.ip, "AVTransport", "GetTransportInfo", ["InstanceID": "0"]).value("CurrentTransportState") }
    public func pause(_ room: Speaker) async throws { _ = try await soap(room.ip, "AVTransport", "Pause", ["InstanceID": "0"]) }
    public func resume(_ room: Speaker) async throws { _ = try await soap(room.ip, "AVTransport", "Play", ["InstanceID": "0", "Speed": "1"]) }
    public func restore(_ snapshot: SonosSnapshot) async throws {
        let ip = snapshot.speaker.ip; var failures: [String] = []
        func attempt(_ svc: String, _ action: String, _ args: [String: String]) async { do { _ = try await soap(ip, svc, action, args) } catch { failures.append(error.localizedDescription) } }
        await attempt("AVTransport", "Stop", ["InstanceID": "0"])
        if !snapshot.uri.isEmpty {
            await attempt("AVTransport", "SetAVTransportURI", ["InstanceID": "0", "CurrentURI": snapshot.uri, "CurrentURIMetaData": snapshot.metadata])
            if snapshot.uri.hasPrefix("x-rincon-queue:"), Int(snapshot.track) ?? 0 > 0 { await attempt("AVTransport", "Seek", ["InstanceID": "0", "Unit": "TRACK_NR", "Target": snapshot.track]) }
            if snapshot.position.contains(":"), snapshot.position != "0:00:00" { await attempt("AVTransport", "Seek", ["InstanceID": "0", "Unit": "REL_TIME", "Target": snapshot.position]) }
            if snapshot.state == "PLAYING" { await attempt("AVTransport", "Play", ["InstanceID": "0", "Speed": "1"]) }
        }
        await attempt("AVTransport", "SetPlayMode", ["InstanceID": "0", "NewPlayMode": snapshot.mode])
        await attempt("RenderingControl", "SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": snapshot.volume])
        await attempt("RenderingControl", "SetMute", ["InstanceID": "0", "Channel": "Master", "DesiredMute": snapshot.mute])
        if !failures.isEmpty { throw AppFailure(L10n.value("\(snapshot.speaker.name): Wiederherstellung unvollständig – \(failures.joined(separator: "; "))")) }
    }
}
