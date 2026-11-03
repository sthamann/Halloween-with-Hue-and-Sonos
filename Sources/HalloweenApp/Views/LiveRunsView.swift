import SwiftUI
import HalloweenCore

struct LiveRunsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var playback: PlaybackCoordinator
    init(store: AppStore) { self.store = store; playback = store.playback }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(eyebrow: L10n.value("Die Nacht läuft"), title: L10n.value("Alles unter Kontrolle."), subtitle: L10n.value("Mehrere Abläufe gleichzeitig. Jeder hat seine eigene Uhr und seine eigenen Geräte."))
                if playback.running {
                    HStack {
                        Button(L10n.value("Alle pausieren")) { playback.pauseAll() }
                        Button(L10n.value("Alle fortsetzen")) { playback.resumeAll() }
                        Button(L10n.value("Alle stoppen"), role: .destructive) { store.stopAll() }
                    }.buttonStyle(.bordered)
                }
                if playback.sessions.isEmpty { ContentUnavailableView(L10n.value("Die Bühne wartet"), systemImage: "play.rectangle", description: Text(L10n.value("Starte einen gespeicherten Ablauf oder aktiviere seine Auslöser."))) }
                ForEach(playback.sessions) { session in RunSessionRow(session: session, playback: playback).hauntedCard() }
                Text(L10n.value("Pausieren hält die Zeitleiste, Sonos und weitere Lichtaktionen an. Lampen behalten ihren aktuellen Zustand. Die Geräte bleiben bis zum Stop oder Ende für diesen Ablauf reserviert.")).font(.caption).foregroundStyle(.secondary)
                Text(L10n.value("Beim Entfernen eines aktiven Laufs werden seine Geräte zuerst wiederhergestellt. Gespeicherte Abläufe löschst du unter Szenen; zugehörige Auslöser werden mit entfernt.")).font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.navigationTitle("Live")
    }
}
struct RunSessionRow: View {
    let session: PlaybackSession
    @ObservedObject var runner: SceneRunner
    let playback: PlaybackCoordinator
    @State private var showLog = false
    init(session: PlaybackSession, playback: PlaybackCoordinator) { self.session = session; runner = session.runner; self.playback = playback }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text(session.scene.name), systemImage: session.scene.symbol).font(.headline)
                Spacer()
                Text(String(format: "%02d:%02d", Int(runner.elapsed) / 60, Int(runner.elapsed) % 60)).font(.caption.monospacedDigit())
            }
            Text(runner.paused ? L10n.value("Pausiert") : L10n.text(runner.status)).font(.caption).foregroundStyle(runner.paused ? .orange : .secondary)
            Text(L10n.value("\(session.resources.rooms.count) Räume · \(session.resources.lights.count) Lampen")).font(.caption).foregroundStyle(.secondary)
            HStack {
                if runner.running {
                    Button { if runner.paused { runner.resume() } else { runner.pause() } } label: { Label(runner.paused ? L10n.value("Fortsetzen") : L10n.value("Pausieren"), systemImage: runner.paused ? "play.fill" : "pause.fill") }.disabled(runner.stopping || runner.controlBusy).accessibilityIdentifier("run-pause-" + session.id.uuidString)
                    Button("Stop", role: .destructive) { runner.stop() }.disabled(runner.stopping).accessibilityIdentifier("run-stop-" + session.id.uuidString)
                }
                Button(L10n.value("Entfernen"), role: .destructive) { playback.remove(session.id) }.disabled(runner.stopping).accessibilityIdentifier("run-remove-" + session.id.uuidString)
                Spacer()
                Button { showLog.toggle() } label: { Image(systemName: "list.bullet.rectangle") }.accessibilityLabel(L10n.value("Ablaufprotokoll"))
            }.buttonStyle(.bordered)
            if showLog { ForEach(Array(runner.log.enumerated()), id: \.offset) { _, line in Text(line).font(.caption) } }
        }
    }
}
