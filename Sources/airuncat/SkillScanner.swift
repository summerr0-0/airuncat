import Foundation

// MARK: - Models

enum LinkState {
    case linked    // entry exists and target is reachable
    case broken    // symlink exists but target is missing
    case unlinked  // no entry
}

struct SkillRecord: Identifiable {
    let id: String          // kebab-case name (also the display name)
    let description: String
    let obsidianPath: String
    var claudeState: LinkState
    var geminiState: LinkState
    var claudeLinkPath: String   // ~/.claude/commands/<name>.md
    var geminiLinkPath: String   // ~/.gemini/commands/<name>.toml (preferred)
    var claudeError: String?
    var geminiError: String?
}

struct OrphanLink: Identifiable {
    let id: String   // link file name stem
    let path: String // full path of the dangling link
    let kind: OrphanKind
    enum OrphanKind { case claude, gemini }
}

// MARK: - Scanner

enum SkillScanner {
    static let obsidianBase =
        (NSHomeDirectory() as NSString).appendingPathComponent("Obsidian/document/06_AI_Config")
    static let claudeCommandsDir =
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/commands")
    static let geminiCommandsDir =
        (NSHomeDirectory() as NSString).appendingPathComponent(".gemini/commands")

    /// Returns (skill records sorted by name, orphan links found in commands dirs).
    static func scan() -> (skills: [SkillRecord], orphans: [OrphanLink]) {
        let fm = FileManager.default

        // 1. Enumerate SKILL_*.md in Obsidian
        var skillFiles: [String] = []  // absolute paths
        if let items = try? fm.contentsOfDirectory(atPath: obsidianBase) {
            skillFiles = items
                .filter { $0.hasPrefix("SKILL_") && $0.hasSuffix(".md") }
                .map { (obsidianBase as NSString).appendingPathComponent($0) }
        }

        // 2. All existing entries in commands dirs (for orphan detection)
        let claudeEntries = commandPaths(in: claudeCommandsDir)
        let geminiEntries = commandPaths(in: geminiCommandsDir)

        // 3. Build SkillRecord per skill file
        var knownNames = Set<String>()
        var records: [SkillRecord] = []

        for path in skillFiles {
            let fileName = (path as NSString).lastPathComponent  // e.g. SKILL_DAILY_VOCAB.md
            let stem = String(fileName.dropFirst("SKILL_".count).dropLast(".md".count))
            let kebab = stem.lowercased().replacingOccurrences(of: "_", with: "-")

            // Collision detection: first alphabetically wins
            guard !knownNames.contains(kebab) else { continue }
            knownNames.insert(kebab)

            let desc = parseFrontmatterDescription(at: path)

            let claudeLink = (claudeCommandsDir as NSString).appendingPathComponent("\(kebab).md")
            let geminiLink = geminiLinkPath(for: kebab)

            let cState = linkState(at: claudeLink, fm: fm)
            let gState = linkState(at: geminiLink, fm: fm)

            records.append(SkillRecord(
                id: kebab,
                description: desc,
                obsidianPath: path,
                claudeState: cState,
                geminiState: gState,
                claudeLinkPath: claudeLink,
                geminiLinkPath: geminiLink
            ))
        }

        records.sort { $0.id < $1.id }

        // 4. Orphan detection — check every entry, not just per-stem-unique ones
        var orphans: [OrphanLink] = []
        for entry in claudeEntries {
            let filename = (entry as NSString).lastPathComponent
            let name = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
            if !knownNames.contains(name), isSymlink(at: entry, fm: fm) {
                orphans.append(OrphanLink(id: name, path: entry, kind: .claude))
            }
        }
        for entry in geminiEntries {
            let filename = (entry as NSString).lastPathComponent
            var name = filename
            if name.hasSuffix(".toml") { name = String(name.dropLast(5)) }
            else if name.hasSuffix(".md") { name = String(name.dropLast(3)) }
            if !knownNames.contains(name), isSymlink(at: entry, fm: fm) {
                orphans.append(OrphanLink(id: name, path: entry, kind: .gemini))
            }
        }

        return (records, orphans)
    }

    // MARK: - Helpers

    /// Returns full paths for all entries in a directory (preserves duplicates with different extensions).
    private static func commandPaths(in dir: String) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return items.map { (dir as NSString).appendingPathComponent($0) }
    }

    /// For Gemini, prefer existing .toml; fall back to .md; default to .toml for new links.
    static func geminiLinkPath(for name: String) -> String {
        let fm = FileManager.default
        let toml = (geminiCommandsDir as NSString).appendingPathComponent("\(name).toml")
        let md   = (geminiCommandsDir as NSString).appendingPathComponent("\(name).md")
        if fm.fileExists(atPath: toml) { return toml }
        if fm.fileExists(atPath: md)   { return md }
        return toml  // default for new creation
    }

    static func linkState(at path: String, fm: FileManager = .default) -> LinkState {
        var isSymlink = false
        var exists = false
        // Use lstat to detect symlinks (fileExists follows symlinks)
        var st = stat()
        if lstat(path, &st) == 0 {
            isSymlink = (st.st_mode & S_IFMT) == S_IFLNK
            if isSymlink {
                exists = fm.fileExists(atPath: path)  // follows the link
                return exists ? .linked : .broken
            } else {
                return .linked  // regular file — treat as linked, don't touch
            }
        }
        return .unlinked
    }

    private static func isSymlink(at path: String, fm: FileManager) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    private static func stripExtension(_ name: String) -> String {
        for ext in [".md", ".toml"] {
            if name.hasSuffix(ext) { return String(name.dropLast(ext.count)) }
        }
        return name
    }

    /// Reads the first `description:` value from YAML frontmatter.
    private static func parseFrontmatterDescription(at path: String) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return "" }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if line.hasPrefix("description:") {
                return line
                    .dropFirst("description:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return ""
    }
}
