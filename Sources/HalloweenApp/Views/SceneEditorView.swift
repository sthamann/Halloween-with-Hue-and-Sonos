import SwiftUI
import HalloweenCore
import Combine
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct SceneEditorView: View {
    var closeEditor: (() -> Void)?
    @ObservedObject var store: AppStore
    var runner: SceneRunner? { store.playback.runner(for: scene.id) ?? devicePreviewRunner }
    var isRunning: Bool { runner?.running == true }
    @State var scene: HorrorScene
    @StateObject private var preview = ScenePreview()
    @State private var selected: UUID?
    @State private var clipFocusRequest = 0
    @State private var devicePreviewRunner: SceneRunner?
    @State private var runnerRevision = 0
    @State private var devicePreviewActive = false
    @State private var audioPreview = true
    @State private var playhead = 0.0
    @State private var showStage = false
    @State private var showCombos = false
    @State private var addAtPlayhead = false
    @State private var importingSound = false
    @State private var showingVoiceLab = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    init(store: AppStore, scene: HorrorScene, closeEditor: (() -> Void)? = nil) {
        self.closeEditor = closeEditor
        self.store = store
        self._selected = State(initialValue: scene.steps.first?.id)
        self._scene = State(initialValue: SceneTimeline.migrating(scene, soundDurations: Dictionary(uniqueKeysWithValues: store.sounds.map { ($0.id, $0.duration) })))
    }
    var durations: [String: Double] { Dictionary(uniqueKeysWithValues: store.sounds.map { ($0.id, $0.duration) }) }
    var plan: SceneTimeline { SceneTimeline(scene: scene, soundDurations: durations, speechDurations: preview.speechDurations) }
    var issue: String? { do { try plan.validate(scene: scene); return nil } catch { return error.localizedDescription } }
    var body: some View {
        let _ = runnerRevision
        return NavigationStack {
            editorContent
            .navigationTitle(L10n.value("Spukstudio"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Schließen")) { closeStudio() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.value("Speichern")) { if save() { closeStudio() } }.disabled(scene.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || issue != nil) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack { Text(L10n.value("\(scene.steps.count) Clips · \(plan.duration, specifier: "%.1f") s")).font(.caption.monospacedDigit()).foregroundStyle(.secondary); Spacer(); if isRunning { Button(L10n.value("Haus stoppen"), role: .destructive) { runner?.stop() }.buttonStyle(.borderedProminent) } else { Button { preview.stop(); devicePreviewActive = false; devicePreviewRunner = nil; if save() { store.run(scene) } } label: { Label(L10n.value("Auf dem Haus starten"), systemImage: "house.fill") }.buttonStyle(.borderedProminent).disabled(scene.steps.isEmpty || store.scanning || issue != nil) } }.padding().background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showingVoiceLab) { VoiceLabView(store: store) { sound in
            insertStep(.sound); if let i = scene.steps.indices.last { scene.steps[i].soundID = sound.id }
        } }
        .fileImporter(isPresented: $importingSound, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { let previousCount = store.sounds.count; store.importSound(url); if store.sounds.count > previousCount, let sound = store.sounds.last { insertStep(.sound); if let i = scene.steps.indices.last { scene.steps[i].soundID = sound.id } } }
            if case .failure(let error) = result { store.error = error.localizedDescription }
        }
        .onChange(of: scene) { if devicePreviewActive { runner?.stop() }; preview.invalidate() }
        .onReceive(runner?.objectWillChange.throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true).eraseToAnyPublisher() ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in
            Task { @MainActor in runnerRevision += 1 }
        }
        .onReceive(runner?.$elapsed.throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true).eraseToAnyPublisher() ?? Empty<Double, Never>().eraseToAnyPublisher()) { playhead = $0 }
        .onChange(of: audioPreview) { preview.stop() }
        .onChange(of: phase) { _, value in if value != .active { preview.stop() } }
        .onDisappear { stopEditorPreview() }
        #if os(macOS)
        .background(StudioShortcuts(focusRequest: clipFocusRequest, copy: copyClip, paste: pasteClip, duplicate: duplicateClip, delete: deleteClip).frame(width: 0, height: 0))
        .frame(minWidth: 1100, idealWidth: 1500, minHeight: 700, idealHeight: 980)
        #else
        .presentationDetents([.large])
        .modifier(StudioPresentation())
        #endif
    }
    @ViewBuilder var editorContent: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                sceneHeading.padding(.horizontal, 22).padding(.vertical, 14)
                Divider()
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if scene.steps.isEmpty {
                                SceneTargetsView(store: store, rooms: $scene.roomIDs, lights: $scene.lightIDs)
                                addClipControls
                            } else { HStack { addButtons } }
                            TimelineCanvas(scene: $scene, plan: plan, sounds: store.sounds, selected: Binding(get: { selected }, set: { if let id = $0 { selectClip(id) } else { selected = nil } }), playhead: isRunning ? playhead : preview.time) { value in preview.stop(); preview.scrub(value, duration: plan.duration) }
                            previewControls.hauntedCard()
                            DisclosureGroup(L10n.value("Lichtbühne anzeigen"), isExpanded: $showStage) { stage.padding(.top, 12) }
                            if !scene.steps.isEmpty {
                                DisclosureGroup(L10n.value("Geräteauswahl & weitere Clip-Optionen")) {
                                    SceneTargetsView(store: store, rooms: $scene.roomIDs, lights: $scene.lightIDs)
                                    addClipControls
                                }
                            }
                            DisclosureGroup(L10n.value("Fertige Effekt-Kombis hinzufügen"), isExpanded: $showCombos) { EffectShelf(addCombo: insertCombo, addEffect: insertEffect).padding(.top, 12) }
                            if let issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                        }.padding(18)
                    }.frame(minWidth: 700)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if scene.steps.isEmpty { Text(L10n.value("Wähle links Sound, Licht oder Stimme. Hier bearbeitest du den ausgewählten Clip.")).foregroundStyle(.secondary) }
                            else { clipInspector; Divider(); clipList }
                            Stepper(L10n.value("Durchläufe: \(scene.repetitions)"), value: $scene.repetitions, in: 1...10)
                        }.padding(18)
                    }.frame(minWidth: 340, idealWidth: 420, maxWidth: 520)
                }
            }
            #else
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sceneHeading
                    SceneTargetsView(store: store, rooms: $scene.roomIDs, lights: $scene.lightIDs)
                    addClipControls
                    if scene.steps.isEmpty {
                        ContentUnavailableView(L10n.value("Deine Szene beginnt mit einem Clip"), systemImage: "plus.circle", description: Text(L10n.value("Wähle oben Sound, Lichteffekt oder Stimme. Danach stellst du den Clip hier ein.")))
                    } else {
                        #if os(macOS)
                        HStack(alignment: .top, spacing: 16) { clipList.frame(width: 250); clipInspector.frame(maxWidth: .infinity) }
                        #else
                        clipList
                        clipInspector
                        #endif
                    }
                    Text(L10n.value("3 · Timing & Vorschau")).font(.headline)
                    previewControls.hauntedCard()
                    DisclosureGroup(L10n.value("Lichtbühne anzeigen"), isExpanded: $showStage) { stage.padding(.top, 12) }
                    TimelineCanvas(scene: $scene, plan: plan, sounds: store.sounds, selected: Binding(get: { selected }, set: { if let id = $0 { selectClip(id) } else { selected = nil } }), playhead: isRunning ? playhead : preview.time) { value in preview.stop(); preview.scrub(value, duration: plan.duration) }
                    DisclosureGroup(L10n.value("Fertige Effekt-Kombis hinzufügen"), isExpanded: $showCombos) { EffectShelf(addCombo: insertCombo, addEffect: insertEffect).padding(.top, 12) }
                    if let issue { Label(L10n.text(issue), systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
                    Stepper(L10n.value("Durchläufe: \(scene.repetitions)"), value: $scene.repetitions, in: 1...10)
                    Text(L10n.value("Auf dem Haus starten steuert deine ausgewählten Geräte. Nach Ende oder Stop werden ihre vorherigen Zustände wiederhergestellt. Sonos und Hue starten über WLAN; geringe Verzögerungen sind möglich.")).font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }
            #endif
    }
    var sceneHeading: some View {
        VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.value("DEIN HALLOWEEN-STUDIO")).font(.caption.bold()).tracking(3).foregroundStyle(.orange)
                        TextField(L10n.value("Name deiner Szene"), text: $scene.name).font(.title.bold()).textFieldStyle(.plain)
                        HStack { Label(L10n.value("Lautstärke"), systemImage: "speaker.wave.2.fill"); Slider(value: $scene.volume, in: 0...100, step: 1); Text("\(Int(scene.volume)) %").font(.caption.monospacedDigit()).frame(width: 48) }
                    }
    }
    var addClipControls: some View {
        VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.value("2 · Was passiert?")).font(.headline)
                        ViewThatFits(in: .horizontal) {
                            HStack { addButtons }
                            VStack(alignment: .leading) { addButtons }
                        }
                        HStack {
                            Toggle(L10n.value("Am Vorschau-Zeitpunkt einfügen"), isOn: $addAtPlayhead).font(.caption)
                            Spacer()
                            Button(L10n.value("Eigenen Sound importieren")) { importingSound = true }.font(.caption)
                        }
                        Text(addAtPlayhead ? L10n.value("Neue Clips starten bei \(preview.time, specifier: "%.1f") s und können parallel laufen.") : L10n.value("Neue Clips werden ans Ende angefügt. Auf der Zeitleiste kannst du sie frei verschieben.")).font(.caption).foregroundStyle(.secondary)
                    }.hauntedCard()
    }
    var insertionTime: Double { addAtPlayhead ? preview.time : (scene.steps.isEmpty ? 0 : plan.duration) }
    @ViewBuilder var addButtons: some View {
        Button { insertStep(.sound) } label: { Label(L10n.value("Sound hinzufügen"), systemImage: "waveform.badge.plus") }.buttonStyle(.borderedProminent)
        Menu {
            ForEach(HueEffectKind.allCases) { effect in Button(effect.title) { insertEffect(effect) } }
            Divider()
            Button(L10n.value("Lichtfarbe")) { insertStep(.color) }
            Button(L10n.value("Licht aus")) { insertStep(.blackout) }
        } label: { Label(L10n.value("Lichteffekt hinzufügen"), systemImage: "bolt.fill") }.buttonStyle(.bordered)
        Menu {
            Button(L10n.value("Stimmenlabor öffnen")) { preview.stop(); showingVoiceLab = true }
            Button(L10n.value("Einfache Textansage")) { insertStep(.speech) }
        } label: { Label(L10n.value("Stimme hinzufügen"), systemImage: "mic.fill") }.buttonStyle(.bordered)
        Button { insertStep(.wait) } label: { Label(L10n.value("Pause"), systemImage: "hourglass") }.buttonStyle(.bordered)
    }
    var clipList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.value("Dein Ablauf · \(scene.steps.count) Clips")).font(.headline)
            ForEach(Array(scene.steps.enumerated()), id: \.element.id) { index, step in
                Button { selectClip(step.id) } label: {
                    HStack(alignment: .top) {
                        Text(String(index + 1)).font(.caption.bold()).foregroundStyle(.orange).frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(step.kind.title, systemImage: step.kind.symbol).font(.headline)
                            Text(clipTitle(step)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(String(format: "%.1f s", step.startTime ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(.orange)
                        }
                        Spacer()
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected == step.id ? .orange.opacity(0.15) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }
    func clipTitle(_ step: SceneStep) -> String {
        switch step.kind {
        case .sound: return L10n.text(store.sounds.first { $0.id == step.soundID }?.name ?? step.soundID)
        case .speech: return step.text
        case .flicker: return (step.hueEffect ?? .ghostFlicker).title
        default: return L10n.value("\(step.seconds, specifier: "%.1f") Sekunden")
        }
    }
    @ViewBuilder var clipInspector: some View {
        if let id = selected, let index = scene.steps.firstIndex(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.value("Clip bearbeiten")).font(.headline); Spacer()
                    Text(L10n.value("Start bei"))
                    TextField(L10n.value("Sekunden"), value: Binding(get: { stepBinding(id).wrappedValue.startTime ?? 0 }, set: { stepBinding(id).wrappedValue.startTime = max(0, min(600, $0)) }), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width: 70)
                    Text("s")
                }
                if scene.steps[index].kind.usesRooms {
                    let ids = scene.steps[index].roomIDs.isEmpty ? scene.roomIDs : scene.steps[index].roomIDs
                    Label(ids.isEmpty ? L10n.value("Noch keine Boxen ausgewählt · oben auswählen") : store.rooms.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", "), systemImage: "hifispeaker.fill").font(.caption).foregroundStyle(ids.isEmpty ? .orange : .secondary)
                }
                if scene.steps[index].kind.usesLights {
                    let ids = scene.steps[index].lightIDs.isEmpty ? scene.lightIDs : scene.steps[index].lightIDs
                    Label(ids.isEmpty ? L10n.value("Noch keine Lichter ausgewählt · oben auswählen") : L10n.value("\(ids.count) Lampen für diesen Clip"), systemImage: "lightbulb.fill").font(.caption).foregroundStyle(ids.isEmpty ? .orange : .secondary)
                }
                HStack {
                    Button(action: duplicateClip) { Label(L10n.value("Duplizieren"), systemImage: "plus.square.on.square") }
                    #if os(macOS)
                    Button(action: copyClip) { Image(systemName: "doc.on.doc") }.help(L10n.value("Clip kopieren"))
                    Button(action: pasteClip) { Image(systemName: "doc.on.clipboard") }.help(L10n.value("Clip einfügen"))
                    #endif
                    Button(role: .destructive, action: deleteClip) { Label(L10n.value("Löschen"), systemImage: "trash") }
                }
                StepCard(store: store, step: stepBinding(id), sceneRoomIDs: scene.roomIDs, sceneLightIDs: scene.lightIDs, number: index + 1, active: runner?.currentStep == id, moveUp: {}, moveDown: {}, remove: { deleteClip() }).id(id)
            }
        }
    }
    var stage: some View { SceneStageView(scene: scene, plan: plan, time: isRunning ? playhead : preview.time, lights: store.lights, live: preview.running || isRunning, hardware: isRunning) }
    var previewControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if isRunning { runner?.stop() }
                else {
                    preview.stop(); showStage = true
                    var test = scene; test.repetitions = 1
                    devicePreviewActive = store.run(test)
                    devicePreviewRunner = devicePreviewActive ? store.playback.runner(for: scene.id) : nil
                }
            } label: {
                Label(isRunning ? L10n.value("Gerätetest stoppen") : L10n.value("Vorschau auf Sonos & Hue"), systemImage: isRunning ? "stop.fill" : "house.fill")
            }.buttonStyle(.borderedProminent).disabled(store.scanning || issue != nil || scene.steps.isEmpty || runner?.stopping == true)
            Text(L10n.value("Spielt einmal auf den gewählten Boxen und Lampen. Danach werden die vorherigen Zustände wiederhergestellt.")).font(.caption).foregroundStyle(.secondary)
            if devicePreviewActive, let runner {
                Text(L10n.text(runner.status)).font(.callout).foregroundStyle(.orange)
                DisclosureGroup(L10n.value("Gerätetest-Protokoll")) {
                    ForEach(Array(runner.log.enumerated()), id: \.offset) { _, entry in Text(L10n.text(entry)).font(.caption) }
                }
            }
            Divider()
            HStack {
                Button { if preview.running || preview.preparing { preview.stop() } else { startPreview() } } label: { Label(preview.preparing ? L10n.value("Vorbereiten …") : preview.running ? "Pause" : L10n.value("Bildschirm-Vorschau"), systemImage: preview.running ? "pause.fill" : "play.fill") }.buttonStyle(.bordered).disabled(isRunning || issue != nil || scene.steps.isEmpty)
                if !preview.running && !preview.preparing && preview.time > 0 && preview.time < plan.duration {
                    Button(L10n.value("Ab hier abspielen")) { startPreview(fromCurrentTime: true) }.disabled(isRunning || issue != nil)
                }
                Button { preview.stop(reset: true) } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel(L10n.value("Vorschau zurücksetzen"))
            }
            Toggle(L10n.value("Mit Ton"), isOn: $audioPreview).toggleStyle(.switch).font(.caption)
            Text(L10n.text(preview.status)).font(.caption).foregroundStyle(.secondary)
            Text(L10n.value("Nur Bildschirm und Ton auf diesem Mac/iPhone. Sonos und Hue bleiben unverändert.")).font(.caption2).foregroundStyle(.secondary)
        }
    }
    func selectClip(_ id: UUID) {
        #if os(macOS)
        clipFocusRequest += 1
        #endif
        selected = id
    }
    func closeStudio() { stopEditorPreview(); if let closeEditor { closeEditor() } else { dismiss() } }
    func stepBinding(_ id: UUID) -> Binding<SceneStep> {
        let fallback = scene.steps.first { $0.id == id } ?? SceneStep(kind: .wait)
        return Binding(get: { scene.steps.first { $0.id == id } ?? fallback }, set: { value in
            if let index = scene.steps.firstIndex(where: { $0.id == id }) { scene.steps[index] = value }
        })
    }
    func deleteClip() {
        guard let selected, let index = scene.steps.firstIndex(where: { $0.id == selected }) else { return }
        scene.steps.remove(at: index)
        if scene.steps.isEmpty { self.selected = nil; clipFocusRequest += 1 }
        else { selectClip(scene.steps[min(index, scene.steps.count - 1)].id) }
    }
    func duplicateClip() {
        guard let selected, let entry = plan.entries.first(where: { $0.id == selected }) else { return }
        appendClip(entry.step, at: entry.end)
    }
    func appendClip(_ original: SceneStep, at time: Double) {
        let copy = original.copied(startingAt: time)
        var updated = scene; updated.steps.append(copy)
        do { try SceneTimeline(scene: updated, soundDurations: durations).validate(scene: updated) }
        catch { store.error = error.localizedDescription; return }
        scene = updated; selectClip(copy.id)
    }
    #if os(macOS)
    private static let clipType = NSPasteboard.PasteboardType("de.hamann.haunt.scene-clip")
    func copyClip() {
        guard let selected, let step = scene.steps.first(where: { $0.id == selected }), let data = try? JSONEncoder().encode(step) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: Self.clipType)
    }
    func pasteClip() {
        guard let data = NSPasteboard.general.data(forType: Self.clipType), let step = try? JSONDecoder().decode(SceneStep.self, from: data) else { return }
        let end = plan.entries.first { $0.id == selected }?.end ?? insertionTime
        appendClip(step, at: end)
    }
    #endif
    func stopEditorPreview() { preview.stop(); if devicePreviewActive { runner?.stop() } }
    func startPreview(fromCurrentTime: Bool = false) { devicePreviewActive = false; showStage = true; store.stopPreview(); preview.start(scene: scene, sounds: Dictionary(uniqueKeysWithValues: store.sounds.map { ($0.id, store.soundURL($0)) }), durations: durations, audio: audioPreview, folder: store.directory, fromCurrentTime: fromCurrentTime) }
    func insertCombo(_ combo: HorrorScene) {
        preview.stop(); let offset = scene.steps.isEmpty ? preview.time : max(preview.time, plan.duration)
        for var step in combo.steps { step.id = UUID(); step.startTime = offset + (step.startTime ?? 0); scene.steps.append(step); selected = step.id }
    }
    func insertEffect(_ effect: HueEffectKind) { var step = SceneStep(kind: .flicker, seconds: 12); step.startTime = insertionTime; step.hueEffect = effect; step.hue = effect.defaultHue; scene.steps.append(step); selected = step.id }
    func insertStep(_ kind: StepKind) { var step = SceneStep(kind: kind); if kind == .speech { step.speechLanguage = L10n.speechLanguage }; step.startTime = insertionTime; scene.steps.append(step); selected = step.id }
    @discardableResult func save() -> Bool { store.saveScene(scene) }
}
struct RoomPicker: View {
    @ObservedObject var store: AppStore
    @Binding var selection: Set<String>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.rooms.isEmpty { Text(L10n.value("Noch keine Räume gefunden. Unter Geräte das Netzwerk durchsuchen.")).foregroundStyle(.secondary) }
            else { HStack { Button(L10n.value("Alle")) { selection = Set(store.rooms.map(\.id)) }; Button(L10n.value("Keine")) { selection.removeAll() } }.font(.caption) }
            ForEach(store.rooms) { room in
                Toggle(isOn: Binding(get: { selection.contains(room.id) }, set: { if $0 { selection.insert(room.id) } else { selection.remove(room.id) } })) {
                    VStack(alignment: .leading) { Text(room.name); let satellites = store.speakers.filter { $0.parentID == room.id }; Text(satellites.isEmpty ? room.model : L10n.value("\(room.model) + \(satellites.count) verbundene Lautsprecher")).font(.caption).foregroundStyle(.secondary) }
                }.toggleStyle(.checkboxCompat)
            }
            let missing = selection.subtracting(Set(store.rooms.map(\.id)))
            if !missing.isEmpty { Text(L10n.value("\(missing.count) gespeicherte Räume derzeit nicht gefunden.")).font(.caption).foregroundStyle(.orange); Button(L10n.value("Nicht erreichbare Auswahl entfernen")) { selection.subtract(missing) } }
        }
    }
}
struct LightPicker: View {
    @ObservedObject var store: AppStore
    @Binding var selection: Set<String>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.lights.isEmpty { Text(L10n.value("Unter Geräte die Hue-Bridge koppeln. Dann erscheinen hier deine Lampen.")).foregroundStyle(.secondary) }
            else { HStack { Button(L10n.value("Alle")) { selection = Set(store.lights.filter(\.reachable).map(\.id)) }; Button(L10n.value("Keine")) { selection.removeAll() } }.font(.caption) }
            ForEach(store.bridges) { bridge in
                BridgeLightPicker(store: store, bridge: bridge, selection: $selection)
            }
            let missing = selection.subtracting(Set(store.lights.map(\.id)))
            if !missing.isEmpty { Text(L10n.value("\(missing.count) gespeicherte Lampen derzeit nicht gefunden.")).font(.caption).foregroundStyle(.orange); Button(L10n.value("Nicht erreichbare Auswahl entfernen")) { selection.subtract(missing) } }
        }
    }
}
struct CheckboxCompat: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { HStack { Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square").foregroundStyle(configuration.isOn ? Color.orange : Color.secondary); configuration.label; Spacer() }.contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}
extension ToggleStyle where Self == CheckboxCompat { static var checkboxCompat: CheckboxCompat { CheckboxCompat() } }
