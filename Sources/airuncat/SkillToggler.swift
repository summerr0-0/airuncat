import Foundation

/// Gemini 복제 링크 관리 + 네이티브 스킬 생성/삭제.
/// Claude 쪽은 관리할 게 없다 — `~/.claude/skills/`의 스킬은 Claude가 자동 인식(항상 활성).
enum SkillToggler {
    // MARK: - Gemini replication (symlink)

    /// `~/.gemini/skills/<name>` 디렉토리 symlink → `~/.claude/skills/<name>` 생성.
    /// SKILL.md 포맷이 동일해 디렉토리째 링크하면 Antigravity(IDE+CLI)가 그대로 읽는다.
    /// Returns nil on success, error message on failure.
    @discardableResult
    static func enableGemini(_ skill: SkillRecord) -> String? {
        let linkPath = skill.geminiLinkPath
        let fm = FileManager.default

        let dir = (linkPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return "디렉토리 생성 실패: \(error.localizedDescription)"
            }
        }

        // If a broken symlink exists, remove it first
        if case .broken = SkillScanner.linkState(at: linkPath) {
            try? fm.removeItem(atPath: linkPath)
        }

        // 네이티브 스킬(<dir>/SKILL.md)만 디렉토리째 링크 — flat 파일이면 상위 폴더 전체가 걸려버림
        guard skill.sourcePath.hasSuffix("/SKILL.md") else {
            return "디렉토리형 스킬이 아닙니다: \(skill.sourcePath)"
        }
        let skillDir = (skill.sourcePath as NSString).deletingLastPathComponent
        do {
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: skillDir)
            return nil
        } catch {
            return "링크 생성 실패: \(error.localizedDescription)"
        }
    }

    /// Removes the Gemini symlinks (both `.toml`/`.md` — legacy 링크가 남으면 토글이 되돌아온다).
    /// 이 스킬을 가리키거나 깨진 symlink만 제거하고, 무관 링크/실파일은 건드리지 않는다.
    @discardableResult
    static func disableGemini(_ skill: SkillRecord) -> String? {
        // 우선 경로가 실파일이면 기존처럼 명시적으로 알린다 (조용한 no-op 방지).
        var st = stat()
        if lstat(skill.geminiLinkPath, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK {
            return "심볼릭 링크가 아닙니다. 수동으로 확인하세요: \(skill.geminiLinkPath)"
        }
        return removeGeminiLinks(id: skill.id, sourcePath: skill.sourcePath)
    }

    // MARK: - Repair All

    /// Re-creates broken Gemini links. Returns a list of (name, error) for any that failed.
    static func repairAll(_ skills: [SkillRecord]) -> [(name: String, error: String)] {
        var failures: [(String, String)] = []
        for skill in skills where skill.geminiState == .broken {
            if let err = enableGemini(skill) {
                failures.append((skill.id, err))
            }
        }
        return failures
    }

    // MARK: - Delete Orphan

    @discardableResult
    static func deleteOrphan(_ orphan: OrphanLink) -> String? {
        removeIfSymlink(at: orphan.path)
    }

    // MARK: - Create Skill

    /// `~/.claude/skills/<name>/SKILL.md`를 생성하고 선택적으로 Gemini에 복제한다.
    /// Returns (record, fileError). Gemini 링크 오류는 record.geminiError에 담긴다.
    static func createSkill(
        name: String,
        description: String,
        linkGemini: Bool
    ) -> (record: SkillRecord?, fileError: String?) {
        let fm = FileManager.default
        let stem = name.lowercased().replacingOccurrences(of: "_", with: "-")
        let skillDir = (PathConstants.claudeSkills as NSString).appendingPathComponent(stem)
        let sourcePath = (skillDir as NSString).appendingPathComponent("SKILL.md")

        guard !fm.fileExists(atPath: skillDir) else {
            return (nil, "이미 존재하는 스킬입니다: \(stem)")
        }
        do { try fm.createDirectory(atPath: skillDir, withIntermediateDirectories: true) }
        catch { return (nil, "디렉토리 생성 실패: \(error.localizedDescription)") }

        let escapedDesc = description
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let content = """
        ---
        name: \(stem)
        description: "\(escapedDesc)"
        ---

        """

        do { try content.write(toFile: sourcePath, atomically: true, encoding: .utf8) }
        catch { return (nil, "파일 생성 실패: \(error.localizedDescription)") }

        var record = SkillRecord(
            id: stem, description: description, sourcePath: sourcePath,
            scope: .native,
            geminiState: .unlinked,
            geminiLinkPath: SkillScanner.geminiLinkPath(for: stem)
        )

        if linkGemini {
            record.geminiError = enableGemini(record)
            record.geminiState = SkillScanner.linkState(at: record.geminiLinkPath)
        }

        return (record, nil)
    }

    // MARK: - Delete Skill

    struct DeleteResult {
        var warnings: [String] = []  // symlink errors (non-fatal)
        var fileError: String? = nil  // fatal: skill dir not removed
    }

    /// Gemini 링크를 제거한 뒤 스킬 디렉토리를 삭제한다.
    /// symlink 디렉토리(외부 repo 연결)는 링크만 제거되고 원본은 남는다(removeItem 의미론).
    static func deleteSkill(_ skill: SkillRecord) -> DeleteResult {
        var result = DeleteResult()

        // 1. Gemini symlinks — 양쪽 확장자 모두 (legacy .md 링크 포함). 무관 링크는 보호.
        if let err = removeGeminiLinks(id: skill.id, sourcePath: skill.sourcePath) {
            result.warnings.append(err)
        }

        // 2. 스킬 디렉토리 — ~/.claude/skills/ 아래일 때만 (안전 가드)
        let skillDir = (skill.sourcePath as NSString).deletingLastPathComponent
        let root = PathConstants.claudeSkills
        guard skill.scope == .native, skillDir.hasPrefix(root + "/"),
              (skillDir as NSString).deletingLastPathComponent == root else {
            result.fileError = "글로벌 스킬 경로가 아닙니다: \(skillDir)"
            return result
        }
        do { try FileManager.default.removeItem(atPath: skillDir) }
        catch { result.fileError = "삭제 실패: \(error.localizedDescription)" }

        return result
    }

    // MARK: - Private

    /// 이 스킬의 Gemini 링크(신형 skills 디렉토리 symlink + legacy commands .toml/.md) 중
    /// 이 스킬을 가리키거나 깨진 것만 제거한다.
    private static func removeGeminiLinks(id: String, sourcePath: String) -> String? {
        let fm = FileManager.default
        let skillDir = ((sourcePath as NSString).deletingLastPathComponent as NSString).standardizingPath
        let source = (sourcePath as NSString).standardizingPath
        var paths = [(PathConstants.geminiSkills as NSString).appendingPathComponent(id)]
        for ext in ["toml", "md"] {
            paths.append((SkillScanner.geminiCommandsDir as NSString).appendingPathComponent("\(id).\(ext)"))
        }
        var firstError: String? = nil
        for path in paths {
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK else { continue }
            let broken = !fm.fileExists(atPath: path)   // follows the link
            let target = resolvedTarget(of: path)
            guard broken || target == source || target == skillDir else { continue }
            do { try fm.removeItem(atPath: path) }
            catch { firstError = firstError ?? "링크 제거 실패: \(error.localizedDescription)" }
        }
        return firstError
    }

    /// symlink 대상을 절대경로로 해석한다.
    private static func resolvedTarget(of path: String) -> String? {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return nil }
        if dest.hasPrefix("/") { return (dest as NSString).standardizingPath }
        let base = (path as NSString).deletingLastPathComponent
        return ((base as NSString).appendingPathComponent(dest) as NSString).standardizingPath
    }

    private static func removeIfSymlink(at path: String) -> String? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }  // doesn't exist → nothing to do
        guard (st.st_mode & S_IFMT) == S_IFLNK else {
            return "심볼릭 링크가 아닙니다. 수동으로 확인하세요: \(path)"
        }
        do {
            try FileManager.default.removeItem(atPath: path)
            return nil
        } catch {
            return "링크 제거 실패: \(error.localizedDescription)"
        }
    }
}
