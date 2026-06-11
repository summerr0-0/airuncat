import Foundation

enum AI { case claude, gemini }

enum SkillToggler {
    // MARK: - Enable (create symlink)

    /// Creates a symlink from the commands dir to the Obsidian skill file.
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
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: skill.obsidianPath)
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
