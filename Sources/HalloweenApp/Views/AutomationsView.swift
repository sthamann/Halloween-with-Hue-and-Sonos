import SwiftUI
import HalloweenCore

struct AutomationsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var engine: AutomationEngine
    @State private var editing: AutomationRule?
    @State private var diagnostics = false
    @State private var filter = "all"
    init(store: AppStore) { self.store = store; engine = store.automation }
    var filteredRules: [AutomationRule] { store.rules.filter { filter == "all" || (filter == "active" ? $0.enabled : !$0.enabled) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(eyebrow: "", title: L10n.value("Dann beginnt der Spuk."), subtitle: L10n.value("Wähle eine Szene und den Moment, der sie startet."))
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.automationEnabled ? L10n.value("Automatik läuft") : L10n.value("Automatik pausiert")).font(.headline)
                        Text(store.automationEnabled ? L10n.value("Aktive Auslöser dürfen Szenen starten.") : L10n.value("Keine Szene startet automatisch. Schalte die Automatik und den gewünschten Auslöser ein.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(L10n.value("Automatische Starts aktivieren"), isOn: Binding(get: { store.automationEnabled }, set: { store.setAutomation($0) })).toggleStyle(.switch).labelsHidden().accessibilityLabel(L10n.value("Automatische Starts aktivieren"))
                }.hauntedCard()
                HStack {
                    Button { if let scene = store.scenes.first { editing = AutomationRule(sceneID: scene.id) } } label: { Label(L10n.value("Auslöser hinzufügen"), systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(store.scenes.isEmpty)
                    Button { diagnostics = true } label: { Label(L10n.value("Sensoren live prüfen"), systemImage: "sensor.fill") }.buttonStyle(.bordered)
                    Spacer()
                }
                if store.scenes.isEmpty { Text(L10n.value("Speichere zuerst deine Szene. Danach kannst du sie hier automatisch starten lassen.")).foregroundStyle(.orange) }
                Picker(L10n.value("Auslöser anzeigen"), selection: $filter) { Text(L10n.value("Alle")).tag("all"); Text(L10n.value("Aktiv")).tag("active"); Text(L10n.value("Pausiert")).tag("paused") }.pickerStyle(.segmented).frame(maxWidth: 370)
                if store.rules.isEmpty { ContentUnavailableView(L10n.value("Noch keine automatischen Starts"), systemImage: "sensor.fill", description: Text(L10n.value("Zum Beispiel: Wenn Bewegung im Flur erkannt wird, starte „Da ist jemand“."))) }
                ForEach(filteredRules) { rule in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text(rule.name).font(.headline); Spacer(); Toggle(L10n.value("Aktiv"), isOn: Binding(get: { store.rules.first { $0.id == rule.id }?.enabled ?? false }, set: { value in if let i = store.rules.firstIndex(where: { $0.id == rule.id }) { store.rules[i].enabled = value; store.save() } })).labelsHidden() }
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 5) { Text(L10n.value("WENN")).font(.caption.bold()).foregroundStyle(.orange); Text(summary(rule)).font(.callout) }
                            Image(systemName: "arrow.right").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 5) { Text(L10n.value("DANN")).font(.caption.bold()).foregroundStyle(.orange); Text(L10n.text(store.scenes.first { $0.id == rule.sceneID }?.name ?? L10n.value("Ablauf fehlt"))).font(.callout.bold()) }
                            Spacer()
                        }
                        Text(store.lastStartLabel(rule.id)).font(.caption).foregroundStyle(.secondary)
                        if let eventDate = engine.lastEvents[rule.sourceID] { Text(L10n.value("Letztes Sensorereignis") + ": " + eventDate.formatted(date: .omitted, time: .standard)).font(.caption) }
                        if !rule.enabled { Label(L10n.value("Auslöser deaktiviert"), systemImage: "pause.circle").font(.callout).foregroundStyle(.orange) }
                        if !store.automationEnabled && rule.enabled { Text(L10n.value("Bereit · globale Automatik ist noch pausiert")).font(.caption).foregroundStyle(.secondary) }
                        if rule.kind == .hue, !store.hueInputs.contains(where: { $0.id == rule.sourceID }) { Label(L10n.value("Dieser Hue-Eingang ist derzeit nicht erreichbar."), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                        HStack { Button(L10n.value("Bearbeiten")) { editing = rule }; Button(L10n.value("Löschen"), role: .destructive) { store.rules.removeAll { $0.id == rule.id }; store.save() }; Spacer(); Text(L10n.value("Sperrzeit: \(Int(rule.cooldown)) s")).font(.caption).foregroundStyle(.secondary) }
                    }.hauntedCard()
                }
                DisclosureGroup(L10n.value("Hue-Verbindungen & MotionAware")) {
                    ForEach(store.bridges) { bridge in
                        VStack(alignment: .leading, spacing: 8) { Text(bridge.name).font(.headline); Text(engine.bridgeStatus[bridge.id] ?? store.inputStatus[bridge.id] ?? L10n.value("Noch nicht gelesen")).font(.caption).foregroundStyle(.secondary); MotionAwareStatus(store: store, bridge: bridge) }.padding(.vertical, 10)
                    }
                    Button(L10n.value("Hue-Eingänge aktualisieren")) { Task { await store.refreshInputs() } }
                }.hauntedCard()
                DisclosureGroup(L10n.value("Auslöser-Protokoll")) { ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in Text(line).font(.caption).frame(maxWidth: .infinity, alignment: .leading) } }
                Text(L10n.value("Für automatische Starts Haunt auf einem wachen Mac geöffnet lassen. Auf iPhone und iPad muss die App im Vordergrund bleiben.")).font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.navigationTitle(L10n.value("Auslöser"))
        .sheet(item: $editing) { rule in TriggerEditorView(store: store, rule: rule) }
        .sheet(isPresented: $diagnostics) { HueInputsView(store: store) }
        .task { await store.refreshInputs() }
    }
    func summary(_ rule: AutomationRule) -> String {
        switch rule.kind {
        case .once: return rule.date.formatted(date: .abbreviated, time: .shortened)
        case .time: return String(format: "%02d:%02d", rule.hour, rule.minute) + " · " + rule.weekdays.sorted().map { L10n.locale.calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        case .interval: return L10n.value("Alle \(Int(rule.interval)) Sekunden")
        case .hue: return (store.hueInputs.first { $0.id == rule.sourceID }?.name ?? L10n.value("Hue-Eingang nicht verfügbar")) + " · " + L10n.hueEvent(rule.event)
        }
    }
}
struct TriggerEditorView: View {
    @ObservedObject var store: AppStore
    @State var rule: AutomationRule
    @Environment(\.dismiss) private var dismiss
    @State private var issue: String?
    var time: Binding<Date> { Binding(get: { Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: rule.hour, minute: rule.minute)) ?? Date() }, set: { rule.hour = Calendar.current.component(.hour, from: $0); rule.minute = Calendar.current.component(.minute, from: $0) }) }
    var selectedInput: HueInput? { store.hueInputs.first { $0.id == rule.sourceID } }
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.value("1 · Welche Szene startet?")) {
                TextField(L10n.value("Name des Auslösers"), text: $rule.name)
                Picker(L10n.value("Ablauf"), selection: $rule.sceneID) { ForEach(store.scenes) { scene in Text(L10n.text(scene.name)).tag(scene.id) } }
                }
                Section(L10n.value("2 · Wann startet sie?")) {
                Picker(L10n.value("Start durch"), selection: $rule.kind) { ForEach(TriggerKind.allCases) { kind in Text(L10n.text(kind.title)).tag(kind) } }
                switch rule.kind {
                case .once: DatePicker(L10n.value("Einmal starten am"), selection: $rule.date)
                case .time:
                    DatePicker(L10n.value("Uhrzeit"), selection: time, displayedComponents: .hourAndMinute)
                    ForEach([2,3,4,5,6,7,1], id: \.self) { day in Toggle(L10n.locale.calendar.weekdaySymbols[day - 1], isOn: Binding(get: { rule.weekdays.contains(day) }, set: { if $0 { rule.weekdays.insert(day) } else { rule.weekdays.remove(day) } })) }
                case .interval:
                    DatePicker(L10n.value("Erster Start"), selection: $rule.date)
                    HStack { Text(L10n.value("Abstand in Sekunden")); TextField(L10n.value("Sekunden"), value: $rule.interval, format: .number).frame(width: 100) }
                    Text(L10n.value("Mindestens 10 Sekunden. Abläufe auf unterschiedlichen Geräten laufen parallel; verpasste Starts werden nicht nachgeholt.")).font(.caption).foregroundStyle(.secondary)
                case .hue:
                    ForEach(store.bridges) { bridge in MotionAwareStatus(store: store, bridge: bridge) }
                    Picker(L10n.value("Sensor / Taster"), selection: $rule.sourceID) {
                        Text(L10n.value("Bitte auswählen")).tag("")
                        if !rule.sourceID.isEmpty, selectedInput == nil { Text(L10n.value("Gespeicherter Eingang · offline")).tag(rule.sourceID) }
                        ForEach(store.bridges) { bridge in Section(bridge.name) { ForEach(store.hueInputs.filter { $0.bridgeID == bridge.id }) { input in Text("\(input.name) · \(L10n.hueResource(input.type))").tag(input.id) } } }
                    }
                    Picker(L10n.value("Ereignis"), selection: $rule.event) { ForEach(selectedInput?.events ?? [rule.event], id: \.self) { event in Text(L10n.hueEvent(event)).tag(event) } }
                    if ["dark", "bright"].contains(rule.event) { HStack { Text(L10n.value("Schwelle in Lux")); TextField("Lux", value: $rule.threshold, format: .number) } }
                    Text(L10n.value("MotionAware-Bereiche aus der Hue-App erscheinen mit kompatibler Bridge Pro. Bewegungsmelder, Dimmer, Smart Button, Tap Dial und Wandmodule werden angezeigt, wenn die Bridge passende Eingänge liefert.")).font(.caption).foregroundStyle(.secondary)
                    if store.hueInputs.isEmpty { Text(L10n.value("Kopple eine Hue-Bridge unter Geräte und aktualisiere die Hue-Eingänge.")).foregroundStyle(.orange) }
                    Button(L10n.value("Hue-Eingänge aktualisieren")) { Task { await store.refreshInputs() } }
                }
                }
                Section(L10n.value("3 · Grenzen & Aktivierung")) {
                Toggle(L10n.value("Nur in einem Zeitfenster"), isOn: $rule.windowEnabled)
                if rule.windowEnabled {
                    DatePicker(L10n.value("Von"), selection: windowBinding(start: true), displayedComponents: .hourAndMinute)
                    DatePicker(L10n.value("Bis"), selection: windowBinding(start: false), displayedComponents: .hourAndMinute)
                    Text(L10n.value("Zeitfenster können über Mitternacht gehen.")).font(.caption)
                }
                HStack { Text(L10n.value("Sperrzeit in Sekunden")); TextField(L10n.value("Sekunden"), value: $rule.cooldown, format: .number).frame(width: 100) }
                Toggle(L10n.value("Diesen Auslöser aktivieren"), isOn: $rule.enabled)
                Text(L10n.value("Erst die globale Automatik starten. Unterschiedliche Geräte laufen parallel. Bereits belegte Geräte werden übersprungen.")).font(.caption).foregroundStyle(.secondary)
                if let issue { Text(L10n.text(issue)).foregroundStyle(.orange) }
                }
            }.formStyle(.grouped).navigationTitle(L10n.value("Wenn … dann …"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.value("Schließen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.value("Speichern")) { save() } }
            }
            .onChange(of: rule.sourceID) { _, _ in rule.event = selectedInput?.events.first ?? "motion" }
            .task(id: rule.kind) {
                if rule.kind == .hue { await store.refreshInputs() }
            }
        }
        #if os(macOS)
        .frame(width: 620, height: 740)
        #endif
    }
    func windowBinding(start: Bool) -> Binding<Date> { Binding(get: { let value = start ? rule.windowStart : rule.windowEnd; return Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: value / 60, minute: value % 60)) ?? Date() }, set: { let value = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0); if start { rule.windowStart = value } else { rule.windowEnd = value } }) }
    func save() {
        do { try rule.validate(); guard store.scenes.contains(where: { $0.id == rule.sceneID }) else { throw AppFailure(L10n.value("Ablauf fehlt")) }; if let i = store.rules.firstIndex(where: { $0.id == rule.id }) { store.rules[i] = rule } else { store.rules.append(rule) }; store.save(); dismiss() }
        catch { issue = error.localizedDescription }
    }
}
