import SwiftUI
import HalloweenCore

private func hauntPublicPage(_ page: String) -> URL {
    let language = L10n.isEnglish ? "en" : "de"
    return URL(string: "https://haunt-halloween-support.stefanhamann83.chatgpt.site/\(language)/\(page).html")!
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.text("Dein Haus bleibt dein Haus.")).font(.title.bold())
                    Text(L10n.text("Haunt speichert Szenen, Audiodateien und Gerätenamen auf diesem Gerät. Hue-Schlüssel werden im Apple-Schlüsselbund gespeichert. Beim Export enthält die Datei deine Szene, Auslöser und eigene Sounds, aber keine Hue-Schlüssel."))
                    Text(L10n.text("Die Gerätesuche verbindet sich mit lokalen IP-Adressen. Sonos erhält Audiodateien von einem lokalen HTTP-Server in der App. Hue-Verbindungen verwenden geprüfte TLS-Zertifikate. Das Mikrofon wird nur für eine von dir gestartete Aufnahme im Stimmenlabor benötigt. Aufnahmen und Stimmeffekte bleiben lokal. Kamera und Standort werden nicht benötigt."))
                    Link(L10n.isEnglish ? "Full privacy policy and contact" : "Vollständiger Datenschutz und Kontakt", destination: hauntPublicPage("privacy"))
                }.padding(26)
            }.navigationTitle(L10n.text("Datenschutz"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Schließen")) { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 580, height: 650)
        #endif
    }
}
