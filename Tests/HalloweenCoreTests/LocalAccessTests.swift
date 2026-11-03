import XCTest
@testable import HalloweenCore
@MainActor final class LocalAccessTests: XCTestCase {
    func testFreshLibraryDoesNotConsumeFreeSlotsWithTemplates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(directory: folder)
        XCTAssertTrue(store.scenes.isEmpty)
        XCTAssertEqual(HorrorScene.presets.count, 3)
    }
}
