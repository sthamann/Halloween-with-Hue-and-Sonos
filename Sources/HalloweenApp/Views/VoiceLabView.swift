import SwiftUI
import HalloweenCore
import UniformTypeIdentifiers

struct VoiceLabRequest: Identifiable {
    let id = UUID()
    var clip: SoundClip?
}

struct VoiceLabView: View {
    @ObservedObject var store: AppStore
    var clip: SoundClip?
    var onSaved: ((SoundClip) -> Void)?
    @StateObject private var lab = VoiceLabStore()
    @State private var mode = "record"
    @State private var importing = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(eyebrow: L10n.value("Alles bleibt auf diesem Gerät"), title: L10n.value("Dein lokales Stimmenlabor"), subtitle: L10n.value("Aufnehmen oder Text sprechen lassen. Effekt anhören. Als Sound in jeder Szene verwenden."))
                    #if os(macOS)
                    HStack(alignment: .top, spacing: 20) { sourcePanel.frame(maxWidth: .infinity); effectPanel.frame(maxWidth: .infinity) }
                    #else
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 20) { sourcePanel.frame(maxWidth: .infinity); effectPanel.frame(maxWidth: .infinity) }
                    } else { VStack(alignment: .leading, spacing: 20) { sourcePanel; effectPanel } }
                    #endif
                    if let error = lab.error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    if let status = lab.status { Text(status).font(.callout).foregroundStyle(.secondary) }
                    savePanel
                }.frame(maxWidth: .infinity).padding(24)
            }.navigationTitle(L10n.value("Stimmenlabor"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Schließen")) { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                do { lab.importAudio(try result.get()) } catch { lab.error = error.localizedDescription }
            }
            .onAppear {
                if let clip, let recipe = store.voiceRecipe(for: clip), let source = store.voiceSource(for: recipe) {
                    lab.load(source: source, recipe: recipe, name: clip.name + L10n.value(" Variante")); mode = recipe.text == nil ? "record" : "text"
                }
            }
            .onChange(of: lab.effect) { _, _ in lab.invalidate() }
            .onChange(of: lab.intensity) { _, _ in lab.invalidate() }
            .onChange(of: lab.trimStart) { _, _ in lab.invalidate() }
            .onChange(of: lab.trimEnd) { _, _ in lab.invalidate() }
            .onChange(of: lab.language) { _, _ in lab.chooseVoice() }
            .onChange(of: phase) { _, value in if value != .active { if lab.recording { lab.finishRecording() }; lab.stopPreview() } }
            .onDisappear { lab.cleanup() }
        }
        #if os(macOS)
        .frame(minWidth: 920, idealWidth: 1040, minHeight: 740, idealHeight: 820)
        #else
        .presentationDetents([.large])
        .modifier(StudioPresentation())
        #endif
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.value("1 · Deine Stimme"), systemImage: "mic.fill").font(.title3.bold())
            Picker(L10n.value("Quelle"), selection: $mode) {
                Text(L10n.value("Aufnahme")).tag("record")
                Text(L10n.value("Apple-Stimme")).tag("text")
            }.pickerStyle(.segmented).disabled(lab.recording || lab.busy)
            if mode == "record" {
                Text(L10n.value("Sprich, flüstere oder schreie deinen Text selbst ein. Maximal 60 Sekunden.")).font(.callout).foregroundStyle(.secondary)
                if lab.recording {
                    Label(L10n.value("Aufnahme läuft"), systemImage: "record.circle.fill").foregroundStyle(.red)
                    ProgressView(value: Double(lab.level)).tint(.red)
                    Text("\(lab.elapsed, specifier: "%.1f") / 60 s").monospacedDigit()
                    Button { lab.finishRecording() } label: { Label(L10n.value("Aufnahme beenden"), systemImage: "stop.fill") }.buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button { store.stopPreview(); Task { await lab.startRecording() } } label: { Label(L10n.value("Aufnahme starten"), systemImage: "record.circle") }.buttonStyle(.borderedProminent).disabled(lab.busy)
                    Button { importing = true } label: { Label(L10n.value("Aufnahme importieren"), systemImage: "square.and.arrow.down") }.disabled(lab.busy)
                }
            } else {
                Picker(L10n.value("Sprache"), selection: $lab.language) { Text("Deutsch").tag("de-DE"); Text("English").tag("en-US") }.disabled(lab.busy)
                if lab.matchingVoices.isEmpty {
                    Text(L10n.value("Keine passende Apple-Stimme installiert. Bitte eine Stimme in den Bedienungshilfen der Systemeinstellungen laden.")).foregroundStyle(.orange)
                } else {
                    Picker(L10n.value("Apple-Stimme"), selection: $lab.voiceID) { ForEach(lab.matchingVoices) { voice in Text(voice.title).tag(voice.id) } }.disabled(lab.busy)
                }
                TextField(L10n.value("Dein Text · maximal 300 Zeichen"), text: $lab.text, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).disabled(lab.busy)
                Text("\(lab.text.count)/300").font(.caption).foregroundStyle(lab.text.count > 300 ? .orange : .secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { voiceSample; createSpeech }
                    VStack(alignment: .leading) { voiceSample; createSpeech }
                }
                Text(L10n.value("Die Hörprobe spielt nur auf diesem Gerät. Erweiterte Stimmen müssen gegebenenfalls zuerst über die Systemeinstellungen geladen werden.")).font(.caption).foregroundStyle(.secondary)
                if lab.speechNeedsUpdate { Text(L10n.value("Text oder Stimme geändert. Bitte zuerst „Text übernehmen“ wählen.")).font(.caption).foregroundStyle(.orange) }
            }
            if lab.source != nil {
                Divider()
                Label(L10n.value("Original vorhanden"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(lab.duration, specifier: "%.1f") s").font(.caption).monospacedDigit()
                Button { store.stopPreview(); lab.previewOriginal() } label: { Label(L10n.value("Original anhören"), systemImage: "headphones") }.disabled(lab.busy || lab.recording)
            }
        }.hauntedCard()
    }
    private var textDisabled: Bool { lab.busy || lab.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lab.text.count > 300 || lab.voiceID.isEmpty }
    private var voiceSample: some View { Button { store.stopPreview(); lab.createSpeech(sampleOnly: true) } label: { Label(L10n.value("Stimme probehören"), systemImage: "headphones") }.disabled(textDisabled) }
    private var createSpeech: some View { Button { lab.createSpeech() } label: { Label(L10n.value("Text übernehmen"), systemImage: "waveform") }.buttonStyle(.borderedProminent).disabled(textDisabled) }

    private var effectPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.value("2 · Spuk-Effekt & Vorschau"), systemImage: "waveform.path").font(.title3.bold())
            Picker(L10n.value("Stimmeffekt"), selection: $lab.effect) { ForEach(VoiceLabEffect.allCases) { Text($0.title).tag($0) } }
            Text(L10n.value("Intensität") + " · \(Int(lab.intensity * 100)) %").font(.callout)
            Slider(value: $lab.intensity, in: 0...1, step: 0.05).disabled(lab.effect == .natural)
            if lab.duration >= 0.1 {
                Text(L10n.value("Ausschnitt") + " · \(String(format: "%.1f", lab.trimStart))–\(String(format: "%.1f", lab.trimEnd)) s").font(.callout)
                HStack { Text(L10n.value("Anfang")); Slider(value: $lab.trimStart, in: 0...max(0.001, lab.duration - 0.1), step: 0.01) }
                HStack { Text(L10n.value("Ende")); Slider(value: $lab.trimEnd, in: 0.1...max(0.101, lab.duration), step: 0.01) }
            }
            Text(L10n.value("Effekte werden einmal lokal berechnet. Die Szene spielt anschließend den fertigen Sound ab.")).font(.caption).foregroundStyle(.secondary)
            if lab.busy { ProgressView(L10n.value("Stimme wird vorbereitet …")) }
            Button { store.stopPreview(); lab.renderPreview() } label: { Label(L10n.value("Effekt-Vorschau"), systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(lab.source == nil || lab.busy || lab.recording || lab.speechNeedsUpdate)
            if lab.playing { Button { lab.stopPreview() } label: { Label(L10n.value("Vorschau stoppen"), systemImage: "stop.fill") } }
        }.hauntedCard().disabled(lab.recording || lab.busy)
    }

    private var savePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.value("3 · In deiner Soundbibliothek speichern"), systemImage: "square.and.arrow.down.fill").font(.title3.bold())
            TextField(L10n.value("Name des Sounds"), text: $lab.name).textFieldStyle(.roundedBorder)
            Text(L10n.value("Der fertige Sound steht in allen Szenen bereit. Das Original bleibt erhalten, damit du später weitere Varianten erstellen kannst.")).font(.caption).foregroundStyle(.secondary)
            Button {
                guard let audio = lab.rendered, let source = lab.source else { return }
                do { let saved = try store.saveVoice(name: lab.name, audio: audio, source: source, recipe: lab.recipe); onSaved?(saved); dismiss() }
                catch { lab.error = error.localizedDescription }
            } label: { Label(L10n.value("Sound speichern"), systemImage: "checkmark.circle.fill") }.buttonStyle(.borderedProminent).disabled(lab.rendered == nil || lab.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lab.name.count > 100 || lab.busy || lab.recording || lab.speechNeedsUpdate)
            if lab.source != nil && lab.rendered == nil { Text(L10n.value("Vor dem Speichern die Effekt-Vorschau starten.")).font(.caption).foregroundStyle(.orange) }
        }.hauntedCard()
    }
}

#if os(iOS)
struct StudioPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) { content.presentationSizing(.page) }
        else { content }
    }
}
#endif
