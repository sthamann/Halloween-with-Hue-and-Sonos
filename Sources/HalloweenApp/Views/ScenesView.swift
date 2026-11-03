import SwiftUI
import HalloweenCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SceneFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var archive: SceneArchive
    var scene: HorrorScene { archive.scene }
    init(scene: HorrorScene) { archive = SceneArchive(scene: scene) }
    init(archive: SceneArchive) { self.archive = archive }
    init(configuration: ReadConfiguration) throws { guard let data = configuration.file.regularFileContents, data.count <= 40_000_000 else { throw AppFailure(L10n.value("Ungültige Szenendatei.")) }; archive = try SceneArchive.decode(data) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return FileWrapper(regularFileWithContents: try encoder.encode(archive)) }
}
struct ScenesView: View {
    @ObservedObject var store: AppStore
    @State private var templates = HorrorScene.presets
    @State private var editing: HorrorScene?
    @State private var importing = false
    @State private var showingPrivacy = false
    @State private var exporting = false
    @State private var exportFile = SceneFile(scene: HorrorScene())
    init(store: AppStore) { self.store = store }
    func copySceneURL(_ scene: HorrorScene) {
        let url = "haunt://scene/" + scene.id.uuidString
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string)
        #else
        UIPasteboard.general.string = url
        #endif
    }
    let columns = [GridItem(.adaptive(minimum: 255), spacing: 18)]
    var accessSummary: some View {
        HStack {
            Label(L10n.value("Unbegrenzt Szenen und Stimmen speichern"), systemImage: "square.stack").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button(L10n.text("Datenschutz")) { showingPrivacy = true }.font(.caption)
        }
    }
    var templateLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.value("Vorlagen · zum Loslegen")).font(.title2.bold())
            Text(L10n.value("Vorlagen sind keine gespeicherten Szenen. Erst beim Speichern entsteht deine eigene Szene.")).font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(templates) { preset in
                    Button { editing = preset } label: {
                        VStack(alignment: .leading, spacing: 12) { Label(preset.name, systemImage: preset.symbol).font(.headline); Text(L10n.value("\(preset.steps.count) Clips · Geräte selbst auswählen")).font(.caption).foregroundStyle(.secondary); Label(L10n.value("Vorlage verwenden"), systemImage: "arrow.up.right").font(.caption).foregroundStyle(.orange) }.frame(maxWidth: .infinity, alignment: .leading).hauntedCard()
                    }.buttonStyle(.plain)
                }
            }
            DisclosureGroup(L10n.value("Weitere Effekt-Kombis & Lichteffekte")) {
                EffectShelf(addCombo: { editing = $0 }, addEffect: { effect in
                    var step = SceneStep(kind: .flicker, seconds: 12); step.startTime = 0; step.hueEffect = effect; step.hue = effect.defaultHue
                    editing = HorrorScene(name: effect.title, symbol: effect.symbol, steps: [step])
                }).padding(.top, 12)
            }
        }
    }
    func startOrEdit(_ scene: HorrorScene) {
        let resources = SceneResources(scene: scene)
        if scene.steps.isEmpty || (resources.rooms.isEmpty && resources.lights.isEmpty && scene.steps.contains { $0.kind.usesRooms || $0.kind.usesLights }) { editing = scene }
        else { store.run(scene) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(eyebrow: L10n.value("Deine Spukregie"), title: L10n.value("Szenen, die du verstehst."), subtitle: L10n.value("Boxen und Lichter auswählen. Sound, Stimme und Effekte hinzufügen. Vorschau starten."))
                    GhostMark().frame(width: 68, height: 68)
                }
                HStack {
                    Button { editing = HorrorScene() } label: { Label(L10n.value("Neue Szene"), systemImage: "plus") }.buttonStyle(.borderedProminent)
                    Button { importing = true } label: { Label(L10n.value("Importieren"), systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                }
                accessSummary
                if !store.favoriteScenes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.value("Favoriten · Schnellzugriff"), systemImage: "star.fill").font(.title2.bold()).foregroundStyle(.orange)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.favoriteScenes) { scene in
                                HStack {
                                    Button { editing = scene } label: { Label(L10n.text(scene.name), systemImage: "star.fill").font(.headline).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                                    Button { startOrEdit(scene) } label: { Image(systemName: "play.fill") }.buttonStyle(.borderedProminent).disabled(store.scanning).accessibilityLabel(L10n.value("\(scene.name) starten"))
                                }.hauntedCard()
                            }
                        }
                    }
                }
                Text(L10n.value("Zuletzt gespeichert zuerst")).font(.caption).foregroundStyle(.secondary)
                HStack { Text(L10n.value("Meine Szenen")).font(.title2.bold()); Spacer(); Text(L10n.value("\(store.scenes.count) gespeichert")).font(.caption).foregroundStyle(.secondary) }
                if store.scenes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.value("Deine erste Spukszene")).font(.title3.bold())
                        Text(L10n.value("Starte leer oder wähle unten eine Vorlage. Deine Geräte ordnest du direkt im Editor zu.")).foregroundStyle(.secondary)
                        Button(L10n.value("Szene selbst bauen")) { editing = HorrorScene() }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, alignment: .leading).hauntedCard()
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(store.scenes) { scene in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Group { if scene.symbol.hasPrefix("moon") { GhostMark().frame(width: 34, height: 40) } else { Image(systemName: scene.symbol).font(.system(size: 34)).foregroundStyle(.orange) } }; Spacer(); Button { store.toggleFavorite(scene.id) } label: { Image(systemName: scene.isFavorite == true ? "star.fill" : "star").foregroundStyle(.orange) }.buttonStyle(.plain).help(L10n.value(scene.isFavorite == true ? "Aus Favoriten entfernen" : "Als Favorit markieren")).accessibilityLabel(L10n.value("Favorit: \(scene.name)")); Text(L10n.value("\(scene.steps.count) Clips")).font(.caption).foregroundStyle(.secondary) }
                            Text(L10n.text(scene.name)).font(.title2.bold())
                            Text(store.lastStartLabel(scene.id)).font(.caption).foregroundStyle(.secondary)
                            Text(scene.steps.map { $0.kind.title }.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary).lineLimit(3).frame(height: 38, alignment: .topLeading)
                            HStack { Label(L10n.value("\(scene.roomIDs.count) Räume"), systemImage: "hifispeaker.fill"); Label(L10n.value("\(scene.lightIDs.count) Lampen"), systemImage: "lightbulb.fill") }.font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button { startOrEdit(scene) } label: { Label("Start", systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(store.scanning)
                                Button(L10n.value("Öffnen & bearbeiten")) { editing = scene }.buttonStyle(.bordered)
                                Spacer()
                                Menu { Button(L10n.value("Duplizieren")) { var copy = scene; copy.id = UUID(); copy.isFavorite = false; copy.name += L10n.value(" Kopie"); store.saveScene(copy) }; Button(L10n.value("Exportieren")) { do { exportFile = SceneFile(archive: try store.archive(scene)); exporting = true } catch { store.error = error.localizedDescription } }; Button(L10n.value("Start-URL kopieren")) { copySceneURL(scene) }; Button(L10n.value("Löschen"), role: .destructive) { store.deleteScene(scene.id) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
                            }
                        }.hauntedCard()
                    }
                }
                templateLibrary
                Label(L10n.value("Starte Szenen direkt oder über aktivierte Auslöser. Sounds und Lichteffekte können gleichzeitig laufen."), systemImage: "sparkle").font(.callout).foregroundStyle(.secondary)
                #if os(iOS)
                Label(L10n.value("Während einer Szene die App geöffnet lassen. Beim Wechsel in den Hintergrund wird die Szene gestoppt."), systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
                #endif
            }.padding(26)
        }.navigationTitle(L10n.value("Szenen"))
        .sceneEditor(item: $editing, store: store)
        .sheet(isPresented: $showingPrivacy) { PrivacyView() }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: exportFile.scene.name) { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); editing = try store.importArchive(data) } catch { store.error = error.localizedDescription }
        }
    }
}
