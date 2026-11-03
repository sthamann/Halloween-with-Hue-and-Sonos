import SwiftUI
import HalloweenCore

struct SoundCreditsView: View {
    let sounds: [SoundClip]
    @Environment(\.dismiss) private var dismiss
    var licensed: [SoundClip] { sounds.filter { $0.builtIn && $0.credit != nil } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.value("\(licensed.count) Halloween-Aufnahmen sind unter CC0 1.0 freigegeben und offline in Haunt enthalten. Dazu kommen sechs für Haunt erzeugte Effekte."))
                    Text(L10n.value("CC0 erlaubt Kopieren, Bearbeiten und Weitergeben, auch für kommerzielle Projekte. Die Urheber und Originalquellen sind hier dokumentiert.")).font(.callout).foregroundStyle(.secondary)
                    Link(L10n.value("CC0 1.0 lesen"), destination: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!)
                }
                ForEach(licensed) { clip in
                    if let credit = clip.credit {
                        Section(clip.name) {
                            Text("\(credit.author) · \(credit.license)")
                            if let source = URL(string: credit.sourceURL), source.scheme == "https" { Link(L10n.value("Originalquelle öffnen"), destination: source) }
                        }
                    }
                }
                Section(L10n.value("Eigene Imports")) { Text(L10n.value("Für selbst importierte Audiodateien wird keine Lizenzfreigabe durch Haunt behauptet.")).font(.callout).foregroundStyle(.secondary) }
            }.navigationTitle(L10n.value("Quellen & Lizenzen"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.value("Schließen")) { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 600)
        #endif
    }
}
