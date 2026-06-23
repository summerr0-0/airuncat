import Foundation

/// Parses YAML-like frontmatter delimited by `---` blocks.
///
/// Supports scalar strings, booleans, inline arrays `[a, b]`, block sequences,
/// and quoted strings. Used by PromptScanner, SkillScanner, MemoryScanner, and HarnessScanner.
enum FrontmatterParser {

    // MARK: - Full parse

    /// Splits `text` into (frontmatter fields, body). Returns `([:], text)` when no valid block.
    static func parse(_ text: String) -> (fields: [String: Any], body: String) {
        guard text.hasPrefix("---") else { return ([:], text) }
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return ([:], text) }
        var endIdx = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" { endIdx = i; break }
        }
        guard endIdx > 0 else { return ([:], text) }
        var body = lines[(endIdx + 1)...].joined(separator: "\n")
        while body.hasPrefix("\n") { body = String(body.dropFirst()) }
        return (parseYAML(Array(lines[1..<endIdx])), body)
    }

    // MARK: - Lightweight single-field reads

    /// Reads only the `description:` value — skips a full YAML parse.
    static func description(atPath path: String) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        return descriptionFromContent(content)
    }

    static func descriptionFromContent(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return "" }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if line.hasPrefix("description:") {
                return line.dropFirst("description:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return ""
    }

    // MARK: - YAML parser

    static func parseYAML(_ lines: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { i += 1; continue }
            guard let colonRange = line.range(of: ":") else { i += 1; continue }

            let key    = String(line[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            if rawVal.hasPrefix("[") && rawVal.hasSuffix("]") {
                // Inline sequence: [a, b, c]
                let inner = String(rawVal.dropFirst().dropLast())
                result[key] = inner.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                               .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    .filter { !$0.isEmpty }
                i += 1
            } else if rawVal.isEmpty {
                i += 1
                // Peek at the next non-empty line to decide block type
                var j = i
                while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                let peek = j < lines.count ? lines[j] : ""

                if peek.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    // Block sequence:  key:\n  - value
                    var items: [String] = []
                    while i < lines.count {
                        let next = lines[i].trimmingCharacters(in: .whitespaces)
                        if next.hasPrefix("- ") {
                            items.append(String(next.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                            i += 1
                        } else { break }
                    }
                    result[key] = items
                } else if peek.hasPrefix("  ") || peek.hasPrefix("\t") {
                    // Nested dict:  key:\n  nestedKey: value
                    var nested: [String: Any] = [:]
                    while i < lines.count {
                        let rawLine = lines[i]
                        guard rawLine.hasPrefix("  ") || rawLine.hasPrefix("\t") else { break }
                        let stripped = rawLine.trimmingCharacters(in: .whitespaces)
                        guard !stripped.isEmpty, let cr = stripped.range(of: ":") else { i += 1; continue }
                        let nKey = String(stripped[..<cr.lowerBound]).trimmingCharacters(in: .whitespaces)
                        var nVal = String(stripped[cr.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if (nVal.hasPrefix("\"") && nVal.hasSuffix("\"")) ||
                           (nVal.hasPrefix("'")  && nVal.hasSuffix("'")) {
                            nVal = String(nVal.dropFirst().dropLast())
                        }
                        nested[nKey] = nVal
                        i += 1
                    }
                    result[key] = nested
                }
            } else if rawVal == "true" {
                result[key] = true; i += 1
            } else if rawVal == "false" {
                result[key] = false; i += 1
            } else {
                var str = rawVal
                if (str.hasPrefix("\"") && str.hasSuffix("\"")) ||
                   (str.hasPrefix("'")  && str.hasSuffix("'")) {
                    str = String(str.dropFirst().dropLast())
                }
                result[key] = str
                i += 1
            }
        }
        return result
    }
}
