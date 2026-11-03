import XCTest
import AVFoundation
import CryptoKit
@testable import HalloweenCore

final class SoundLibraryTests: XCTestCase {
    private var folder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/HalloweenApp/Resources/Sounds")
    }
    private func resources() throws -> ([BundledSound], [String: URL]) {
        let catalog = try SoundLibrary.decode(Data(contentsOf: folder.appendingPathComponent("sound-catalog.json")))
        return (catalog, Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, folder.appendingPathComponent($0.filename)) }))
    }
    @MainActor func testCompleteLibraryDecodesAndLoadsIntoAppAndEveryCC0FileHasMatchingHashAndLicense() throws {
        let (catalog, urls) = try resources()
        XCTAssertEqual(catalog.count, 25)
        XCTAssertEqual(catalog.filter { $0.credit != nil }.count, 18)
        for entry in catalog {
            let data = try Data(contentsOf: urls[entry.id]!); let player = try AVAudioPlayer(contentsOf: urls[entry.id]!)
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), entry.sha256)
            if let credit = entry.credit {
                XCTAssertEqual(credit.license, "CC0 1.0")
                XCTAssertEqual(credit.licenseURL, "https://creativecommons.org/publicdomain/zero/1.0/")
                XCTAssertEqual(URL(string: credit.sourceURL)?.host, "opengameart.org")
                let file = try AVAudioFile(forReading: urls[entry.id]!)
                XCTAssertEqual(file.fileFormat.sampleRate, 44100); XCTAssertEqual(file.fileFormat.channelCount, 1)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
                XCTAssertLessThanOrEqual(samples.map { abs($0) }.max()!, 0.5001)
                XCTAssertGreaterThanOrEqual(player.duration, 2)
            }
        }
        let store = AppStore(); store.configureSounds(urls, catalog: catalog)
        XCTAssertEqual(store.sounds.filter(\.builtIn).count, 25)
        XCTAssertEqual(store.sounds.filter { $0.credit != nil }.count, 18)
        XCTAssertEqual(store.soundURL(store.sounds.first { $0.id == "cc0-ghost-3" }!), urls["cc0-ghost-3"])
    }
    func testImportedSoundsFromPreviousVersionStillDecodeWithoutClaimingCC0() throws {
        let data = Data(#"{"id":"old","name":"Import","filename":"old.mp3","duration":3,"symbol":"waveform","builtIn":false}"#.utf8)
        let clip = try JSONDecoder().decode(SoundClip.self, from: data)
        XCTAssertNil(clip.credit); XCTAssertNil(clip.category); XCTAssertFalse(clip.builtIn)
    }
    func testCatalogRejectsDuplicateIDsAndFileTraversal() throws {
        var catalog = SoundLibrary.originals
        catalog.append(catalog[0]); XCTAssertThrowsError(try SoundLibrary.decode(JSONEncoder().encode(catalog)))
        catalog = SoundLibrary.originals; catalog[0].filename = "../outside.wav"
        XCTAssertThrowsError(try SoundLibrary.decode(JSONEncoder().encode(catalog)))
    }
}
