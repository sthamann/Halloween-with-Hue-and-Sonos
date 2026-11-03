import SwiftUI
import HalloweenCore

struct DevicesView: View {
    @ObservedObject var store: AppStore
    @State private var query = ""
    @State private var tab = 0
    @State private var pairing: HueBridge?
    @State private var manual = false
    @State private var bridgeIP = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    SectionHeading(eyebrow: L10n.value("Dein verbundenes Haus"), title: L10n.value("Geräte & Räume"), subtitle: L10n.value("Einmal verbinden. In jeder Szene verwenden."))
                    Button { Task { await store.scan() } } label: { Label(store.scanning ? L10n.value("Suche läuft …") : L10n.value("Geräte suchen"), systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(store.scanning || store.playback.running)
                }
                DeviceSummaryCards(store: store)
                if store.scanning { ProgressView(L10n.value("Sonos und Hue werden gesucht …")) }
                HStack {
                    Picker(L10n.value("Geräte anzeigen"), selection: $tab) { Text("Sonos").tag(0); Text("Philips Hue").tag(1) }.pickerStyle(.segmented).frame(maxWidth: 320)
                    Spacer()
                    Button { manual = true } label: { Label(L10n.value("Bridge hinzufügen"), systemImage: "plus") }.buttonStyle(.bordered)
                }
                TextField(L10n.value("Raum, Gerät oder Bridge suchen"), text: $query).textFieldStyle(.roundedBorder)
                if tab == 0 {
                    if store.rooms.isEmpty { ContentUnavailableView(L10n.value("Noch keine Sonos-Räume"), systemImage: "hifispeaker.fill", description: Text(L10n.value("Geräte suchen und den lokalen Netzwerkzugriff erlauben."))) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 14) {
                        ForEach(store.rooms.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.model.localizedCaseInsensitiveContains(query) }) { room in SonosDeviceCard(store: store, room: room) }
                    }
                } else {
                    Text(L10n.value("Jede Bridge separat verbinden. Räume und Lampen erscheinen nach dem Koppeln.")).font(.callout).foregroundStyle(.secondary)
                    ForEach(store.bridges.filter { bridge in query.isEmpty || bridge.name.localizedCaseInsensitiveContains(query) || store.hueRooms.contains { $0.bridgeID == bridge.id && $0.name.localizedCaseInsensitiveContains(query) } || store.lights.contains { $0.bridgeID == bridge.id && $0.name.localizedCaseInsensitiveContains(query) } }) { bridge in
                        HueDeviceCard(store: store, bridge: bridge, query: query) { pairing = bridge }
                    }
                    if store.bridges.isEmpty { ContentUnavailableView(L10n.value("Noch keine Hue-Bridge"), systemImage: "lightbulb.2.fill", description: Text(L10n.value("Geräte suchen oder die Bridge-IP manuell hinzufügen."))) }
                }
                DisclosureGroup(L10n.value("Hilfe zum lokalen Netzwerk")) {
                    Text(L10n.value("Verbinde diesen Mac oder dieses iPhone mit demselben Netzwerk wie Sonos und Hue. Erlaube Haunt den lokalen Netzwerkzugriff. Falls nötig: Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk.")).font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                }
            }.padding(26)
        }.navigationTitle(L10n.value("Geräte"))
        .sheet(item: $pairing) { bridge in HuePairingView(store: store, bridge: bridge) }
        .sheet(isPresented: $manual) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.value("Bridge über IP hinzufügen")).font(.title2.bold())
                    Text(L10n.value("Die IP findest du in der Hue-App oder deinem Router.")).foregroundStyle(.secondary)
                    TextField(L10n.value("Bridge-IP, z. B. 192.168.1.178"), text: $bridgeIP).textFieldStyle(.roundedBorder)
                    Button(L10n.value("Bridge suchen")) { Task { await store.addBridge(ip: bridgeIP); if let found = store.bridges.first(where: { $0.ip == bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines) }) { tab = 1; manual = false; pairing = found } } }.buttonStyle(.borderedProminent).disabled(bridgeIP.isEmpty)
                }.padding(28).navigationTitle(L10n.value("Bridge hinzufügen"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Schließen")) { manual = false } } }
            }.frame(minWidth: 320, idealWidth: 460, minHeight: 260)
        }
        .task { if !store.bridges.isEmpty && store.lights.isEmpty { await store.refreshLights() } }
    }
}

