import SwiftUI
import HalloweenCore
#if os(macOS)
import AppKit
#endif

struct TimelineCanvas: View {
    @Binding var scene: HorrorScene
    let plan: SceneTimeline
    let sounds: [SoundClip]
    @Binding var selected: UUID?
    let playhead: Double
    let scrub: (Double) -> Void
    @State private var zoom = 28.0
    var width: CGFloat { CGFloat(max(30, plan.duration + 5) * zoom) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.value("ZEITLEISTE"), systemImage: "film.stack").font(.caption.bold()).tracking(2)
                Spacer()
                Text("\(playhead, specifier: "%.1f") / \(plan.duration, specifier: "%.1f") s").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                Button { zoom = max(12, zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel(L10n.value("Zeitleiste verkleinern"))
                Button { zoom = min(80, zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel(L10n.value("Zeitleiste vergrößern"))
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(Array(stride(from: 0, through: Int(ceil(Double(width) / zoom)), by: zoom < 20 ? 10 : 5)), id: \.self) { second in
                                Text("\(second)s").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: CGFloat((zoom < 20 ? 10 : 5) * zoom), alignment: .leading)
                            }
                        }
                        Rectangle().fill(.orange).frame(width: 2, height: 23).offset(x: CGFloat(playhead * zoom))
                    }.frame(width: width, height: 26, alignment: .leading).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { scrub(Double($0.location.x) / zoom) })
                    ForEach(plan.entries.contains { $0.step.kind == .wait } ? [0, 1, 2, 3] : [0, 1, 2], id: \.self) { lane in
                        TimelineLane(scene: $scene, sounds: sounds, entries: plan.entries.filter { laneFor($0.step.kind) == lane }, selected: $selected, zoom: zoom, width: width, title: [L10n.value("SOUND"), L10n.value("STIMME"), L10n.value("HUE-LICHT"), L10n.value("PAUSEN")][lane], tint: [.orange, .purple, .cyan, .gray][lane], playhead: playhead)
                    }
                }.coordinateSpace(name: "hauntTimeline")
            }.background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            if plan.entries.contains(where: \.estimatedDuration) { Text(L10n.value("~ Stimmendauer geschätzt · mit Ton wird die tatsächliche Dauer vorbereitet.")).font(.caption2).foregroundStyle(.secondary) }
            Text(L10n.value("Clips ziehen = Startzeit ändern · rechten Griff ziehen = Clip-Dauer ändern · Skala antippen = Vorschauposition")).font(.caption).foregroundStyle(.secondary)
        }.hauntedCard()
    }
    func laneFor(_ kind: StepKind) -> Int { kind == .sound ? 0 : kind == .speech ? 1 : kind.usesLights ? 2 : 3 }
}
private struct TimelineLane: View {
    @Binding var scene: HorrorScene
    let sounds: [SoundClip]
    let entries: [TimelineEntry]
    @Binding var selected: UUID?
    let zoom: Double; let width: CGFloat; let title: String; let tint: Color; let playhead: Double
    var placements: [(entry: TimelineEntry, row: Int)] {
        var ends: [Double] = []; var result: [(TimelineEntry, Int)] = []
        for entry in entries { let row = ends.firstIndex(where: { $0 <= entry.start + 0.001 }) ?? ends.count; if row == ends.count { ends.append(entry.end) } else { ends[row] = entry.end }; result.append((entry, row)) }
        return result
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.045))
            Text(L10n.text(title)).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(tint.opacity(0.8)).padding(.leading, 8).padding(.top, 6)
            ForEach(Array(stride(from: 0, through: Int(Double(width) / zoom), by: 5)), id: \.self) { second in Rectangle().fill(.white.opacity(0.05)).frame(width: 1).offset(x: CGFloat(Double(second) * zoom)) }
            ForEach(placements, id: \.entry.id) { item in
                let entry = item.entry
                TimelineClip(entry: entry, title: label(entry.step), tint: tint, zoom: zoom, row: item.row,
                             selected: selected == entry.id, maxDuration: entry.step.kind == .sound ? (sounds.first { $0.id == entry.step.soundID }?.duration ?? entry.duration) : entry.step.kind == .speech ? SceneTimeline.estimatedSpeechDuration(entry.step.text) : 600, select: { selected = entry.id }) { start, duration in
                    update(entry.id) {
                        $0.startTime = start
                        if let duration { if $0.kind.usesRooms { $0.audioDuration = duration } else { $0.seconds = duration } }
                    }
                }

            }
            Rectangle().fill(.orange).frame(width: 2).offset(x: CGFloat(playhead * zoom)).allowsHitTesting(false)
        }.frame(width: width, height: CGFloat(30 + max(1, (placements.map(\.row).max() ?? 0) + 1) * 59))
    }
    func update(_ id: UUID, _ change: (inout SceneStep) -> Void) { if let index = scene.steps.firstIndex(where: { $0.id == id }) { change(&scene.steps[index]) } }
    func label(_ step: SceneStep) -> String { step.hueEffect?.title ?? (step.kind == .speech ? step.text : step.kind == .sound ? L10n.text(sounds.first { $0.id == step.soundID }?.name ?? L10n.value("Sound fehlt")) : step.kind.title) }
}

