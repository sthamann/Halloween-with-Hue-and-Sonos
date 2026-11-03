import XCTest
@testable import HalloweenCore

final class SceneLibraryTests: XCTestCase {
    @MainActor func testSavingMovesSceneToTopAndPreservesFavoritesThroughReloadAndStaleEditor() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(directory: folder)
        let first = HorrorScene(name: "First")
        let second = HorrorScene(name: "Second")
        XCTAssertTrue(store.saveScene(first, at: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(store.saveScene(second, at: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(store.scenes.map(\.id), [second.id, first.id])
        store.toggleFavorite(first.id)
        XCTAssertEqual(store.scenes.map(\.id), [second.id, first.id], "Starring does not pretend the scene was edited")
        XCTAssertTrue(store.saveScene(first, at: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(store.scenes.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.favoriteScenes.map(\.id), [first.id], "Saving an old editor copy preserves the current favorite")
        let restored = AppStore(directory: folder)
        XCTAssertEqual(restored.scenes.map(\.id), [first.id, second.id])
        XCTAssertEqual(restored.favoriteScenes.map(\.id), [first.id])
        restored.toggleFavorite(first.id)
        XCTAssertTrue(restored.favoriteScenes.isEmpty)
        XCTAssertEqual(restored.scenes[0].updatedAt, Date(timeIntervalSince1970: 300))
    }
    func testLegacyScenesWithoutMetadataStillDecodeAndKeepStableOrder() throws {
        let scenes = [HorrorScene(name: "Old A"), HorrorScene(name: "Old B")]
        let data = try JSONEncoder().encode(scenes)
        let decoded = try JSONDecoder().decode([HorrorScene].self, from: data)
        XCTAssertTrue(decoded.allSatisfy { $0.updatedAt == nil && $0.isFavorite == nil })
        XCTAssertEqual(SceneLibrary.sorted(decoded).map(\.id), scenes.map(\.id))
    }
    @MainActor func testImportedSceneGetsNewSaveDateAndDoesNotAdoptForeignFavoriteFlag() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(directory: folder)
        XCTAssertTrue(store.saveScene(HorrorScene(name: "Existing"), at: Date(timeIntervalSince1970: 100)))
        var incoming = HorrorScene(name: "Imported", steps: [SceneStep(kind: .wait)])
        incoming.isFavorite = true; incoming.updatedAt = Date(timeIntervalSince1970: 10)
        let imported = try store.importArchive(JSONEncoder().encode(SceneArchive(scene: incoming)))
        XCTAssertEqual(store.scenes.first?.id, imported.id)
        XCTAssertNotEqual(imported.id, incoming.id)
        XCTAssertEqual(imported.isFavorite, false)
        XCTAssertNotNil(imported.updatedAt)
    }
}
