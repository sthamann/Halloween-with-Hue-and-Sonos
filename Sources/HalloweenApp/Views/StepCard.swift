import SwiftUI
import HalloweenCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(iOS)
private struct SceneSoundChooser: View {
    let sounds: [SoundClip]
    @Binding var selected: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var filtered: [SoundClip] {
        sounds.filter { query.isEmpty || L10n.text($0.name).localizedCaseInsensitiveContains(query) || L10n.text($0.category ?? "").localizedCaseInsensitiveContains(query) }
            .sorted { if $0.builtIn != $1.builtIn { return !$0.builtIn }; return L10n.text($0.name).localizedStandardCompare(L10n.text($1.name)) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List(filtered) { clip in
                Button {
                    selected = clip.id; dismiss()
                } label: {
                    HStack {
                        Image(systemName: clip.symbol).foregroundStyle(.orange)
                        VStack(alignment: .leading) { Text(L10n.text(clip.name)); Text(L10n.text(clip.category ?? "Eigener Import") + " · \(Int(clip.duration)) s").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if selected == clip.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange) }
                    }.foregroundStyle(.primary)
                }
            }.searchable(text: $query, prompt: L10n.value("Sound suchen"))
                .navigationTitle(L10n.value("Sound auswählen"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Abbrechen")) { dismiss() } } }
        }
    }
}
#endif

struct StepCard: View {
    @ObservedObject var store: AppStore
    @Binding var step: SceneStep
    let sceneRoomIDs: Set<String>
    let sceneLightIDs: Set<String>
    let number: Int; let active: Bool; let moveUp: () -> Void; let moveDown: () -> Void; let remove: () -> Void
    @State private var choosingSound = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(String(number)).font(.headline).foregroundStyle(.orange).frame(width: 28, height: 28).background(.orange.opacity(0.15), in: Circle())
                Picker(L10n.value("Aktion"), selection: $step.kind) { ForEach(StepKind.allCases) { kind in Label(L10n.text(kind.title), systemImage: kind.symbol).tag(kind) } }.labelsHidden()
                Spacer()
                if step.startTime == nil {
                Button(action: moveUp) { Image(systemName: "arrow.up") }.help(L10n.value("Nach oben"))
                Button(action: moveDown) { Image(systemName: "arrow.down") }.help(L10n.value("Nach unten"))
                }
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
            }
            switch step.kind {
            case .sound:
                #if os(iOS)
                Button { choosingSound = true } label: {
                    HStack { Label(L10n.text(store.sounds.first { $0.id == step.soundID }?.name ?? "Sound"), systemImage: "waveform"); Spacer(); Image(systemName: "chevron.right") }
                }.sheet(isPresented: $choosingSound) { SceneSoundChooser(sounds: store.sounds, selected: $step.soundID) }
                #else
                Picker("Sound", selection: $step.soundID) { ForEach(store.sounds) { clip in Text(L10n.text(clip.name) + " · \(Int(clip.duration)) s").tag(clip.id) } }
                #endif
                if step.startTime == nil { Toggle(L10n.value("Vor dem nächsten Schritt auf Soundende warten"), isOn: $step.waitForSound).font(.caption) }
            case .speech:
                TextField(L10n.value("Was soll die Stimme sagen?"), text: $step.text, axis: .vertical).textFieldStyle(.roundedBorder)
                Picker(L10n.value("Sprache der Stimme"), selection: Binding(get: { step.speechLanguage ?? L10n.speechLanguage }, set: { step.speechLanguage = $0 })) { Text("Deutsch").tag("de-DE"); Text("English").tag("en-US") }
                Picker(L10n.value("Stimmeffekt"), selection: Binding(get: { step.voiceEffect ?? .ghost }, set: { step.voiceEffect = $0 })) { ForEach(VoiceEffect.allCases) { effect in Text(effect.title).tag(effect) } }
                Text(L10n.value("Maximal 300 Zeichen")).font(.caption).foregroundStyle(.secondary)
                if step.startTime == nil { Toggle(L10n.value("Auf das Ende der Stimme warten"), isOn: $step.waitForSound).font(.caption) }
            case .wait: secondsControl
            case .color:
                secondsControl; colorControls
            case .flicker:
                secondsControl; colorControls
                Picker("Hue-Effekt", selection: Binding(get: { step.hueEffect ?? .ghostFlicker }, set: { step.hueEffect = $0; step.hue = $0.defaultHue })) { ForEach(HueEffectKind.allCases) { effect in Text(L10n.text(effect.title)).tag(effect) } }
                Text((step.hueEffect ?? .ghostFlicker).detail).font(.caption).foregroundStyle(.secondary)
            case .blackout:
                secondsControl
                Text(L10n.value("Die ausgewählten Lampen bleiben bis zum nächsten Lichtschritt oder Szenenende aus.")).font(.caption).foregroundStyle(.secondary)
            }
            if step.kind.usesRooms {
                let full = step.kind == .sound ? (store.sounds.first { $0.id == step.soundID }?.duration ?? 4) : SceneTimeline.estimatedSpeechDuration(step.text)
                HStack {
                    Text(L10n.value("Clip-Dauer"))
                    TextField(L10n.value("Sekunden"), value: Binding(get: { min(full, step.audioDuration ?? full) }, set: { step.audioDuration = max(0.1, min(full, $0)) }), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width: 75)
                    Text("s")
                    Button(L10n.value("Volle Länge")) { step.audioDuration = nil }.font(.caption)
                }
                let inherited = step.roomIDs.isEmpty
                let effective = inherited ? sceneRoomIDs : step.roomIDs
                DisclosureGroup(inherited ? L10n.value("Boxen für diesen Clip · \(effective.count) aus der Szene") : L10n.value("Boxen für diesen Clip · \(effective.count) eigene")) {
                    if !sceneRoomIDs.isEmpty {
                        Toggle(L10n.value("Boxen aus der Szene übernehmen"), isOn: Binding(get: { step.roomIDs.isEmpty }, set: { step.roomIDs = $0 ? [] : sceneRoomIDs })).toggleStyle(.switch).font(.caption)
                    }
                    RoomPicker(store: store, selection: Binding(get: { step.roomIDs.isEmpty ? sceneRoomIDs : step.roomIDs }, set: { step.roomIDs = $0 })).padding(.top, 8).disabled(inherited && !sceneRoomIDs.isEmpty)
                    Text(L10n.value(inherited ? "Diese Boxen gelten automatisch. Für andere Boxen die Übernahme ausschalten." : "Eigene Auswahl für diesen Clip. Eine leere Auswahl übernimmt wieder die Szenenboxen.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if step.kind.usesLights {
                let inherited = step.lightIDs.isEmpty
                let effective = inherited ? sceneLightIDs : step.lightIDs
                DisclosureGroup(inherited ? L10n.value("Lampen für diesen Clip · \(effective.count) aus der Szene") : L10n.value("Lampen für diesen Clip · \(effective.count) eigene")) {
                    if !sceneLightIDs.isEmpty {
                        Toggle(L10n.value("Lampen aus der Szene übernehmen"), isOn: Binding(get: { step.lightIDs.isEmpty }, set: { step.lightIDs = $0 ? [] : sceneLightIDs })).toggleStyle(.switch).font(.caption)
                    }
                    if inherited && !sceneLightIDs.isEmpty {
                        ForEach(store.lights.filter { sceneLightIDs.contains($0.id) }) { light in
                            HStack { Label(light.name, systemImage: "checkmark.square.fill").foregroundStyle(.orange); Spacer(); HueLightTestButton(store: store, light: light) }
                        }
                    } else { LightPicker(store: store, selection: $step.lightIDs).padding(.top, 8) }
                    Text(L10n.value(inherited ? "Diese Lampen gelten automatisch. Für andere Lampen die Übernahme ausschalten." : "Eigene Auswahl für diesen Clip. Eine leere Auswahl übernimmt wieder die Szenenlampen.")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.hauntedCard().overlay(RoundedRectangle(cornerRadius: 18).stroke(active ? .orange : .clear, lineWidth: 2))
    }
    var secondsControl: some View { HStack { Text(L10n.value("Dauer")); Slider(value: $step.seconds, in: 0.1...max(60, step.seconds), step: 0.1); TextField(L10n.value("Sekunden"), value: Binding(get: { step.seconds }, set: { step.seconds = max(0.1, min(600, $0)) }), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width: 65); Text("s") } }
    var colorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L10n.value("Helligkeit")); Slider(value: $step.brightness, in: 0...100, step: 1); Text("\(Int(step.brightness)) %").frame(width: 50) }
            Toggle(L10n.value("Aktuelle Farbe jeder Lampe beibehalten"), isOn: Binding(get: { step.useLampColor ?? false }, set: { step.useLampColor = $0 })).toggleStyle(.switch)
            if step.useLampColor == true {
                Text(L10n.value("Nur Helligkeit und Flackern ändern sich. Jede Lampe behält ihre eigene Farbe oder Weißtemperatur.")).font(.caption).foregroundStyle(.secondary)
            }
            ColorPicker(L10n.value("Eigene Farbe"), selection: Binding(get: { Color(hue: step.hue / 360, saturation: (step.saturation ?? 100) / 100, brightness: step.brightness / 100) }, set: { setColor($0) }), supportsOpacity: false).disabled(step.useLampColor == true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], alignment: .leading) { ForEach([(L10n.value("Blutrot"), 0.0), (L10n.value("Kürbis"), 28.0), (L10n.value("Giftgrün"), 110.0), (L10n.value("Geisterblau"), 230.0), (L10n.value("Violett"), 280.0)], id: \.0) { name, hue in Button(name) { step.hue = hue; step.saturation = 100 }.font(.caption).disabled(step.useLampColor == true).disabled(step.useLampColor == true) } }
        }
    }
    func setColor(_ color: Color) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        #if os(macOS)
        guard let resolved = NSColor(color).usingColorSpace(.deviceRGB) else { return }
        resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #else
        UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #endif
        step.hue = Double(hue) * 360; step.saturation = Double(saturation) * 100; step.brightness = Double(brightness) * 100
    }
}
