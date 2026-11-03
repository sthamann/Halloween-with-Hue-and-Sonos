import Foundation

public struct SoundCredit: Codable, Hashable, Sendable {
    public var author: String
    public var sourceURL: String
    public var license: String
    public var licenseURL: String
}
public struct BundledSound: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var filename: String
    public var symbol: String
    public var category: String
    public var credit: SoundCredit?
    public var sha256: String?
}
public enum SoundLibrary {
    public static let originals: [BundledSound] = [
        ("electric-crackle", L10n.value("Elektrisches Spuk-Knistern"), "bolt.fill"),
        ("heartbeat", L10n.value("Herzschlag im Dunkeln"), "heart.fill"), ("storm", L10n.value("Gewitter"), "cloud.bolt.rain.fill"),
        ("knocks", L10n.value("Klopfen an der Tür"), "door.left.hand.open"), ("ghost", L10n.value("Geisterchor"), "wind"),
        ("laugh", L10n.value("Unheimliches Kichern"), "theatermasks.fill"), ("creak", L10n.value("Die knarrende Tür"), "door.right.hand.open")
    ].map { BundledSound(id: $0.0, name: $0.1, filename: $0.0 + ".wav", symbol: $0.2, category: L10n.value("Eigene Effekte"), credit: nil, sha256: nil) }
    public static func decode(_ data: Data) throws -> [BundledSound] {
        guard data.count < 1_048_576 else { throw AppFailure("Der Soundkatalog ist zu groß.") }
        let entries = try JSONDecoder().decode([BundledSound].self, from: data)
        guard !entries.isEmpty, entries.count <= 500, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && !$0.filename.contains("/") && !$0.filename.contains("\\") && $0.filename.lowercased().hasSuffix(".wav") }) else { throw AppFailure("Der Soundkatalog enthält ungültige Einträge.") }
        return entries
    }
    public static func load(bundle: Bundle) throws -> ([BundledSound], [String: URL]) {
        guard let catalogURL = bundle.url(forResource: "sound-catalog", withExtension: "json", subdirectory: "Sounds") ?? bundle.url(forResource: "sound-catalog", withExtension: "json") else { throw AppFailure("Der eingebaute Soundkatalog fehlt. Bitte die App erneut bauen.") }
        let catalog = try decode(Data(contentsOf: catalogURL))
        var urls: [String: URL] = [:]
        for entry in catalog {
            let stem = String(entry.filename.dropLast(4))
            guard let url = bundle.url(forResource: stem, withExtension: "wav", subdirectory: "Sounds") ?? bundle.url(forResource: stem, withExtension: "wav") else { throw AppFailure("Eingebauter Sound fehlt: \(entry.name)") }
            urls[entry.id] = url
        }
        return (catalog, urls)
    }
}