struct DeviceSummaryCards: View {
    @ObservedObject var store: AppStore
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            metric("Sonos", "\(store.speakers.count)", L10n.value("Geräte gefunden"), "hifispeaker.fill")
            metric(L10n.value("Räume"), "\(store.rooms.count)", L10n.value("Sonos-Abspielziele"), "door.left.hand.open")
            metric("Hue", "\(store.pairedBridgeCount)/\(store.bridges.count)", L10n.value("Bridges gekoppelt"), "link")
            metric(L10n.value("Lampen"), "\(store.lights.count)", L10n.value("auf gekoppelten Bridges"), "lightbulb.fill")
        }
    }
    func metric(_ title: String, _ value: String, _ detail: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 28, weight: .bold, design: .rounded)); Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).hauntedCard()
    }
}
private struct SonosDeviceCard: View {
    @ObservedObject var store: AppStore
    let room: Speaker
    var satellites: [Speaker] { store.speakers.filter { $0.parentID == room.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(room.name, systemImage: "hifispeaker.fill").font(.headline)
            Text(room.model).font(.callout).foregroundStyle(.secondary)
            Text(L10n.value("\(satellites.count + 1) Lautsprecher · ein Abspielziel")).font(.caption).foregroundStyle(.orange)
            DisclosureGroup(L10n.value("Gerätedetails")) {
                Text(room.ip).font(.caption.monospaced()).textSelection(.enabled)
                ForEach(satellites) { speaker in Text(speaker.model + " · " + speaker.ip).font(.caption) }
                if !satellites.isEmpty { Text(L10n.value("Verbundene Lautsprecher spielen gemeinsam mit diesem Raum.")).font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).hauntedCard()
    }
}
private struct HueDeviceCard: View {
    @ObservedObject var store: AppStore
    let bridge: HueBridge
    let query: String
    let pair: () -> Void
    @State private var allLights = false
    var paired: Bool { CredentialStore.read(bridge.id) != nil }
    var lights: [HueLight] { store.lights.filter { $0.bridgeID == bridge.id } }
    var rooms: [HueRoom] { store.hueRooms.filter { $0.bridgeID == bridge.id && !$0.isZone } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "lightbulb.2.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) { Text(bridge.name).font(.title3.bold()); Text(bridge.ip).font(.caption.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                Label(paired ? L10n.value("Gekoppelt") : L10n.value("Nicht gekoppelt"), systemImage: paired ? "checkmark.circle.fill" : "link").foregroundStyle(paired ? .green : .orange).font(.caption)
                if paired { Button(L10n.value("Aktualisieren")) { Task { await store.refreshLights() } }.disabled(store.playback.running) }
                else { Button(L10n.value("Bridge koppeln"), action: pair).buttonStyle(.borderedProminent).disabled(store.playback.running) }
            }
            if !paired {
                Button(L10n.value("Gespeicherten Hue-Zugriff freigeben")) {
                    if CredentialStore.requestAccess(bridge.id) {
                        Task { await store.refreshLights() }
                    } else {
                        store.error = L10n.value("Kein Zugriff auf den gespeicherten Hue-Schlüssel. Du kannst die Freigabe später erneut versuchen oder die Bridge neu koppeln.")
                    }
                }.disabled(store.playback.running)
            }
            if paired {
                Text(L10n.value("\(lights.count) Lampen · \(rooms.count) Räume · \(store.hueInputs.filter { $0.bridgeID == bridge.id }.count) Auslöser-Eingänge")).font(.callout).foregroundStyle(.secondary)
                if let status = store.bridgeStatus[bridge.id], lights.isEmpty { Text(status).font(.caption).foregroundStyle(.orange) }
                if !rooms.isEmpty {
                    DisclosureGroup(L10n.value("Räume & Lampen anzeigen")) {
                        ForEach(rooms) { room in
                            DisclosureGroup {
                                ForEach(lights.filter { room.lightIDs.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { light in lightRow(light) }
                            } label: { Label(L10n.value("\(room.name) · \(room.lightIDs.count) Lampen"), systemImage: "door.left.hand.open") }.padding(.vertical, 5)
                        }
                    }
                }
                DisclosureGroup(L10n.value("Alle Lampen durchsuchen"), isExpanded: Binding(get: { allLights || !query.isEmpty }, set: { allLights = $0 })) {
                    ForEach(lights.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { light in lightRow(light) }
                }
            } else { Text(L10n.value("Koppeln öffnet eine Anleitung für die Taste auf dieser Bridge.")).font(.callout).foregroundStyle(.secondary) }
        }.hauntedCard()
    }
    func lightRow(_ light: HueLight) -> some View { HStack { Label(light.name, systemImage: "lightbulb.fill"); Spacer(); Text(light.reachable ? L10n.value("Erreichbar") : "Offline").foregroundStyle(light.reachable ? Color.secondary : Color.orange); HueLightTestButton(store: store, light: light) }.font(.caption).padding(.vertical, 3) }
}
