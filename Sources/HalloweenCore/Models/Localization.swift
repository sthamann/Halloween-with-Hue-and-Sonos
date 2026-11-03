import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, german = "de", english = "en"
    public var id: String { rawValue }
    public var title: String { switch self { case .system: return "System"; case .german: return "Deutsch"; case .english: return "English" } }
}
public enum L10n {
    public static var language: AppLanguage = .german
    public static var isEnglish: Bool { language == .english || (language == .system && !(Locale.preferredLanguages.first ?? "en").hasPrefix("de")) }
    public static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "de_DE") }
    public static var speechLanguage: String { isEnglish ? "en-US" : "de-DE" }
    public static func text(_ value: String) -> String {
        if isEnglish { return translations[value] ?? uxTranslations[value] ?? value }
        // Status messages may have been created before an in-app language change.
        return translations.first(where: { $0.value == value })?.key ?? uxTranslations.first(where: { $0.value == value })?.key ?? value
    }
    public static func value(_ value: LocalizedValue) -> String {
        let parts = text(value.key).components(separatedBy: "%@")
        var result = parts[0]
        for index in 1..<parts.count {
            result += index <= value.arguments.count ? value.arguments[index - 1] : "%@"
            result += parts[index]
        }
        return result
    }
}
public struct LocalizedValue: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public var key: String; public var arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""; var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
        public mutating func appendInterpolation(_ value: Double, specifier: String) { key += "%@"; arguments.append(String(format: specifier, locale: L10n.locale, value)) }
        public mutating func appendInterpolation(_ value: Float, specifier: String) { appendInterpolation(Double(value), specifier: specifier) }
    }
}
