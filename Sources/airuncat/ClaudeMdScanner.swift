import Foundation

// MARK: - Models

struct ClaudeMdEntry: Identifiable, Sendable {
    let id: String       // path (고유)
    let path: String
    let label: String    // "CLAUDE.md", ".claude/CLAUDE.md", "~/.claude/CLAUDE.md"
    let exists: Bool
    let wordCount: Int   // 0 when not yet loaded; populated by scan(cwd:)
    let mtime: Date?     // nil when exists=false
}

struct ClaudeMdInfo: Sendable {
    let globalEntry: ClaudeMdEntry
    let projectEntries: [ClaudeMdEntry]
    var projectExists: Bool { projectEntries.contains { $0.exists } }
}

// MARK: - Scanner

enum ClaudeMdScanner {
    static let globalPath: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/CLAUDE.md")

    // Cheap check for badge prefetch — no file reads, just fileExists
    static func exists(cwd: String) -> Bool {
        let fm = FileManager.default
        let root = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        let sub  = (cwd as NSString).appendingPathComponent(".claude/CLAUDE.md")
        return fm.fileExists(atPath: root) || fm.fileExists(atPath: sub)
    }

    // Full scan with wordCount — called on popover open
    static func scan(cwd: String) -> ClaudeMdInfo {
        let globalEntry = makeEntry(path: globalPath, label: "~/.claude/CLAUDE.md")

        let rootPath = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        let subPath  = (cwd as NSString).appendingPathComponent(".claude/CLAUDE.md")
        let projectEntries = [
            makeEntry(path: rootPath, label: "CLAUDE.md"),
            makeEntry(path: subPath,  label: ".claude/CLAUDE.md"),
        ]

        return ClaudeMdInfo(globalEntry: globalEntry, projectEntries: projectEntries)
    }

    // MARK: - Helpers

    private static func makeEntry(path: String, label: String) -> ClaudeMdEntry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return ClaudeMdEntry(id: path, path: path, label: label, exists: false, wordCount: 0, mtime: nil)
        }
        return ClaudeMdEntry(
            id: path,
            path: path,
            label: label,
            exists: true,
            wordCount: wordCount(path: path),
            mtime: mtime(of: path)
        )
    }

    static func wordCount(path: String) -> Int {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        return content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }

    private static func mtime(of path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
    }
}
