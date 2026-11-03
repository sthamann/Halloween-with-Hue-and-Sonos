import SwiftUI
import HalloweenCore

struct BridgeLightPicker: View {
    @ObservedObject var store: AppStore
    let bridge: HueBridge
    @Binding var selection: Set<String>
    var available: [HueLight] { store.lights.filter { $0.bridgeID == bridge.id && $0.reachable } }
    var body: some View {
        DisclosureGroup {
            HStack {
                Button(L10n.value("Alle dieser Bridge")) { selection.formUnion(available.map(\.id)) }
                Button(L10n.value("Keine")) { selection.subtract(available.map(\.id)) }
            }.font(.caption).padding(.top, 8)
            ForEach(store.hueRooms.filter { $0.bridgeID == bridge.id }) { room in
                let ids = room.lightIDs.intersection(Set(available.map(\.id)))
                Toggle(isOn: Binding(get: { !ids.isEmpty && ids.isSubset(of: selection) }, set: { if $0 { selection.formUnion(ids) } else { selection.subtract(ids) } })) {
                    Label("\(room.name) · \(ids.intersection(selection).count)/\(ids.count)", systemImage: room.isZone ? "square.dashed" : "door.left.hand.open")
                }.toggleStyle(.checkboxCompat).disabled(ids.isEmpty)
            }
            Divider()
            ForEach(store.lights.filter { $0.bridgeID == bridge.id }) { light in
                HStack {
                Toggle(isOn: Binding(get: { selection.contains(light.id) }, set: { if $0 { selection.insert(light.id) } else { selection.remove(light.id) } })) {
                    Label(light.name + (light.reachable ? "" : " · offline"), systemImage: light.color ? "lightbulb.fill" : "lightbulb")
                }.toggleStyle(.checkboxCompat).disabled(!light.reachable)
                Spacer()
                HueLightTestButton(store: store, light: light)
                }
            }
            if available.isEmpty { Text(store.bridgeStatus[bridge.id] ?? L10n.value("Bridge zuerst unter Geräte koppeln.")).font(.caption).foregroundStyle(.secondary) }
        } label: {
            VStack(alignment: .leading) {
                Text(bridge.name).font(.headline)
                Text("\(bridge.ip) · \(available.filter { selection.contains($0.id) }.count) ausgewählt").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}
