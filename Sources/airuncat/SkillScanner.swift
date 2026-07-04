import Foundation

// MARK: - Models

enum LinkState {
    case linked    // entry exists and target is reachable
    case broken    // symlink exists but target is missing
    case unlinked  // no entry
}

enum SkillScope: Equatable {
    case global   // ~/.airuncat/skills/ — managed by airuncat, linked to commands dirs
    case project  // <cwd>/.claude/commands/ — project-local, Claude reads directly
    case native   // ~/.claude/skills/<name>/SKILL.md — Claude 네이티브 스킬(자동 활성, 링크 관리 없음)
}

struct SkillRecord: Identifiable {
    let id: String          // kebab-case name
    let description: String
    let sourcePath: String
    var scope: SkillScope
    var claudeState: LinkState
    var geminiState: LinkState
    var claudeLinkPath: String   // ~/.claude/commands/<name>.md
    var geminiLinkPath: String   // ~/.gemini/commands/<name>.toml
    var claudeError: String?
    var geminiError: String?
    var group: String? = nil     // native 스킬의 출처 프로젝트(폴더 분리용)
}

struct OrphanLink: Identifiable {
    let id: String   // link file name stem
    let path: String // full path of the dangling link
    let kind: OrphanKind
    enum OrphanKind { case claude, gemini }
}

// MARK: - Scanner

enum SkillScanner {
    static var claudeCommandsDir: String { PathConstants.claudeCommands }
    static var geminiCommandsDir: String { PathConstants.geminiCommands }

    /// Returns (skill records sorted by name, orphan links found in commands dirs).
    /// Pass `projectCwd` to also include project-local skills from `<cwd>/.claude/commands/`.
    static func scan(projectCwd: String? = nil) -> (skills: [SkillRecord], orphans: [OrphanLink]) {
        // 마이그레이션은 AiruncatApp.init에서 1회 — 스캔은 순수 읽기.
        let fm = FileManager.default
        let skillsDir = SkillManager.skillsDir

        // 1. Enumerate *.md in global skills dir
        var skillFiles: [String] = []
        if let items = try? fm.contentsOfDirectory(atPath: skillsDir) {
            skillFiles = items
                .filter { $0.hasSuffix(".md") }
                .map { (skillsDir as NSString).appendingPathComponent($0) }
        }

        // 2. All existing entries in commands dirs (for orphan detection)
        let claudeEntries = commandPaths(in: claudeCommandsDir)
        let geminiEntries = commandPaths(in: geminiCommandsDir)

        // 3. Build SkillRecord per global skill file
        var knownNames = Set<String>()
        var records: [SkillRecord] = []

        for path in skillFiles {
            let fileName = (path as NSString).lastPathComponent
            let rawStem = String(fileName.dropLast(".md".count))
            let stem = rawStem.hasPrefix("SKILL_") ? String(rawStem.dropFirst("SKILL_".count)) : rawStem
            let kebab = stem.lowercased().replacingOccurrences(of: "_", with: "-")

            guard !knownNames.contains(kebab) else { continue }
            knownNames.insert(kebab)

            let desc = parseFrontmatterDescription(at: path)
            let claudeLink = (claudeCommandsDir as NSString).appendingPathComponent("\(kebab).md")
            let geminiLink = geminiLinkPath(for: kebab)

            records.append(SkillRecord(
                id: kebab,
                description: desc,
                sourcePath: path,
                scope: .global,
                claudeState: linkState(at: claudeLink, fm: fm),
                geminiState: linkState(at: geminiLink, fm: fm),
                claudeLinkPath: claudeLink,
                geminiLinkPath: geminiLink
            ))
        }

        // 4. Project-local skills from <cwd>/.claude/commands/
        if let cwd = projectCwd, !cwd.isEmpty {
            let projCommandsDir = (cwd as NSString).appendingPathComponent(".claude/commands")
            if let items = try? fm.contentsOfDirectory(atPath: projCommandsDir) {
                for filename in items.filter({ $0.hasSuffix(".md") }) {
                    let kebab = String(filename.dropLast(".md".count)).lowercased()
                    guard !knownNames.contains(kebab) else { continue }  // global wins on collision
                    knownNames.insert(kebab)
                    let path = (projCommandsDir as NSString).appendingPathComponent(filename)
                    let desc = parseFrontmatterDescription(at: path)
                    records.append(SkillRecord(
                        id: kebab,
                        description: desc,
                        sourcePath: path,
                        scope: .project,
                        claudeState: .linked,   // project skills need no symlink
                        geminiState: .unlinked,
                        claudeLinkPath: path,
                        geminiLinkPath: ""
                    ))
                }
            }
        }

        // 5. Native skills from ~/.claude/skills/<name>/SKILL.md (Claude 자동 인식, 링크 관리 없음)
        records.append(contentsOf: nativeSkills(knownNames: &knownNames))

        // 정렬: global → project → native. native는 group(출처)별로 묶고 이름순.
        func rank(_ s: SkillScope) -> Int {
            switch s { case .global: return 0; case .project: return 1; case .native: return 2 }
        }
        records.sort {
            let ra = rank($0.scope), rb = rank($1.scope)
            if ra != rb { return ra < rb }
            if $0.scope == .native, $1.scope == .native, $0.group != $1.group {
                return ($0.group ?? "") < ($1.group ?? "")
            }
            return $0.id < $1.id
        }

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

    // MARK: - Native skills (~/.claude/skills)

    /// `~/.claude/skills/<name>/SKILL.md`를 스캔한다. Claude가 자동 인식하는 네이티브 스킬로,
    /// airuncat이 링크를 관리하지 않는다(읽기 전용 표시). 심볼릭 대상에서 출처 프로젝트를 추출.
    private static func nativeSkills(knownNames: inout Set<String>) -> [SkillRecord] {
        let fm = FileManager.default
        let dir = PathConstants.claudeSkills
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        var recs: [SkillRecord] = []
        for name in entries where !name.hasPrefix(".") {
            let skillDir = (dir as NSString).appendingPathComponent(name)
            let skillMd = (skillDir as NSString).appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMd) else { continue }   // 폴더+SKILL.md 형태만

            let kebab = name.lowercased()
            guard !knownNames.contains(kebab) else { continue }
            knownNames.insert(kebab)

            recs.append(SkillRecord(
                id: kebab,
                description: nativeDescription(atPath: skillMd),
                sourcePath: skillMd,
                scope: .native,
                claudeState: .linked,     // 네이티브는 항상 활성 — 링크 상태 개념 없음
                geminiState: .unlinked,
                claudeLinkPath: skillMd,
                geminiLinkPath: "",
                group: nativeGroup(skillDir: skillDir, skillMd: skillMd)
            ))
        }
        return recs
    }

