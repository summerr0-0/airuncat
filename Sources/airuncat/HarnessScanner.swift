import Foundation
import CryptoKit

// MARK: - Models

enum RuleScope {
    case global, project
    var prefix: String { self == .global ? "g" : "p" }
}

struct RuleFile: Identifiable {
    let id: String       // "\(scope.prefix):\(stem)" — scope 포함, ForEach 충돌 방지
    let stem: String     // 파일명 stem (표시용)
    let path: String
    let summary: String  // 파일 첫 비빈·비헤더 줄 (없으면 "")
    let mtime: Date      // stat mtime
    let scope: RuleScope
}

struct HookEntry: Identifiable {
    let id: String            // SHA256(event+matcher+command)[0..<8]
    let event: String         // "PreToolUse" | "PostToolUse"
    let matcher: String
    let commandSummary: String
    var enabled: Bool
}

enum PermissionKind: String {
    case allow, deny
}

struct PermissionEntry: Identifiable {
    let id: String          // "\(kind.rawValue):\(pattern)" — allow/deny 양쪽 동일 pattern 허용
    let pattern: String
    let kind: PermissionKind
}

struct HarnessInfo {
    let projectPath: String
    let settingsPath: String
    var settingsMtime: Date
    var rules: [RuleFile]
    var hooks: [HookEntry]
    var permissions: [PermissionEntry]
    var omcPresent: Bool
    var writeError: String?

    // 점수 입력 (프로젝트-로컬 정적 신호) — scan()에서 채움, 기본값으로 멤버와이즈 init 보존
    var claudeMdWordCount: Int = 0
    var claudeMdHasImports: Bool = false
    var projectSkillCount: Int = 0

    var projectRuleCount: Int { rules.filter { $0.scope == .project }.count }
    var score: HarnessScore { HarnessScoring.evaluate(self) }

    var enabledHookCount: Int { hooks.filter(\.enabled).count }
    var totalCount: Int { rules.count + hooks.count }
    var activeCount: Int { rules.count + enabledHookCount }
    var hasDisabledHook: Bool { hooks.contains { !$0.enabled } }

    var badgeLabel: String {
        guard totalCount > 0 else { return "" }
        if activeCount == totalCount { return "H \(totalCount)" }
        return "H \(activeCount)/\(totalCount)"
    }
}

// MARK: - Scanner

enum HarnessScanner {
    static var globalRulesDir: String { PathConstants.claudeRules }

    static func scan(cwd: String) -> HarnessInfo? {
        let claudeDir = (cwd as NSString).appendingPathComponent(".claude")
        guard FileManager.default.fileExists(atPath: claudeDir) else { return nil }

        let settingsPath = (claudeDir as NSString).appendingPathComponent("settings.json")
        let settingsMtime = mtime(of: settingsPath) ?? Date()

        let rules = scanRules(claudeDir: claudeDir)
        let hooks = scanHooks(settingsPath: settingsPath)
        let permissions = scanPermissions(settingsPath: settingsPath)
        let omcPresent = detectOMC(cwd: cwd)
        let md = scanClaudeMd(cwd: cwd)
        let projectSkillCount = countProjectSkills(cwd: cwd)

        return HarnessInfo(
            projectPath: cwd,
            settingsPath: settingsPath,
            settingsMtime: settingsMtime,
            rules: rules,
            hooks: hooks,
            permissions: permissions,
            omcPresent: omcPresent,
            claudeMdWordCount: md.wordCount,
            claudeMdHasImports: md.hasImports,
            projectSkillCount: projectSkillCount
        )
    }

    /// 프로젝트 CLAUDE.md를 1회 읽어 wordCount와 @import 존재를 함께 산출.
    /// root `CLAUDE.md` 우선, 없으면 `.claude/CLAUDE.md`. 둘 다 없으면 (0, false).
    private static func scanClaudeMd(cwd: String) -> (wordCount: Int, hasImports: Bool) {
        let fm = FileManager.default
        let root = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        let sub  = (cwd as NSString).appendingPathComponent(".claude/CLAUDE.md")
        let path = fm.fileExists(atPath: root) ? root : (fm.fileExists(atPath: sub) ? sub : nil)
        guard let path, let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return (0, false)
        }
        let wordCount = content.split { $0.isWhitespace || $0.isNewline }.count

