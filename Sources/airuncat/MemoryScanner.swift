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

        let (fields, _) = FrontmatterParser.parse(content)
        guard !fields.isEmpty else {
            return MemoryRecord(id: stem, description: "", type: .unknown, path: path, mtime: fileMtime)
        }

        let name        = (fields["name"]        as? String) ?? stem
        let description = (fields["description"] as? String) ?? ""

        // metadata.type takes precedence; fall back to top-level type
        let typeStr: String
        if let meta = fields["metadata"] as? [String: Any], let t = meta["type"] as? String {
            typeStr = t
        } else {
            typeStr = (fields["type"] as? String) ?? ""
        }

        return MemoryRecord(id: name, description: description,
                            type: MemoryType(rawValue: typeStr) ?? .unknown,
                            path: path, mtime: fileMtime)
    }
}
