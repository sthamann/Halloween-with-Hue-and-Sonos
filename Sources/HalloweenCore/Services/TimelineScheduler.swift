import Foundation

@MainActor public enum TimelineScheduler {
    public static func run(_ plan: SceneTimeline, clock: PlaybackClock, action: @escaping @MainActor @Sendable (TimelineEntry) async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for entry in plan.entries {
                group.addTask { @MainActor in try await clock.wait(until: entry.start); try await action(entry) }
            }
            group.addTask { @MainActor in try await clock.wait(until: plan.duration) }
            try await group.waitForAll()
        }
    }
    public static func wait(until target: ContinuousClock.Instant) async throws { try await ContinuousClock().sleep(until: target, tolerance: .milliseconds(10)); try Task.checkCancellation() }
    public static func run(_ plan: SceneTimeline, origin: ContinuousClock.Instant, action: @escaping @MainActor @Sendable (TimelineEntry) async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for entry in plan.entries {
                group.addTask {
                    try await wait(until: origin.advanced(by: .seconds(entry.start)))
                    try await action(entry)
                }
            }
            group.addTask { try await wait(until: origin.advanced(by: .seconds(plan.duration))) }
            try await group.waitForAll()
        }
    }
}
