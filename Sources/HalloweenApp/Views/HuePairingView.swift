import SwiftUI
import HalloweenCore

struct HuePairingView: View {
    @ObservedObject var store: AppStore
    let bridge: HueBridge
    @State private var busy = false
    @State private var connected = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: connected ? "checkmark.circle.fill" : "hand.tap.fill").font(.system(size: 56)).foregroundStyle(connected ? .green : .orange)
                Text(connected ? L10n.value("Bridge verbunden") : L10n.value("Drücke jetzt die Bridge-Taste")).font(.title2.bold())
                Text(bridge.name + " · " + bridge.ip).font(.headline)
                if connected {
                    Text(L10n.value("Die Lampen und Auslöser dieser Bridge stehen jetzt in deinen Szenen bereit.")).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button(L10n.value("Fertig")) { dismiss() }.buttonStyle(.borderedProminent)
                } else {
                    Text(L10n.value("1. Drücke einmal die große Taste auf genau dieser Hue-Bridge.\n2. Bestätige danach hier innerhalb von 30 Sekunden.")).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if busy { ProgressView(L10n.value("Verbindung wird hergestellt …")) }
                    if let issue { Text(issue).foregroundStyle(.orange).multilineTextAlignment(.center) }
                    Button {
                        busy = true; issue = nil
                        Task { connected = await store.pair(bridge); if !connected { issue = store.error; store.error = nil }; busy = false }
                    } label: { Label(L10n.value("Ich habe die Taste gedrückt · jetzt koppeln"), systemImage: "link") }.buttonStyle(.borderedProminent).disabled(busy)
                    Text(L10n.value("Noch nichts gedrückt? Du kannst die Taste jetzt drücken und danach bestätigen.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }.padding(32).navigationTitle(L10n.value("Hue-Bridge koppeln"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Abbrechen")) { dismiss() }.disabled(busy) } }
        }
        #if os(macOS)
        .frame(width: 540, height: 450)
        #endif
    }
}
