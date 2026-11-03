import Foundation
import Combine

/// Read-only event diagnostics. This observer never invokes a scene or changes a light.
@MainActor public final class HueInputMonitor: ObservableObject {
    public struct State: Sendable {
        public let event: HueInputEvent
        public let received: Date
        public let live: Bool
    }
    @Published public private(set) var states: [String: State] = [:]
    @Published public private(set) var statuses: [String: String] = [:]
    @Published public private(set) var receivedCount = 0
    private var tasks: [Task<Void, Never>] = []
    private var generation = UUID()
    public init() {}
    public func stop() { generation = UUID(); tasks.forEach { $0.cancel() }; tasks = [] }
    public func start(_ bridges: [HueBridge]) {
        stop(); states = [:]; statuses = Dictionary(uniqueKeysWithValues: bridges.map { ($0.id, CredentialStore.read($0.id) == nil ? L10n.value("Nicht gekoppelt") : L10n.value("Verbindung wird hergestellt …")) }); receivedCount = 0
        let epoch = generation
        for bridge in bridges where CredentialStore.read(bridge.id) != nil {
            tasks.append(Task { [weak self] in
                var delay = 1.0
                while !Task.isCancelled {
                    guard let self, self.generation == epoch else { return }
                    do {
                        let client = HueEventClient(bridge: bridge)
                        let inventory = try await client.inventory()
                        guard self.generation == epoch else { return }
                        for event in inventory.baseline { self.states[event.sourceID] = State(event: event, received: Date(), live: false) }
                        self.statuses[bridge.id] = L10n.value("Inventar gelesen · verbinde Live-Ereignisse …")
                        delay = 1
                        try await client.listen(connected: { [weak self] in
                            await self?.connected(bridge.id, epoch: epoch)
                        }, deliver: { [weak self] event in
                            await self?.record(event, epoch: epoch)
                        })
                    } catch is CancellationError { return }
                    catch { guard self.generation == epoch else { return }; self.statuses[bridge.id] = error.localizedDescription }
                    try? await Task.sleep(for: .seconds(delay)); delay = min(30, delay * 2)
                }
            })
        }
    }
    private func connected(_ bridgeID: String, epoch: UUID) {
        guard generation == epoch else { return }
        statuses[bridgeID] = L10n.value("Live verbunden · nur Beobachtung")
    }
    private func record(_ event: HueInputEvent, epoch: UUID) {
        guard generation == epoch else { return }
        states[event.sourceID] = State(event: event, received: Date(), live: true)
        receivedCount += 1
    }
    deinit { tasks.forEach { $0.cancel() } }
}
