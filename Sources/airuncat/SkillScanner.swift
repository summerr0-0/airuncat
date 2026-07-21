import Foundation

// MARK: - Models

enum LinkState {
    case linked    // entry exists and target is reachable
    case broken    // symlink exists but target is missing
    case unlinked  // no entry
}

enum SkillScope: Equatable {
    case native   // ~/.claude/skills/<name>/SKILL.md — 원본(글로벌). Claude 항상 활성, G 토글로 Gemini 복제
    case project  // <cwd>/.claude/{commands,skills} — 프로젝트 로컬, 읽기 전용 표시
}

struct SkillRecord: Identifiable {
    let id: String          // kebab-case name
    let description: String
    let sourcePath: String
    var scope: SkillScope
    var geminiState: LinkState
    var geminiLinkPath: String   // ~/.gemini/commands/<name>.toml
    var geminiError: String?
    var group: String? = nil     // native 스킬의 출처(symlink 대상 repo), project 스킬의 폴더명
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

    /// Returns (skill records sorted by scope/group/name, broken symlinks in commands dirs).
    /// `projectCwds`: 스캔할 프로젝트들의 cwd. 각 프로젝트의 `.claude/commands`+`.claude/skills`를
    /// 프로젝트별 group으로 묶어 포함한다(여러 프로젝트 동시).
    static func scan(projectCwds: [String] = []) -> (skills: [SkillRecord], orphans: [OrphanLink]) {
        var records = nativeSkills()

        // 프로젝트 로컬 스킬 — 여러 프로젝트의 .claude/commands + .claude/skills, 프로젝트별 group.
        var seenCwds = Set<String>()
        for cwd in projectCwds where !cwd.isEmpty && seenCwds.insert(cwd).inserted {
            records.append(contentsOf: projectSkills(cwd: cwd))
        }

        // 정렬: native(그룹별) → project(그룹별). 그룹 내 이름순.
        records.sort {
            let ra = $0.scope == .native ? 0 : 1
            let rb = $1.scope == .native ? 0 : 1
            if ra != rb { return ra < rb }
            if $0.group != $1.group { return ($0.group ?? "") < ($1.group ?? "") }
            return $0.id < $1.id
        }

        // 고아 = commands 디렉토리의 **깨진 symlink**. 건강한 무관 링크는 사용자 소유물 — 안 건드림.
        var orphans: [OrphanLink] = []
        for entry in commandPaths(in: claudeCommandsDir) where linkState(at: entry) == .broken {
            orphans.append(OrphanLink(id: stem(of: entry), path: entry, kind: .claude))
        }
        for entry in commandPaths(in: geminiCommandsDir) where linkState(at: entry) == .broken {
            orphans.append(OrphanLink(id: stem(of: entry), path: entry, kind: .gemini))
        }

        return (records, orphans)
    }

    // MARK: - Native skills (~/.claude/skills — 원본)

