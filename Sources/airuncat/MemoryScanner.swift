import Foundation

// MARK: - Models

enum MemoryType: String, Sendable, CaseIterable {
    case user, feedback, project, reference, unknown

    static var allCasesOrdered: [MemoryType] { [.user, .feedback, .project, .reference, .unknown] }
}

struct MemoryRecord: Identifiable, Sendable {
    let id: String          // name from frontmatter, or file stem
    let description: String
    let type: MemoryType
    let path: String
    let mtime: Date
}

// MARK: - Scanner

enum MemoryScanner {

    // Memory dir is derived directly from the session's jsonl path.
    // This avoids re-implementing Claude Code's internal cwd encoding rules.
    static func memoryDir(forJsonl jsonlPath: String) -> String {
        let parent = (jsonlPath as NSString).deletingLastPathComponent
        return (parent as NSString).appendingPathComponent("memory")
    }

    // Cheap count for badge display — no file content reads
    static func count(forJsonl jsonlPath: String) -> Int {
        let dir = memoryDir(forJsonl: jsonlPath)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return 0 }
        return items.filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }.count
    }

    // Full scan — called on popover open (priority: .userInitiated)
    static func scan(forJsonl jsonlPath: String) -> [MemoryRecord] {
        let dir = memoryDir(forJsonl: jsonlPath)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return items
            .filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }
            .compactMap { filename -> MemoryRecord? in
                let path = (dir as NSString).appendingPathComponent(filename)
                return parseRecord(path: path)
            }
            .sorted { $0.mtime > $1.mtime }
    }

    // MARK: - Frontmatter parsing

    private static func parseRecord(path: String) -> MemoryRecord? {
        let fileMtime = FileIOHelper.mtime(at: path)

        let stem = String((path as NSString).lastPathComponent.dropLast(3))

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return MemoryRecord(id: stem, description: "", type: .unknown, path: path, mtime: fileMtime)
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return MemoryRecord(id: stem, description: "", type: .unknown, path: path, mtime: fileMtime)
        }

        var name = stem
        var description = ""
        var type: MemoryType = .unknown
        var inFrontmatter = false
        var inMetadata = false

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inFrontmatter { break }
                inFrontmatter = true
                continue
            }
            guard inFrontmatter else { continue }

            if line.hasPrefix("metadata:") {
                inMetadata = true
                continue
            }

            if inMetadata {
                // Nested keys use 2-space indent
                if line.hasPrefix("  ") {
                    let stripped = line.trimmingCharacters(in: .whitespaces)
                    if stripped.hasPrefix("type:") {
                        let val = stripped.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        type = MemoryType(rawValue: val) ?? .unknown
                    }
                } else {
                    inMetadata = false
                }
            }

            if trimmed.hasPrefix("name:") {
                name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if trimmed.hasPrefix("description:") {
                description = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if trimmed.hasPrefix("type:") && !inMetadata {
                // Top-level type fallback (when metadata block absent)
                let val = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if type == .unknown { type = MemoryType(rawValue: val) ?? .unknown }
            }
        }

        return MemoryRecord(id: name, description: description, type: type, path: path, mtime: fileMtime)
    }
}
