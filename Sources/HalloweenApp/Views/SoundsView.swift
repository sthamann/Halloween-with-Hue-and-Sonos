import SwiftUI
import HalloweenCore
import UniformTypeIdentifiers

struct SoundsView: View {
    @ObservedObject var store: AppStore
    @State private var playbackRequest: SonosSoundRequest?
    @State private var voiceLabRequest: VoiceLabRequest?
    @State private var importing = false
    @State private var showingCredits = false
    @State private var category = L10n.value("Alle")
    @State private var query = ""
    @State private var selectedRooms: Set<String> = []
    @State private var volume = 25.0
    init(store: AppStore) { self.store = store }
    var categories: [String] { [L10n.value("Alle")] + Array(Set(store.sounds.map { $0.category ?? L10n.value("Eigene Imports") })).sorted() }
    var filtered: [SoundClip] { store.sounds.filter { (category == L10n.value("Alle") || ($0.category ?? L10n.value("Eigene Imports")) == category) && (query.isEmpty || L10n.text($0.name).localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query) || ($0.category ?? "").localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(eyebrow: "Soundlabor", title: L10n.value("Das Geräusch hinter der Tür."), subtitle: L10n.value("\(store.sounds.filter(\.builtIn).count) eingebaute Effekte, deine MP3s und eine Stimme, die deinen Text sagt."))
                VStack(alignment: .leading, spacing: 14) {
                    DisclosureGroup(L10n.value("Zielräume · \(selectedRooms.count) ausgewählt")) { RoomPicker(store: store, selection: $selectedRooms).padding(.top, 10) }
                    HStack { Text(L10n.value("Sonos-Lautstärke")); Slider(value: $volume, in: 0...100, step: 1); Text("\(Int(volume))/100").monospacedDigit().frame(width: 66) }
                    Text(L10n.value("Vorschau spielt nur auf diesem Gerät. „Auf Sonos“ spielt einmal in den ausgewählten Räumen.")).font(.caption).foregroundStyle(.secondary)
                }.hauntedCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.value("Lokales Stimmenlabor"), systemImage: "mic.fill").font(.title2.bold())
                    Text(L10n.value("Aufnehmen, Apple-Stimmen auswählen und Horror-Effekte als eigene Sounds speichern.")).foregroundStyle(.secondary)
                    Button { voiceLabRequest = VoiceLabRequest() } label: { Label(L10n.value("Stimmenlabor öffnen"), systemImage: "waveform.path") }.buttonStyle(.borderedProminent)
                }.hauntedCard()
                Button { importing = true } label: { Label(L10n.value("Eigenen Sound importieren"), systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                HStack {
                    Picker(L10n.value("Kategorie"), selection: $category) { ForEach(categories, id: \.self) { Text(L10n.text($0)).tag($0) } }.pickerStyle(.menu)
                    Spacer()
                    Button { showingCredits = true } label: { Label(L10n.value("Quellen & Lizenzen"), systemImage: "info.circle") }
                }
                if filtered.isEmpty { ContentUnavailableView(L10n.value("Kein passender Sound"), systemImage: "waveform", description: Text(L10n.value("Wähle eine andere Kategorie oder ändere deine Suche."))) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 16)], spacing: 16) {
                    ForEach(filtered) { clip in
                        VStack(alignment: .leading, spacing: 15) {
                            HStack { Image(systemName: clip.symbol).font(.title).foregroundStyle(.orange); Spacer(); Text("\(clip.duration, specifier: "%.1f") s").font(.caption).foregroundStyle(.secondary) }
                            Text(L10n.text(clip.name)).font(.headline)
                            Text(L10n.text(clip.category ?? L10n.value("Eigener Import"))).font(.caption).foregroundStyle(.secondary)
                            if store.voiceRecipe(for: clip) != nil { Button(L10n.value("Neue Stimmvariante")) { voiceLabRequest = VoiceLabRequest(clip: clip) } }
                            if let credit = clip.credit { Text("\(credit.license) · \(credit.author)").font(.caption2).foregroundStyle(.secondary) }
                            HStack { Button { store.previewSound(clip) } label: { Label(L10n.value("Vorschau"), systemImage: "headphones") }.disabled(store.playback.running); Button { playbackRequest = SonosSoundRequest(clip: clip) } label: { Label(L10n.value("Auf Sonos"), systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(store.scanning) }
                        }.hauntedCard()
                    }
                }
                Button(L10n.value("Vorschau stoppen")) { store.stopPreview() }
            }.padding(26)
        }.navigationTitle("Sounds")
        .searchable(text: $query, prompt: L10n.value("Sound suchen"))
        .sheet(item: $voiceLabRequest) { request in VoiceLabView(store: store, clip: request.clip) }
        .sheet(item: $playbackRequest) { request in
            SonosPlaybackPicker(store: store, rooms: $selectedRooms, volume: $volume, title: L10n.value("Auf welchen Boxen abspielen?"), detail: request.clip.map { L10n.text($0.name) } ?? "") {
                guard let clip = request.clip else { return false }; return runSound(clip)
            }
        }
        .sheet(isPresented: $showingCredits) { SoundCreditsView(sounds: store.sounds) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in do { store.importSound(try result.get()) } catch { store.error = error.localizedDescription } }
    }
    @discardableResult func runSound(_ clip: SoundClip) -> Bool { var step = SceneStep(kind: .sound, soundID: clip.id); step.waitForSound = true; var scene = HorrorScene(name: clip.name, steps: [step]); scene.roomIDs = selectedRooms; scene.volume = volume; return store.run(scene) }
}

private struct SonosSoundRequest: Identifiable {
    let id = UUID()
    let clip: SoundClip?
}
private struct SonosPlaybackPicker: View {
    @ObservedObject var store: AppStore
    @Binding var rooms: Set<String>
    @Binding var volume: Double
    let title: String
    let detail: String
    let play: () -> Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(detail).font(.headline).lineLimit(4)
                Text(L10n.value("Wähle die Sonos-Räume für diese Wiedergabe.")).foregroundStyle(.secondary)
                ScrollView { RoomPicker(store: store, selection: $rooms) }
                HStack { Text(L10n.value("Lautstärke")); Slider(value: $volume, in: 0...100, step: 1); Text("\(Int(volume))/100").monospacedDigit() }
                Text(store.rooms.filter { rooms.contains($0.id) }.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.orange)
            }.padding(24).navigationTitle(title)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Abbrechen")) { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    HStack { Spacer(); Button(L10n.value("Jetzt auf Sonos abspielen")) { if play() { dismiss() } }.buttonStyle(.borderedProminent).disabled(rooms.intersection(Set(store.rooms.map(\.id))).isEmpty || store.scanning) }.padding()
                }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 580)
        #endif
    }
}
