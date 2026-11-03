import SwiftUI
import HalloweenCore

struct HueInputsView: View {
    @ObservedObject var store: AppStore
    @StateObject private var monitor = HueInputMonitor()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.value("Sensoren live prüfen")).font(.title2.bold())
                    Text(L10n.value("Bewege dich im eingerichteten Bereich oder drücke einen Hue-Taster. Hier siehst du die echten Bridge-Ereignisse. Dieser Test startet keine Szene.")).foregroundStyle(.secondary)
                    Text(L10n.value("\(monitor.receivedCount) Live-Ereignisse empfangen")).font(.callout).foregroundStyle(.orange)
                    ForEach(store.bridges) { bridge in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(bridge.name).font(.headline)
                            Text(monitor.statuses[bridge.id] ?? L10n.value("Verbindung wird hergestellt …")).font(.caption).foregroundStyle(.secondary)
                            MotionAwareStatus(store: store, bridge: bridge)
                            ForEach(store.hueInputs.filter { $0.bridgeID == bridge.id }) { input in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) { Text(input.name); Text(L10n.hueResource(input.type)).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    if let state = monitor.states[input.id] {
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(L10n.hueEvent(state.event.event)).foregroundStyle(state.live ? Color.orange : Color.secondary)
                                            Text((state.live ? L10n.value("Live") : L10n.value("Gelesener Zustand")) + " · " + state.received.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    } else { Text(L10n.value("Noch kein Zustand")).font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 6)
                                Divider()
                            }
                        }.hauntedCard()
                    }
                }.padding(24)
            }.navigationTitle(L10n.value("Hue-Eingänge"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.value("Fertig")) { dismiss() } } }
        }
        .task { await store.refreshInputs(); monitor.start(store.bridges) }
        .onDisappear { monitor.stop() }
        #if os(macOS)
        .frame(width: 760, height: 720)
        #endif
    }
}
struct MotionAwareStatus: View {
    @ObservedObject var store: AppStore
    let bridge: HueBridge
    var body: some View {
        if let inventory = store.hueInventory[bridge.id], inventory.motionCandidateCount > 0 || inventory.motionAreaCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label(inventory.motionAreaCount > 0 ? L10n.value("MotionAware · \(inventory.motionAreaCount) Bereiche eingerichtet") : L10n.value("MotionAware · noch kein Bereich eingerichtet"), systemImage: "sensor.fill").font(.callout).foregroundStyle(inventory.motionAreaCount > 0 ? Color.green : Color.orange)
                if inventory.motionAreaCount == 0 {
                    Text(L10n.value("\(inventory.motionCandidateCount) geeignete Geräte gemeldet. Richte zuerst in der Hue-App einen MotionAware-Bereich ein. Danach hier die Eingänge aktualisieren.")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