    /// 블록 스칼라(`description: |`)까지 처리해 첫 줄 요약을 뽑는다.
    private static func nativeDescription(atPath path: String) -> String {
        let d = FrontmatterParser.description(atPath: path)
        let markers: Set<String> = ["", "|", ">", "|-", ">-", "|+", ">+"]
        guard markers.contains(d) else { return d }
        // 블록 스칼라: description: 다음의 첫 들여쓰기 비어있지 않은 줄.
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        let lines = content.components(separatedBy: "\n")
        var seenDesc = false
        for line in lines {
            if !seenDesc {
                if line.hasPrefix("description:") { seenDesc = true }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    /// 네이티브 스킬의 출처 프로젝트 라벨. 심볼릭 대상 경로에서 repo 폴더명을 추출.
    private static func nativeGroup(skillDir: String, skillMd: String) -> String {
        let fm = FileManager.default
        func resolve(_ p: String) -> String? {
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: p) else { return nil }
            if dest.hasPrefix("/") { return dest }
            let base = (p as NSString).deletingLastPathComponent
            return ((base as NSString).appendingPathComponent(dest) as NSString).standardizingPath
        }
        guard let target = resolve(skillDir) ?? resolve(skillMd) else { return "로컬" }
        if target.contains("/Obsidian/") { return "Obsidian" }

        let comps = (target as NSString).pathComponents
        if let idx = comps.lastIndex(of: "skills") {
            var j = idx - 1
            if j >= 0, comps[j] == ".claude" { j -= 1 }
            if j >= 0 { return comps[j] }
        }
        let parent = (target as NSString).deletingLastPathComponent
        let last = (parent as NSString).lastPathComponent
        return last.isEmpty ? "로컬" : last
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

    private static func parseFrontmatterDescription(at path: String) -> String {
        FrontmatterParser.description(atPath: path)
    }
}
