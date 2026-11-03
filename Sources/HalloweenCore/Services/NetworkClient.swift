import Foundation
import Darwin

public enum LocalNetwork {
    public static func addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&pointer) == 0 else { return [] }; defer { freeifaddrs(pointer) }
        var list: [(String, String)] = []; var current = pointer
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: item.pointee.ifa_name); guard name.hasPrefix("en"), item.pointee.ifa_flags & UInt32(IFF_UP) != 0, item.pointee.ifa_flags & UInt32(IFF_RUNNING) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host); if !ip.hasPrefix("169.254.") { list.append((name, ip)) }
            }
        }
        return list.sorted { $0.0 < $1.0 }.map(\.1)
    }
    public static var hostAddress: String? { addresses().first }
    /// Ask the OS which local address reaches this speaker, without sending an audio packet.
    public static func routedAddress(to remote: String) -> String? {
        var destination = sockaddr_in(); destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET); destination.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, remote, &destination.sin_addr) == 1 else { return nil }
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0); guard descriptor >= 0 else { return nil }; defer { close(descriptor) }
        let connected = withUnsafePointer(to: &destination) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { return nil }
        var local = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        guard result == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(cString: buffer)
    }
    public static func subnetHosts(address: String, mask: String) -> [String] {
        func number(_ ip: String) -> UInt32? {
            let parts = ip.split(separator: ".").compactMap { UInt32($0) }
            guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
            return parts.reduce(0) { ($0 << 8) | $1 }
        }
        guard let ip = number(address), let mask = number(mask) else { return [] }
        let inverse = ~mask
        guard inverse & (inverse &+ 1) == 0, inverse > 1 else { return [] }
        // Bound discovery to avoid huge scans on enterprise LANs. Manual Hue-IP remains available.
        let scanMask: UInt32 = inverse > 4095 ? 0xffffff00 : mask
        let network = ip & scanMask; let broadcast = network | ~scanMask
        return ((network + 1)..<broadcast).filter { $0 != ip }.map { value in
            [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
        }
    }
    public static func hosts() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return [] }; defer { freeifaddrs(pointer) }
        var hosts: Set<String> = []; var current = pointer
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name).hasPrefix("en"), item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  item.pointee.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  let address = item.pointee.ifa_addr, let mask = item.pointee.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            func numeric(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                return String(cString: buffer)
            }
            if let ip = numeric(address), !ip.hasPrefix("169.254."), let mask = numeric(mask) { hosts.formUnion(subnetHosts(address: ip, mask: mask)) }
        }
        return hosts.sorted()
    }

}
struct NetworkClient: @unchecked Sendable {
    let session: URLSession
    init(session: URLSession) { self.session = session }
    init(timeout: Double = 5) {
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout + 2; config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }
    func request(_ url: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], timeout: Double? = nil) async throws -> Data {
        guard let url = URL(string: url) else { throw AppFailure(L10n.value("Ungültige Geräteadresse.")) }
        var req = URLRequest(url: url); req.httpMethod = method; req.httpBody = body
        if let timeout { req.timeoutInterval = timeout }
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: req)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw AppFailure(L10n.value("\(url.host ?? "Gerät") antwortet mit einem HTTP-Fehler.")) }
        return data
    }
}
