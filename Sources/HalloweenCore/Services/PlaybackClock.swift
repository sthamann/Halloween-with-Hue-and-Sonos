import Foundation

/// A scene's elapsed time excludes pauses. Every cue and audio deadline uses this clock.
@MainActor public final class PlaybackClock {
    private var origin = ContinuousClock.now
    private var pausedAt: ContinuousClock.Instant?
    private var pausedDuration = 0.0
    public init() {}
    public var elapsed: Double {
        let components = origin.duration(to: pausedAt ?? .now).components
        return max(0, Double(components.seconds) + Double(components.attoseconds) / 1e18 - pausedDuration)
    }
    public func reset(paused: Bool = false) { origin = .now; pausedDuration = 0; pausedAt = paused ? origin : nil }
    public func pause() { if pausedAt == nil { pausedAt = .now } }
    public func resume() {
        if let start = pausedAt { let c = start.duration(to: .now).components; pausedDuration += Double(c.seconds) + Double(c.attoseconds) / 1e18; pausedAt = nil }
    }
    public func checkpoint() async throws {
        try Task.checkCancellation()
        while pausedAt != nil { try await Task.sleep(for: .milliseconds(30)); try Task.checkCancellation() }
    }
    public func wait(until target: Double) async throws {
        while true {
            try await checkpoint()
            let remaining = target - elapsed
            if remaining <= 0 { return }
            try await Task.sleep(for: .seconds(min(0.03, remaining)))
        }
    }
}
