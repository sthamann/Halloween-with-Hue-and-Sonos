import SwiftUI
import HalloweenCore

enum AppPage: String, CaseIterable, Identifiable {
    case scenes = "Szenen", sounds = "Sounds", devices = "Geräte", automations = "Auslöser", live = "Live"
    var id: String { rawValue }
    var symbol: String { switch self { case .scenes: return "sparkles"; case .sounds: return "waveform"; case .devices: return "hifispeaker.2.fill"; case .automations: return "timer"; case .live: return "play.rectangle.fill" } }
}
struct ContentView: View {
    @ObservedObject var store: AppStore
    @State private var favoriteEditing: HorrorScene?
    @State private var page: AppPage? = .scenes
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { GhostMark().frame(width: 42, height: 48); VStack(alignment: .leading) { Text("HAUNT").font(.title2.bold()); Text(L10n.value("Dein Haus. Deine Spuknacht.")).font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal).padding(.top, 22)
                    List(AppPage.allCases, selection: $page) { item in Label(L10n.text(item.rawValue), systemImage: item.symbol).tag(item) }.listStyle(.sidebar)
                    if !store.favoriteScenes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.value("Favoriten")).font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(store.favoriteScenes.prefix(5)) { scene in
                                Button { favoriteEditing = scene } label: { Label(L10n.text(scene.name), systemImage: "star.fill").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal)
                    }
                    Picker(L10n.value("Sprache / Language"), selection: $store.language) { ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) } }.padding(.horizontal)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.deviceSummary).font(.caption).foregroundStyle(.secondary)
                    }.padding()
                }.navigationSplitViewColumnWidth(min: 220, ideal: 245)
            } detail: {
                VStack(spacing: 0) { RunnerBanner(store: store); pageView(page ?? .scenes) }
            }
            #else
            TabView {
                ForEach(AppPage.allCases) { item in
                    NavigationStack { VStack(spacing: 0) { RunnerBanner(store: store); pageView(item) } }.tabItem { Label(L10n.text(item.rawValue), systemImage: item.symbol) }
                }
            }
            #endif
        }
        .environment(\.locale, L10n.locale)
        .id(store.language.rawValue)
        .sceneEditor(item: $favoriteEditing, store: store)
        .onOpenURL { store.openSceneURL($0) }
        .alert(L10n.value("Hinweis"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            store.setForeground(phase == .active)
            if phase == .background { store.playback.stopAll(); store.stopPreview() }
            #endif
        }
    }
    @ViewBuilder func pageView(_ page: AppPage) -> some View {
        switch page { case .scenes: ScenesView(store: store); case .sounds: SoundsView(store: store); case .devices: DevicesView(store: store); case .automations: AutomationsView(store: store); case .live: LiveRunsView(store: store) }
    }
}
struct RunnerBanner: View {
    @ObservedObject var store: AppStore
    @ObservedObject var playback: PlaybackCoordinator
    init(store: AppStore) { self.store = store; playback = store.playback }
    @State private var showLog = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if playback.running { Image(systemName: "waveform.path").foregroundStyle(.orange) } else { GhostMark().frame(width: 21, height: 25) }
                Text(playback.running ? L10n.value("\(playback.active.count) Abläufe aktiv") : L10n.value("Bereit für die Nacht.")).font(.callout).lineLimit(2)
                Spacer()
                if playback.running { Button(role: .destructive) { store.stopAll() } label: { Label(L10n.value("Alle stoppen"), systemImage: "stop.fill") }.buttonStyle(.borderedProminent) }
                Button { showLog.toggle() } label: { Image(systemName: "list.bullet.rectangle") }.help(L10n.value("Ablaufprotokoll"))
            }.padding(14).background(.thinMaterial)
            if showLog { ScrollView { VStack(spacing: 10) { ForEach(playback.sessions) { session in RunSessionRow(session: session, playback: playback) } }.padding() }.frame(maxHeight: 230) }
        }
    }
}
struct SectionHeading: View {
    let eyebrow: String; let title: String; let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 9) { Text(L10n.text(eyebrow).uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(.orange); Text(L10n.text(title)).font(.largeTitle.bold()); Text(L10n.text(subtitle)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading) }
}
extension View {
    func hauntedCard() -> some View { self.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08))) }
}
