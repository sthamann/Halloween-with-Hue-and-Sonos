import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class XMLNode {
    let name: String; let attributes: [String: String]; var text = ""; var children: [XMLNode] = []
    init(_ name: String, _ attributes: [String: String] = [:]) { self.name = name.components(separatedBy: ":").last!; self.attributes = attributes }
    func all(_ name: String) -> [XMLNode] { (self.name == name ? [self] : []) + children.flatMap { $0.all(name) } }
    func value(_ name: String) -> String { all(name).first?.text ?? "" }
}
final class XMLTree: NSObject, XMLParserDelegate {
    var root: XMLNode?; var stack: [XMLNode] = []
    static func parse(_ data: Data) throws -> XMLNode {
        let delegate = XMLTree(); let parser = XMLParser(data: data); parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw AppFailure(L10n.value("Das Gerät lieferte ungültige XML-Daten.")) }; return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let node = XMLNode(elementName, attributes); if let parent = stack.last { parent.children.append(node) } else { root = node }; stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
}
func xmlEscape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
