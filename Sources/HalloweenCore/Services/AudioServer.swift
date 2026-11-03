import Foundation
import Network

public struct HTTPAudioResponse: Sendable {
    public let status: Int; public let headers: [String: String]; public let body: Data
    public static func make(data: Data, mime: String, method: String, range: String?) -> HTTPAudioResponse {
        var headers = ["Content-Type": mime, "Accept-Ranges": "bytes", "Connection": "close"]
        guard method == "GET" || method == "HEAD" else { return HTTPAudioResponse(status: 405, headers: ["Allow": "GET, HEAD", "Content-Length": "0"], body: Data()) }
        if let range {
            guard range.hasPrefix("bytes="), !range.contains(",") else { return HTTPAudioResponse(status: 416, headers: ["Content-Range": "bytes */\(data.count)", "Content-Length": "0"], body: Data()) }
            let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, !data.isEmpty else { return HTTPAudioResponse(status: 416, headers: ["Content-Range": "bytes */\(data.count)", "Content-Length": "0"], body: Data()) }
            let start: Int; let end: Int
            if parts[0].isEmpty, let suffix = Int(parts[1]), suffix > 0 { start = max(0, data.count - suffix); end = data.count - 1 }
            else if let lower = Int(parts[0]), lower >= 0, let upper = parts[1].isEmpty ? data.count - 1 : Int(parts[1]) { start = lower; end = min(upper, data.count - 1) }
            else { return HTTPAudioResponse(status: 416, headers: ["Content-Range": "bytes */\(data.count)", "Content-Length": "0"], body: Data()) }
            guard start < data.count, end >= start else { return HTTPAudioResponse(status: 416, headers: ["Content-Range": "bytes */\(data.count)", "Content-Length": "0"], body: Data()) }
            let slice = data.subdata(in: start..<(end + 1)); headers["Content-Range"] = "bytes \(start)-\(end)/\(data.count)"; headers["Content-Length"] = String(slice.count)
            return HTTPAudioResponse(status: 206, headers: headers, body: method == "HEAD" ? Data() : slice)
        }
        headers["Content-Length"] = String(data.count)
        return HTTPAudioResponse(status: 200, headers: headers, body: method == "HEAD" ? Data() : data)
    }
}
public final class AudioServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Halloween.audio-server")
    private var listener: NWListener?; private var files: [String: URL] = [:]; private var requests: [String: Int] = [:]; private var connections: [NWConnection] = []
    private var host = ""; private var port: UInt16 = 0
    private var startup: CheckedContinuation<Void, Error>?
    private var clients: [String: [String: Int]] = [:]
    public init() {}
    public func start() async throws {
        guard let host = LocalNetwork.hostAddress else { throw AppFailure(L10n.value("Kein lokales WLAN oder Ethernet gefunden.")) }; self.host = host
        let listener = try NWListener(using: .tcp, on: .any); self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in guard let self else { connection.cancel(); return }; self.connections.append(connection); connection.start(queue: self.queue); self.receive(connection, data: Data()) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.sync { startup = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, let pending = self.startup else { return }
                switch state {
                case .ready: self.startup = nil; self.port = listener.port?.rawValue ?? 0; pending.resume()
                case .failed(let error): self.startup = nil; pending.resume(throwing: error)
                case .cancelled: self.startup = nil; pending.resume(throwing: AppFailure(L10n.value("Audio-Server wurde beendet.")))
                default: break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, let pending = self.startup else { return }
                self.startup = nil; listener.cancel(); pending.resume(throwing: AppFailure(L10n.value("Audio-Server konnte nicht gestartet werden.")))
            }
        }
    }
    public func serve(_ file: URL) -> URL {
        let token = UUID().uuidString + "." + file.pathExtension
        queue.sync { files["/" + token] = file }
        return URL(string: "http://\(host):\(port)/\(token)")!
    }
    public func reachableURL(_ url: URL, for ip: String) -> URL {
        guard let address = LocalNetwork.routedAddress(to: ip), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = address; return components.url ?? url
    }
    public func requestCount(_ url: URL) -> Int { queue.sync { requests[url.path] ?? 0 } }
    public func requestCount(_ url: URL, from ip: String) -> Int { queue.sync { clients[url.path]?[ip] ?? 0 } }
    public func stop() { queue.sync { listener?.cancel(); listener = nil; connections.forEach { $0.cancel() }; connections.removeAll(); files.removeAll(); requests.removeAll(); clients.removeAll() } }
    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = data; if let bytes { accumulated.append(bytes) }
            guard accumulated.count <= 32_768, error == nil else { connection.cancel(); return }
            guard let request = String(data: accumulated, encoding: .utf8), request.contains("\r\n\r\n") else { if complete { connection.cancel() } else { self.receive(connection, data: accumulated) }; return }
            let lines = request.components(separatedBy: "\r\n"); let first = lines[0].split(separator: " ")
            guard first.count >= 2, let file = self.files[String(first[1])], let payload = try? Data(contentsOf: file) else { self.send(connection, response: HTTPAudioResponse(status: 404, headers: ["Content-Length": "0"], body: Data())); return }
            let range = lines.first(where: { $0.lowercased().hasPrefix("range:") })?.dropFirst(6).trimmingCharacters(in: .whitespaces)
            let mime = file.pathExtension.lowercased() == "mp3" ? "audio/mpeg" : file.pathExtension.lowercased() == "wav" ? "audio/wav" : "audio/x-caf"
            let response = HTTPAudioResponse.make(data: payload, mime: mime, method: String(first[0]), range: range)
            if first[0] == "GET", [200, 206].contains(response.status) {
                let path = String(first[1]); self.requests[path, default: 0] += 1
                if case .hostPort(let host, _) = connection.endpoint { self.clients[path, default: [:]][String(describing: host), default: 0] += 1 }
            }
            self.send(connection, response: response)
        }
    }
    private func send(_ connection: NWConnection, response: HTTPAudioResponse) {
        let reason = [200: "OK", 206: "Partial Content", 404: "Not Found", 405: "Method Not Allowed", 416: "Range Not Satisfiable"][response.status] ?? "Error"
        let head = "HTTP/1.1 \(response.status) \(reason)\r\n" + response.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        var data = Data(head.utf8); data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in connection.cancel(); self?.connections.removeAll { $0 === connection } })
    }
}