        // @import 검출: 코드펜스 밖에서 `@`로 시작하고 경로(`/` 또는 `.md`)를 가진 줄만.
        // (Swift `@MainActor`/`@State` 등 데코레이터·멘션 오탐 방지)
        var hasImports = false
        var inFence = false
        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            if line.hasPrefix("@"), line.contains("/") || line.contains(".md") {
                hasImports = true
                break
            }
        }
        return (wordCount, hasImports)
    }

    /// 프로젝트-로컬 자동화(슬래시 커맨드/스킬) 파일 수.
    /// `<cwd>/.claude/commands` + `<cwd>/.claude/skills`의 *.md를 직접 세어
    /// SkillScanner의 Obsidian 마이그레이션 쓰기 부작용과 글로벌 충돌 필터를 피한다.
    private static func countProjectSkills(cwd: String) -> Int {
        let fm = FileManager.default
        var count = 0
        for rel in [".claude/commands", ".claude/skills"] {
            let dir = (cwd as NSString).appendingPathComponent(rel)
            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                count += items.filter { $0.hasSuffix(".md") }.count
            }
        }
        return count
    }

    // MARK: - Helpers

    private static func scanRules(claudeDir: String) -> [RuleFile] {
        var result: [RuleFile] = []
        result += scanRulesDir(globalRulesDir, scope: .global)
        let projectRulesDir = (claudeDir as NSString).appendingPathComponent("rules")
        result += scanRulesDir(projectRulesDir, scope: .project)
        return result
    }

    private static func scanRulesDir(_ dir: String, scope: RuleScope) -> [RuleFile] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return items
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { filename in
                let stem = String(filename.dropLast(3))
                let path = (dir as NSString).appendingPathComponent(filename)
                return RuleFile(
                    id: "\(scope.prefix):\(stem)",
                    stem: stem,
                    path: path,
                    summary: readSummary(path: path),
                    mtime: mtime(of: path) ?? .distantPast,
                    scope: scope
                )
            }
    }

    private static func readSummary(path: String) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
    }

    static func scanHooks(settingsPath: String) -> [HookEntry] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var entries: [HookEntry] = []
        entries += parseHookSection(json["hooks"], enabled: true)
        entries += parseHookSection(json["_disabledHooks"], enabled: false)
        return entries
    }

    private static func parseHookSection(_ section: Any?, enabled: Bool) -> [HookEntry] {
        guard let dict = section as? [String: Any] else { return [] }
        var entries: [HookEntry] = []
        for (event, groups) in dict {
            guard let groupArray = groups as? [[String: Any]] else { continue }
            for group in groupArray {
                let matcher = group["matcher"] as? String ?? ""
                let hooks = group["hooks"] as? [[String: Any]] ?? []
                let firstCmd = hooks.first?["command"] as? String ?? ""
                let summary = String(firstCmd.prefix(70))
                let hookCount = hooks.count
                let displaySummary = hookCount > 1 ? "\(summary) (외 \(hookCount - 1)개)" : summary
                let entryId = hookHash(event: event, matcher: matcher, command: firstCmd)
                entries.append(HookEntry(
                    id: entryId,
                    event: event,
                    matcher: matcher,
                    commandSummary: displaySummary,
                    enabled: enabled
                ))
            }
        }
        return entries.sorted { $0.event < $1.event || ($0.event == $1.event && $0.matcher < $1.matcher) }
    }

    static func hookHash(event: String, matcher: String, command: String) -> String {
        let input = Data((event + matcher + command).utf8)
        let digest = SHA256.hash(data: input)
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func scanPermissions(settingsPath: String) -> [PermissionEntry] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let perms = json["permissions"] as? [String: Any]
        else { return [] }

        var result: [PermissionEntry] = []
        for kind in [PermissionKind.allow, .deny] {
            let patterns = perms[kind.rawValue] as? [String] ?? []
            result += patterns.sorted().map {
                PermissionEntry(id: "\(kind.rawValue):\($0)", pattern: $0, kind: kind)
            }
        }
        return result
    }

    private static func detectOMC(cwd: String) -> Bool {
        let claudeMd = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        guard let content = try? String(contentsOfFile: claudeMd, encoding: .utf8) else { return false }
        return content.contains("oh-my-claudecode") || content.contains("OMC(")
    }

    static func mtime(of path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
    }
}
