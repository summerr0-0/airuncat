import Foundation

enum AI { case claude, gemini }

enum SkillToggler {
    // MARK: - Enable (create symlink)

    /// Creates a symlink from the commands dir to the local skill file.
    /// Returns nil on success, error message on failure.
    @discardableResult
    static func enable(_ skill: SkillRecord, for ai: AI) -> String? {
        let linkPath = ai == .claude ? skill.claudeLinkPath : skill.geminiLinkPath
        let fm = FileManager.default

        // Ensure the target directory exists
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

        do {
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: skill.sourcePath)
            return nil
        } catch {
            return "링크 생성 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Disable (remove symlink)

    /// Removes the symlink. Only removes if it is actually a symlink — never touches regular files.
    @discardableResult
    static func disable(_ skill: SkillRecord, for ai: AI) -> String? {
        let linkPath = ai == .claude ? skill.claudeLinkPath : skill.geminiLinkPath
        return removeIfSymlink(at: linkPath)
    }

    // MARK: - Repair All

    /// Re-creates broken links. Returns a list of (name, error) for any that failed.
    static func repairAll(_ skills: [SkillRecord]) -> [(name: String, error: String)] {
        var failures: [(String, String)] = []
        for skill in skills {
            if skill.claudeState == .broken {
                if let err = enable(skill, for: .claude) {
                    failures.append((skill.id + " (C)", err))
                }
            }
            if skill.geminiState == .broken {
                if let err = enable(skill, for: .gemini) {
                    failures.append((skill.id + " (G)", err))
                }
            }
        }
        return failures
    }

    // MARK: - Delete Orphan

    @discardableResult
    static func deleteOrphan(_ orphan: OrphanLink) -> String? {
        return removeIfSymlink(at: orphan.path)
    }

    // MARK: - Create Skill

    /// Creates SKILL_*.md in ~/.airuncat/skills/ and optionally symlinks it.
    /// Returns (record, fileError). Symlink errors are stored in record.claudeError/geminiError.
    static func createSkill(
        name: String,
        description: String,
        linkClaude: Bool,
        linkGemini: Bool
    ) -> (record: SkillRecord?, fileError: String?) {
        let fm = FileManager.default
        let skillsDir = SkillManager.skillsDir

        // Ensure skills directory exists
        if !fm.fileExists(atPath: skillsDir) {
            do { try fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true) }
            catch { return (nil, "디렉토리 생성 실패: \(error.localizedDescription)") }
        }

        let stem = name.lowercased().replacingOccurrences(of: "_", with: "-")
        let sourcePath = (skillsDir as NSString).appendingPathComponent("\(stem).md")

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let escapedDesc = description
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let content = """
        ---
        title: "\(name)"
        description: "\(escapedDesc)"
        date: \(dateStr)
        tags: []
        status: active
        ---

        """

        do { try content.write(toFile: sourcePath, atomically: true, encoding: .utf8) }
        catch { return (nil, "파일 생성 실패: \(error.localizedDescription)") }

        guard fm.fileExists(atPath: sourcePath) else { return (nil, "파일 생성 확인 실패") }

        // Use `stem` (kebab-case, lowercased) for link paths — same as the file stem on disk.
        let claudeLink = (SkillScanner.claudeCommandsDir as NSString).appendingPathComponent("\(stem).md")
        let geminiLink = (SkillScanner.geminiCommandsDir as NSString).appendingPathComponent("\(stem).toml")

        var record = SkillRecord(
            id: stem, description: description, sourcePath: sourcePath,
            scope: .global,
            claudeState: .unlinked, geminiState: .unlinked,
            claudeLinkPath: claudeLink, geminiLinkPath: geminiLink
        )

        if linkClaude {
            record.claudeError = enable(record, for: .claude)
            record.claudeState = SkillScanner.linkState(at: claudeLink)
        }
        if linkGemini {
            record.geminiError = enable(record, for: .gemini)
            let newLink = SkillScanner.geminiLinkPath(for: stem)
            record.geminiState = SkillScanner.linkState(at: newLink)
            record.geminiLinkPath = newLink
        }

        return (record, nil)
    }

    // MARK: - Delete Skill

    struct DeleteResult {
        var warnings: [String] = []  // symlink errors (non-fatal)
        var fileError: String? = nil  // fatal: source file not removed
    }

    /// Removes all symlinks then the local source file. Always attempts all steps.
    static func deleteSkill(_ skill: SkillRecord) -> DeleteResult {
        var result = DeleteResult()

        // 1. Claude symlink
        if let err = removeIfSymlink(at: skill.claudeLinkPath) { result.warnings.append(err) }

        // 2. Gemini symlinks — record's actual path + both extensions to catch legacy links
        let geminiToml = (SkillScanner.geminiCommandsDir as NSString).appendingPathComponent("\(skill.id).toml")
        let geminiMd   = (SkillScanner.geminiCommandsDir as NSString).appendingPathComponent("\(skill.id).md")
        var geminiPaths = [geminiToml, geminiMd]
        if !geminiPaths.contains(skill.geminiLinkPath) { geminiPaths.append(skill.geminiLinkPath) }
        for path in geminiPaths {
            if let err = removeIfSymlink(at: path) { result.warnings.append(err) }
        }

        // 3. Local source file (fatal)
        do { try FileManager.default.removeItem(atPath: skill.sourcePath) }
        catch { result.fileError = "파일 삭제 실패: \(error.localizedDescription)" }

        return result
    }

    // MARK: - Private

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
