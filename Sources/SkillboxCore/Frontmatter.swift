import Foundation

/// Parsed YAML frontmatter of a SKILL.md file.
///
/// The parser is intentionally small: it handles the scalar/list/nested-map
/// subset that real SKILL.md files use, without pulling in a YAML library.
public struct Frontmatter: Sendable, Equatable {
    /// Top-level scalar fields, e.g. `name`, `description`, `author`, `license`.
    public var fields: [String: String]
    /// `tags: [a, b]` or a `tags:` block list.
    public var tags: [String]
    /// Nested `metadata:` map, flattened to `key -> value`.
    public var metadata: [String: String]
    /// The document body with the frontmatter block removed.
    public var body: String

    public init(
        fields: [String: String] = [:],
        tags: [String] = [],
        metadata: [String: String] = [:],
        body: String = ""
    ) {
        self.fields = fields
        self.tags = tags
        self.metadata = metadata
        self.body = body
    }

    public subscript(field: String) -> String? { fields[field] }
}

public enum FrontmatterParser {
    /// Splits `text` into frontmatter and body. Text without a leading `---`
    /// block yields empty metadata and the full text as the body.
    public static func parse(_ text: String) -> Frontmatter {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return Frontmatter(body: text)
        }

        var closingIndex: Int?
        var index = 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                closingIndex = index
                break
            }
            index += 1
        }
        guard let close = closingIndex else {
            // Unterminated block: treat the whole document as body.
            return Frontmatter(body: text)
        }

        let block = Array(lines[1..<close])
        let body = lines[(close + 1)...].joined(separator: "\n")

        var fields: [String: String] = [:]
        var tags: [String] = []
        var metadata: [String: String] = [:]

        var currentTopKey: String?
        var currentListKey: String?
        var currentList: [String] = []
        var inMetadata = false
        var pendingFoldedKey: String?
        var foldedValue = ""

        func flushList() {
            guard let key = currentListKey, !currentList.isEmpty else {
                currentListKey = nil
                currentList = []
                return
            }
            if key == "tags" {
                tags = currentList
            } else {
                fields[key] = currentList.joined(separator: ", ")
            }
            currentListKey = nil
            currentList = []
        }

        func flushFolded() {
            guard let key = pendingFoldedKey else { return }
            let value = foldedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if inMetadata {
                metadata[key] = value
            } else {
                fields[key] = value
            }
            pendingFoldedKey = nil
            foldedValue = ""
        }

        for rawLine in block {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let indent = line.prefix { $0 == " " }.count
            let isTopLevel = indent == 0

            if isTopLevel {
                flushList()
                flushFolded()
                inMetadata = false
                currentTopKey = nil

                guard let colon = trimmed.firstIndex(of: ":") else { continue }
                let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

                if value == ">" || value == "|" || value == ">-" || value == "|-" {
                    pendingFoldedKey = key
                    foldedValue = ""
                    continue
                }

                if value.isEmpty {
                    if key == "metadata" {
                        inMetadata = true
                    } else {
                        currentListKey = key
                        currentList = []
                    }
                    currentTopKey = key
                    continue
                }

                currentTopKey = key
                value = unquote(value)

                if value.hasPrefix("["), value.hasSuffix("]") {
                    let inner = value.dropFirst().dropLast()
                    let items = inner.split(separator: ",").map {
                        unquote($0.trimmingCharacters(in: .whitespaces))
                    }.filter { !$0.isEmpty }
                    if key == "tags" { tags = items } else { fields[key] = items.joined(separator: ", ") }
                } else {
                    fields[key] = value
                }
                continue
            }

            // Indented line.
            if pendingFoldedKey != nil {
                foldedValue += (foldedValue.isEmpty ? "" : " ") + trimmed
                continue
            }

            if trimmed.hasPrefix("- ") {
                let item = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                if currentListKey != nil { currentList.append(item) }
                continue
            }

            if inMetadata, let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = unquote(String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                metadata[key] = value
                continue
            }

            // Continuation of a previously opened list key.
            if currentListKey != nil, currentTopKey != nil { continue }
        }

        flushList()
        flushFolded()

        return Frontmatter(fields: fields, tags: tags, metadata: metadata, body: body)
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
