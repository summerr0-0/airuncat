import Foundation

// MARK: - Model

struct PromptRecord: Identifiable {
    let id: String          // file stem, e.g. "PROMPT_ultrawork"
    let title: String
    let tags: [String]
    let category: String
    let pinned: Bool
    let body: String
}

// MARK: - Scanner

enum PromptScanner {
    static let promptsDir = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Obsidian/document/07_Prompts")

    static func scan() -> [PromptRecord] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: promptsDir) else { return [] }
        return items
            .filter { $0.hasPrefix("PROMPT_") && $0.hasSuffix(".md") }
            .sorted()
            .compactMap { filename in
                let stem = String(filename.dropLast(3))
                let path = (promptsDir as NSString).appendingPathComponent(filename)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let (meta, body) = parseFrontmatter(content)
                return PromptRecord(
                    id: stem,
                    title: meta["title"] as? String ?? stem,
                    tags: meta["tags"] as? [String] ?? [],
                    category: meta["category"] as? String ?? "기타",
                    pinned: meta["pinned"] as? Bool ?? false,
                    body: body
                )
            }
    }

    // MARK: - Frontmatter parser

    static func parseFrontmatter(_ text: String) -> (meta: [String: Any], body: String) {
        guard text.hasPrefix("---") else { return ([:], text) }
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return ([:], text) }

        var endIdx = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIdx = i
                break
            }
        }
        guard endIdx > 0 else { return ([:], text) }

        let frontLines = Array(lines[1..<endIdx])
        var body = lines[(endIdx + 1)...].joined(separator: "\n")
        while body.hasPrefix("\n") { body = String(body.dropFirst()) }
        return (parseYAML(frontLines), body)
    }

    private static func parseYAML(_ lines: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { i += 1; continue }
            guard let colonRange = line.range(of: ":") else { i += 1; continue }

            let key = String(line[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            if rawVal.hasPrefix("[") && rawVal.hasSuffix("]") {
                // Flow sequence: tags: [a, b, c]
                let inner = String(rawVal.dropFirst().dropLast())
                let items = inner.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                result[key] = items
                i += 1
            } else if rawVal.isEmpty {
                // Block sequence:
                //   tags:
                //     - a
                //     - b
                var items: [String] = []
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("- ") {
                        items.append(String(next.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else {
                        break
                    }
                }
                result[key] = items
            } else if rawVal == "true" {
                result[key] = true
                i += 1
            } else if rawVal == "false" {
                result[key] = false
                i += 1
            } else {
                var str = rawVal
                if (str.hasPrefix("\"") && str.hasSuffix("\"")) ||
                   (str.hasPrefix("'") && str.hasSuffix("'")) {
                    str = String(str.dropFirst().dropLast())
                }
                result[key] = str
                i += 1
            }
        }
        return result
    }
}
