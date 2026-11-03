import SwiftUI
import HalloweenCore

struct HueLightTestButton: View {
    @ObservedObject var store: AppStore
    let light: HueLight
    var busy: Bool { store.testingLightID == light.id }
    var body: some View {
        Button {
            Task { await store.testLight(light) }
        } label: {
            Label(L10n.value(busy ? "Blinkt …" : "Test"), systemImage: busy ? "hourglass" : "lightbulb.max.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!light.reachable || store.testingLightID != nil || store.playback.running || store.automationEnabled || CredentialStore.read(light.bridgeID) == nil)
        .help(L10n.value(store.playback.running || store.automationEnabled ? "Für den Lampentest Abläufe beenden und Automatik ausschalten." : "Diese Lampe einmal kurz aufblinken lassen."))
        .accessibilityLabel(L10n.value("\(light.name) einmal aufblinken lassen"))
    }
}