private struct TimelineClip: View {
    let entry: TimelineEntry
    let title: String
    let tint: Color
    let zoom: Double
    let row: Int
    let selected: Bool
    let maxDuration: Double
    let select: () -> Void
    let commit: (Double, Double?) -> Void
    @GestureState private var moveDelta = 0.0
    @GestureState private var lengthDelta = 0.0
    var start: Double { max(0, min(600, entry.start + moveDelta)) }
    var duration: Double { max(0.1, min(maxDuration, entry.duration + lengthDelta)) }
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: entry.step.hueEffect?.symbol ?? entry.step.kind.symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption.bold()).lineLimit(1)
                    Text("\(start, specifier: "%.1f")s · \(duration, specifier: "%.1f")s").font(.caption2.monospacedDigit()).opacity(0.8).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.leading, 10).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                .onTapGesture(perform: select)
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("hauntTimeline"))
                    .updating($moveDelta) { value, delta, _ in delta = value.translation.width / zoom }
                    .onChanged { _ in if !selected { select() }; cursor(.closedHand) }
                    .onEnded { value in commit(max(0, min(600, ((entry.start + value.translation.width / zoom) * 10).rounded() / 10)), nil); cursor(.openHand) })
                .onContinuousHover { phase in switch phase { case .active: cursor(.openHand); case .ended: cursor(.arrow) } }
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.12))
                Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold))
            }.frame(width: 26).padding(.vertical, 4).padding(.trailing, 3).contentShape(Rectangle())
                .onContinuousHover { phase in switch phase { case .active: cursor(.resize); case .ended: cursor(.arrow) } }
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("hauntTimeline"))
                    .updating($lengthDelta) { value, delta, _ in delta = value.translation.width / zoom }
                    .onChanged { _ in if !selected { select() }; cursor(.resize) }
                    .onEnded { value in commit(entry.start, max(0.1, min(maxDuration, ((entry.duration + value.translation.width / zoom) * 10).rounded() / 10))); cursor(.resize) })
                .help(L10n.value("Dauer ändern · rechten Griff ziehen"))
        }.frame(width: max(70, CGFloat(duration * zoom)), height: 54)
            .background(tint.opacity(selected ? 0.55 : 0.23), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? tint : tint.opacity(0.25), lineWidth: 1))
            .offset(x: CGFloat(start * zoom), y: CGFloat(24 + row * 59))
            .accessibilityLabel(L10n.value("\(title), Start \(start) Sekunden"))
            .onDisappear { cursor(.arrow) }
    }
    enum Pointer { case arrow, openHand, closedHand, resize }
    func cursor(_ pointer: Pointer) {
        #if os(macOS)
        switch pointer { case .arrow: NSCursor.arrow.set(); case .openHand: NSCursor.openHand.set(); case .closedHand: NSCursor.closedHand.set(); case .resize: NSCursor.resizeLeftRight.set() }
        #endif
    }
}