    /// `~/.claude/skills/<name>/SKILL.md`를 스캔한다. Claude가 자동 인식하므로 항상 활성이고,
    /// airuncat이 관리하는 건 Gemini 복제 링크뿐이다. symlink 디렉토리는 출처 repo를 group으로 표시.
    private static func nativeSkills() -> [SkillRecord] {
        let fm = FileManager.default
        let dir = PathConstants.claudeSkills
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        var recs: [SkillRecord] = []
        for name in entries.sorted() where !name.hasPrefix(".") {
            let skillDir = (dir as NSString).appendingPathComponent(name)
            let skillMd = (skillDir as NSString).appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMd) else { continue }   // 폴더+SKILL.md 형태만

            let kebab = name.lowercased()
            let geminiLink = geminiLinkPath(for: kebab)
            recs.append(SkillRecord(
                id: kebab,
                description: blockScalarDescription(atPath: skillMd),
                sourcePath: skillMd,
                scope: .native,
                geminiState: linkState(at: geminiLink, fm: fm),
                geminiLinkPath: geminiLink,
                group: nativeGroup(skillDir: skillDir, skillMd: skillMd)
            ))
        }
        return recs
    }

    // MARK: - Project skills (<cwd>/.claude/commands + .claude/skills)

    /// 한 프로젝트의 로컬 스킬을 모은다: `.claude/commands/*.md` + `.claude/skills/<n>/SKILL.md`.
    /// group = 프로젝트 폴더명(폴더 분리용). 같은 프로젝트 안에서 이름 중복은 한 번만.
    /// 참고: 프로젝트 스킬은 native와 **일부러** 교차 dedup하지 않는다 —
    /// 같은 이름이 스코프별로 존재할 수 있고(글로벌 vs 특정 프로젝트) 각 섹션에 보여주는 게 맞다.
    private static func projectSkills(cwd: String) -> [SkillRecord] {
        let fm = FileManager.default
        let label = projectLabel(cwd)
        var local = Set<String>()
        var out: [SkillRecord] = []

        // commands/*.md
        let cmdDir = (cwd as NSString).appendingPathComponent(".claude/commands")
        if let items = try? fm.contentsOfDirectory(atPath: cmdDir) {
            for filename in items.filter({ $0.hasSuffix(".md") }) {
                let kebab = String(filename.dropLast(3)).lowercased()
                guard local.insert(kebab).inserted else { continue }
                let path = (cmdDir as NSString).appendingPathComponent(filename)
                out.append(projectRecord(id: kebab, path: path, group: label))
            }
        }

        // skills/<name>/SKILL.md 또는 skills/*.md(플랫)
        let skDir = (cwd as NSString).appendingPathComponent(".claude/skills")
        if let items = try? fm.contentsOfDirectory(atPath: skDir) {
            for name in items where !name.hasPrefix(".") {
                let entryPath = (skDir as NSString).appendingPathComponent(name)
                let path: String
                let kebab: String
                if name.hasSuffix(".md") {
                    path = entryPath
                    kebab = String(name.dropLast(3)).lowercased()
                } else {
                    path = (entryPath as NSString).appendingPathComponent("SKILL.md")
                    kebab = name.lowercased()
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
                      local.insert(kebab).inserted else { continue }
                out.append(projectRecord(id: kebab, path: path, group: label))
            }
        }
        return out
    }

    private static func projectRecord(id: String, path: String, group: String) -> SkillRecord {
        SkillRecord(
            id: id,
            description: blockScalarDescription(atPath: path),
            sourcePath: path,
            scope: .project,
            geminiState: .unlinked,   // 프로젝트 스킬은 Gemini 복제 관리 대상 아님
            geminiLinkPath: "",
            group: group
        )
    }

    /// 프로젝트 폴더명(cwd의 마지막 경로 요소). 폴더 분리 라벨.
    private static func projectLabel(_ cwd: String) -> String {
        let last = (cwd as NSString).lastPathComponent
        return last.isEmpty ? cwd : last
    }

    // MARK: - Description / group helpers

    /// 블록 스칼라(`description: |`)까지 처리해 첫 줄 요약을 뽑는다.
    private static func blockScalarDescription(atPath path: String) -> String {
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

    /// 네이티브 스킬의 출처 라벨. symlink 대상 경로에서 repo 폴더명을 추출, 실체 디렉토리는 "로컬".
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

    private static func stem(of path: String) -> String {
        let name = (path as NSString).lastPathComponent
        for ext in [".md", ".toml"] where name.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }

    /// Gemini(Antigravity) 복제 위치 = `~/.gemini/skills/<name>` 디렉토리 symlink.
    /// Claude 네이티브와 같은 SKILL.md 포맷이라 변환 없이 디렉토리째 링크한다.
    /// (구 gemini CLI의 commands/*.toml은 시작 시 마이그레이션으로 전환됨.)
    static func geminiLinkPath(for name: String) -> String {
        (PathConstants.geminiSkills as NSString).appendingPathComponent(name)
    }

    static func linkState(at path: String, fm: FileManager = .default) -> LinkState {
        // Use lstat to detect symlinks (fileExists follows symlinks)
        var st = stat()
        if lstat(path, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFLNK {
                return fm.fileExists(atPath: path) ? .linked : .broken  // follows the link
            }
            return .linked  // regular file — treat as linked, don't touch
        }
        return .unlinked
    }
}
