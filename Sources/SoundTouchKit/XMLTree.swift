import Foundation

/// A minimal in-memory XML tree. SoundTouch responses are small, so a full
/// tree is simpler to query than streaming the parser events.
struct XMLTree: Sendable, Equatable {
    var name: String
    var attributes: [String: String]
    var children: [XMLTree]
    var text: String

    subscript(attribute: String) -> String? { attributes[attribute] }

    func child(_ name: String) -> XMLTree? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLTree] {
        children.filter { $0.name == name }
    }

    /// Text of a direct child, or nil when the child is missing or empty.
    func text(of name: String) -> String? {
        guard let value = child(name)?.text, !value.isEmpty else { return nil }
        return value
    }

    static func parse(_ data: Data) throws -> XMLTree {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw SoundTouchError.invalidResponse
        }
        return root
    }
}

private final class Builder: NSObject, XMLParserDelegate {
    private var stack: [XMLTree] = []
    var root: XMLTree?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        stack.append(XMLTree(name: elementName, attributes: attributeDict, children: [], text: ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var node = stack.popLast() else { return }
        node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stack.isEmpty {
            root = node
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }
}

/// Escapes a value for use inside an XML attribute or element.
func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
