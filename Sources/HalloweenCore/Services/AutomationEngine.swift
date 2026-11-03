import Foundation
import Combine

@MainActor public final class AutomationEngine: ObservableObject {
    @Published public private(set) var active = false
    @Published public private(set) var status = L10n.value("Automatik ausgeschaltet")
    @Published public private(set) var bridgeStatus: [String: String] = [:]
    @Published public private(set) var log: [String] = []
    @Published public private(set) var lastEvents: [String: Date] = [:]
    private var clock: Task<Void, Never>?
    private var monitors: [Task<Void, Never>] = []
    private var gate = TriggerGate()
    private var generation = UUID()
    public init() {}
    public func stop() {
        generation = UUID(); clock?.cancel(); clock = nil; monitors.forEach { $0.cancel() }; monitors = []
        active = false; status = L10n.value("Automatik ausgeschaltet"); bridgeStatus = [:]
    }
    public func start(rules: @escaping () -> [AutomationRule], bridges: [HueBridge], fire: @escaping (AutomationRule) -> Bool) {
        stop(); gate = TriggerGate(); active = true; status = L10n.value("Automatik aktiv · App geöffnet lassen")
        let epoch = generation
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == epoch else { return }
                for rule in self.gate.scheduled(rules(), now: Date()) { self.dispatch(rule, fire: fire) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        for bridge in bridges where CredentialStore.read(bridge.id) != nil {
            monitors.append(Task { [weak self] in
                var delay = 1.0
                while !Task.isCancelled {
                    guard let self, self.generation == epoch else { return }
                    do {
                        let client = HueEventClient(bridge: bridge)
                        let snapshot = try await client.inventory()
                        try Task.checkCancellation(); guard self.generation == epoch else { return }
                        self.gate.prime(snapshot.baseline)
                        self.bridgeStatus[bridge.id] = L10n.value("Verbunden")
                        delay = 1
                        try await client.listen { event in
                            await MainActor.run { [weak self] in
                                guard let self, self.generation == epoch else { return }
                                self.lastEvents[event.sourceID] = Date()
                                for rule in self.gate.receive(event, rules: rules(), now: Date()) { self.dispatch(rule, fire: fire) }
                            }
                        }
                    } catch is CancellationError { return }
                    catch { guard self.generation == epoch else { return }; self.bridgeStatus[bridge.id] = L10n.value("Nicht erreichbar: \(error.localizedDescription)") }
                    try? await Task.sleep(for: .seconds(delay)); delay = min(30, delay * 2)
                }
            })
        }
    }
    private func dispatch(_ rule: AutomationRule, fire: (AutomationRule) -> Bool) {
        let result = fire(rule) ? L10n.value("Gestartet") : L10n.value("Widerspruch · Ablauf fehlt oder Geräte sind belegt")
        log.insert("\(Date().formatted(date: .omitted, time: .standard)) · \(rule.name) · \(result)", at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }; status = result
    }
}
