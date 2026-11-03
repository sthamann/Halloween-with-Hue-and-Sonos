import SwiftUI
import HalloweenCore

struct EffectShelf: View {
    let addCombo: (HorrorScene) -> Void
    let addEffect: (HueEffectKind) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(L10n.value("Ein Klick. Eine Spukszene.")).font(.title3.bold()); Spacer(); Text(L10n.value("Kombis ans Ende anfügen")).font(.caption).foregroundStyle(.secondary) }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(EffectCombos.scenes) { combo in
                        Button { addCombo(combo) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Image(systemName: combo.symbol).font(.title2).foregroundStyle(.orange); Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(.orange.opacity(0.7)) }
                                Text(combo.name).font(.callout.bold()).foregroundStyle(.primary)
                                Text(combo.steps.contains { $0.kind == .speech } ? L10n.value("Sound + Licht + Spukstimme") : L10n.value("Sound + Hue-Licht")).font(.caption2).foregroundStyle(.secondary)
                            }.padding(16).frame(width: 180, alignment: .leading).background(LinearGradient(colors: [.orange.opacity(0.12), .purple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityLabel(L10n.value("Kombi einfügen: \(combo.name)"))
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) { ForEach(HueEffectKind.allCases) { effect in
                    Button { addEffect(effect) } label: { Label(L10n.text(effect.title), systemImage: effect.symbol).font(.caption).padding(.horizontal, 12).padding(.vertical, 10).background(.cyan.opacity(0.08), in: Capsule()).overlay(Capsule().stroke(.cyan.opacity(0.18))) }.buttonStyle(.plain).help(effect.detail)
                } }
            }
        }
    }
}
