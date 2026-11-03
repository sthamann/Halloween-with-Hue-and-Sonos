import SwiftUI
import HalloweenCore

struct SceneStageView: View {
    let scene: HorrorScene
    let plan: SceneTimeline
    let time: Double
    let lights: [HueLight]
    let live: Bool
    var hardware = false
    var stageLights: [(String, String)] {
        let ids = scene.lightIDs.union(scene.steps.reduce(into: Set<String>()) { $0.formUnion($1.lightIDs) }).sorted()
        return ids.isEmpty ? [("virtual-1", L10n.value("Bühne links")), ("virtual-2", L10n.value("Bühne Mitte")), ("virtual-3", L10n.value("Bühne rechts"))] : ids.map { id in (id, lights.first { $0.id == id }?.name ?? L10n.value("Gespeicherte Lampe")) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label(L10n.value("LIVE BÜHNE"), systemImage: "eye.fill").font(.caption.bold()).tracking(2); Spacer(); Circle().fill(live ? .green : .secondary).frame(width: 6, height: 6); Text(live ? L10n.value("Vorschau läuft") : L10n.value("Virtuelle Vorschau")).font(.caption).foregroundStyle(.secondary) }
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Color(red: 0.025, green: 0.025, blue: 0.07), .black], startPoint: .top, endPoint: .bottom))
                GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(stageLights, id: \.0) { id, name in
                        let value = lightFrame(id)
                        let color = Color(hue: value.hue / 360, saturation: value.saturation / 100, brightness: 1)
                        VStack(spacing: 12) {
                            ZStack {
                                Ellipse().fill(color.opacity(value.brightness / 130)).frame(width: 100, height: 150).blur(radius: 25)
                                Image(systemName: "lightbulb.fill").font(.system(size: 27)).foregroundStyle(color.opacity(max(0.08, value.brightness / 100))).shadow(color: color.opacity(value.brightness / 100), radius: 20)
                            }.frame(height: 45)
                            Text(name).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        }.frame(width: max(85, (geometry.size.width - 24) / Double(min(6, stageLights.count))))
                        .accessibilityElement(children: .ignore).accessibilityLabel(L10n.value("\(name), \(Int(value.brightness)) Prozent Licht"))
                    }
                }.padding(.horizontal, 12).padding(.bottom, 18)
                }
                }
                VStack { Spacer(); HStack(spacing: 5) { ForEach(0..<35) { index in Capsule().fill(.orange.opacity(activeAudio ? 0.65 : 0.12)).frame(width: 3, height: activeAudio ? CGFloat(3 + 10 * abs(sin(time * 4 + Double(index) * 1.8))) : 3) } }.frame(height: 16).padding(.bottom, 4) }
            }.frame(height: 105)
            HStack { Text(activeNames).font(.caption).foregroundStyle(.secondary).lineLimit(2); Spacer() }
            Text(L10n.value(hardware ? "Zeitleiste · Wiedergabe auf Sonos und Hue" : "Virtuelles Licht · lokale Tonvorschau")).font(.caption2).foregroundStyle(.secondary)
        }.hauntedCard()
    }
    var activeAudio: Bool { plan.entries.contains { $0.step.kind.usesRooms && $0.start <= time && time < $0.end } }
    var activeNames: String {
        let names = plan.entries.filter { $0.start <= time && time < $0.end }.map { $0.step.hueEffect?.title ?? ($0.step.kind == .speech ? "„\($0.step.text)“" : $0.step.kind.title) }
        return names.isEmpty ? L10n.value("Bereit für deinen nächsten Spukmoment") : names.joined(separator: " · ")
    }
    func lightFrame(_ id: String) -> HueEffectFrame {
        let entry = plan.entries.last { entry in
            guard entry.step.kind.usesLights, entry.start <= time else { return false }
            let targets = entry.step.lightIDs.isEmpty ? scene.lightIDs : entry.step.lightIDs
            return targets.contains(id) || (targets.isEmpty && id.hasPrefix("virtual-"))
        }
        guard let entry else { return HueEffectFrame(time: 0, brightness: 8, hue: 230) }
        let step = entry.step
        if step.kind == .blackout { return HueEffectFrame(time: time, brightness: 0, hue: step.hue) }
        let lamp = lights.first { $0.id == id }
        var keptHue = lamp?.currentHue ?? 30
        var keptSaturation = lamp?.currentSaturation ?? 35
        if step.useLampColor == true, let previous = plan.entries.last(where: { earlier in
            guard earlier.start <= entry.start, earlier.step.kind.usesLights, earlier.step.kind != .blackout, earlier.step.useLampColor != true else { return false }
            let targets = earlier.step.lightIDs.isEmpty ? scene.lightIDs : earlier.step.lightIDs
            return targets.contains(id) || (targets.isEmpty && id.hasPrefix("virtual-"))
        }) {
            let old = previous.step
            if old.kind == .flicker {
                let frame = (old.hueEffect ?? .ghostFlicker).sampledFrame(at: min(max(0, entry.start - previous.start), max(0, previous.duration - 0.001)), brightness: old.brightness, hue: old.hue)
                keptHue = frame.hue; keptSaturation = old.saturation ?? frame.saturation
            } else { keptHue = old.hue; keptSaturation = old.saturation ?? 100 }
        }
        let hue = step.useLampColor == true ? keptHue : step.hue
        let saturation = step.useLampColor == true ? keptSaturation : step.saturation
        if step.kind == .flicker {
            var frame = (step.hueEffect ?? .ghostFlicker).sampledFrame(at: min(max(0, time - entry.start), max(0, entry.duration - 0.001)), brightness: step.brightness, hue: hue, seed: HueEffectKind.seed(for: id))
            if let saturation { frame.saturation = saturation }
            return frame
        }
        return HueEffectFrame(time: time, brightness: step.brightness, hue: hue, saturation: saturation ?? 100)
    }
}
