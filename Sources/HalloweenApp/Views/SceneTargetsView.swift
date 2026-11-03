import SwiftUI
import HalloweenCore

struct SceneTargetsView: View {
    @ObservedObject var store: AppStore
    @Binding var rooms: Set<String>
    @Binding var lights: Set<String>
    @State private var choosing: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.value("1 · Wo spielt deine Szene?")).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { roomButton; lightButton }
                VStack(spacing: 12) { roomButton; lightButton }
            }
            Text(L10n.value("Diese Auswahl gilt für alle Clips. Einzelne Clips können eigene Boxen oder Lampen verwenden.")).font(.caption).foregroundStyle(.secondary)
        }.hauntedCard()
        .sheet(isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } })) {
            TargetSelectionView(store: store, rooms: $rooms, lights: $lights, mode: choosing ?? "sonos")
        }
    }
    var roomButton: some View { targetButton(L10n.value("Boxen auswählen"), subtitle: rooms.isEmpty ? L10n.value("Noch kein Sonos-Raum") : store.rooms.filter { rooms.contains($0.id) }.map(\.name).joined(separator: ", "), count: rooms.count, symbol: "hifispeaker.fill") { choosing = "sonos" } }
    var lightButton: some View { targetButton(L10n.value("Lichter auswählen"), subtitle: lights.isEmpty ? L10n.value("Noch keine Lampen") : L10n.value("\(lights.count) Lampen aus \(Set(store.lights.filter { lights.contains($0.id) }.map(\.bridgeID)).count) Bridges"), count: lights.count, symbol: "lightbulb.fill") { choosing = "hue" } }
    func targetButton(_ title: String, subtitle: String, count: Int, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Image(systemName: symbol).font(.title2).foregroundStyle(.orange); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Image(systemName: count == 0 ? "plus.circle.fill" : "checkmark.circle.fill").foregroundStyle(count == 0 ? .orange : .green) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
    }
}

struct TargetSelectionView: View {
    @ObservedObject var store: AppStore
    @Binding var rooms: Set<String>
    @Binding var lights: Set<String>
    let mode: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(L10n.value("Raum oder Lampe suchen"), text: $query).textFieldStyle(.roundedBorder)
                    if mode == "sonos" {
                        Text(L10n.value("Sonos-Räume sind deine Abspielziele. Sub und Surrounds spielen mit ihrem Raum.")).font(.callout).foregroundStyle(.secondary)
                        if store.rooms.isEmpty { Text(L10n.value("Noch keine Räume gefunden. Unter Geräte das Netzwerk durchsuchen.")) }
                        ForEach(store.rooms.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { room in
                            Toggle(isOn: selection(room.id, set: $rooms)) { VStack(alignment: .leading) { Text(room.name).font(.headline); Text(room.model).font(.caption).foregroundStyle(.secondary) } }.toggleStyle(.checkboxCompat).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        if store.lights.isEmpty { Text(L10n.value("Unter Geräte die Hue-Bridge koppeln. Dann erscheinen hier deine Lampen.")) }
                        ForEach(store.bridges) { bridge in
                            TargetBridgeLights(store: store, bridge: bridge, query: query, selected: $lights)
                        }
                    }
                }.padding(22)
            }.navigationTitle(mode == "sonos" ? L10n.value("Boxen auswählen") : L10n.value("Lichter auswählen"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Auswahl leeren")) { if mode == "sonos" { rooms.removeAll() } else { lights.removeAll() } } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.value("Fertig · \(mode == "sonos" ? rooms.count : lights.count) ausgewählt")) { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(width: 650, height: 650)
        #endif
    }
    func selection(_ id: String, set: Binding<Set<String>>) -> Binding<Bool> { Binding(get: { set.wrappedValue.contains(id) }, set: { if $0 { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } }) }
}
private struct TargetBridgeLights: View {
    @ObservedObject var store: AppStore
    let bridge: HueBridge
    let query: String
    @Binding var selected: Set<String>
    @State private var showAll = false
    var matchingRoomLightIDs: Set<String> { store.hueRooms.filter { $0.bridgeID == bridge.id && $0.name.localizedCaseInsensitiveContains(query) }.reduce(into: Set<String>()) { $0.formUnion($1.lightIDs) } }
    var available: [HueLight] { store.lights.filter { $0.bridgeID == bridge.id && $0.reachable } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(bridge.name).font(.headline); Spacer(); Text(L10n.value("\(available.filter { selected.contains($0.id) }.count)/\(available.count) gewählt")).font(.caption).foregroundStyle(.orange) }
            if available.isEmpty { Text(store.bridgeStatus[bridge.id] ?? L10n.value("Bridge zuerst unter Geräte koppeln.")).font(.callout).foregroundStyle(.secondary) }
            else {
                HStack { Button(L10n.value("Alle dieser Bridge")) { selected.formUnion(available.map(\.id)) }; Button(L10n.value("Keine")) { selected.subtract(available.map(\.id)) } }.font(.caption)
                ForEach(store.hueRooms.filter { $0.bridgeID == bridge.id && !$0.isZone && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { room in
                        let ids = room.lightIDs.intersection(Set(available.map(\.id)))
                        HStack {
                            Toggle(isOn: Binding(get: { !ids.isEmpty && ids.isSubset(of: selected) }, set: { if $0 { selected.formUnion(ids) } else { selected.subtract(ids) } })) { Label(room.name, systemImage: "door.left.hand.open") }.toggleStyle(.checkboxCompat)
                            Text("\(ids.intersection(selected).count)/\(ids.count)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                DisclosureGroup(L10n.value("Einzelne Lampen wählen"), isExpanded: Binding(get: { showAll || !query.isEmpty }, set: { showAll = $0 })) {
                    ForEach(store.lights.filter { $0.bridgeID == bridge.id && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || matchingRoomLightIDs.contains($0.id)) }) { light in
                        HStack {
                            Toggle(isOn: Binding(get: { selected.contains(light.id) }, set: { if $0 { selected.insert(light.id) } else { selected.remove(light.id) } })) { Text(light.name + (light.reachable ? "" : " · offline")) }.toggleStyle(.checkboxCompat).disabled(!light.reachable)
                            Spacer()
                            HueLightTestButton(store: store, light: light)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.hauntedCard()
    }
}
