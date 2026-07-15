import Foundation

enum SkillManager {
    /// 구 airuncat 스킬 저장소 — 마이그레이션 소스로만 남음.
    static var legacyStoreDir: String { PathConstants.skills }

    // MARK: - Migration (store → Claude native)

    /// `~/.airuncat/skills/*.md`를 `~/.claude/skills/<name>/SKILL.md`로 1회 이전한다.
    /// Claude 네이티브가 원본이 되고 store는 폐지된다. idempotent — store 없으면 no-op.
    static func migrateStoreToClaudeIfNeeded() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: legacyStoreDir) else { return }

        for filename in items.sorted() where filename.hasSuffix(".md") {
            let src = (legacyStoreDir as NSString).appendingPathComponent(filename)
            let rawStem = String(filename.dropLast(".md".count))
            let stem = rawStem.hasPrefix("SKILL_") ? String(rawStem.dropFirst("SKILL_".count)) : rawStem
            let kebab = stem.lowercased().replacingOccurrences(of: "_", with: "-")

            let destDir = (PathConstants.claudeSkills as NSString).appendingPathComponent(kebab)
            let dest = (destDir as NSString).appendingPathComponent("SKILL.md")

            var materializedFromLink = false
            if symlinkTarget(of: dest) == (src as NSString).standardizingPath {
                // 네이티브 자리에 이 파일을 가리키는 symlink가 이미 있음 → 실체화
                try? fm.removeItem(atPath: dest)
                materializedFromLink = true
            } else if fm.fileExists(atPath: destDir) {
                continue  // 실제 네이티브가 이미 존재 → 원본 보존, 건너뜀
            } else {
                do { try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true) }
                catch { continue }
            }

            do { try fm.moveItem(atPath: src, toPath: dest) } catch {
                // 실체화 실패 시 제거했던 symlink 복원 — 스킬이 조용히 사라지지 않게.
                if materializedFromLink { try? fm.createSymbolicLink(atPath: dest, withDestinationPath: src) }
                continue
            }

            // 구 Claude command symlink는 제거 — 네이티브 스킬이 대체한다.
            let storePrefix = legacyStoreDir + "/"
            let claudeLink = (PathConstants.claudeCommands as NSString).appendingPathComponent("\(kebab).md")
            if symlinkTarget(of: claudeLink)?.hasPrefix(storePrefix) == true {
                try? fm.removeItem(atPath: claudeLink)
            }

            // Gemini symlink는 새 위치로 재지정 (복제 상태 보존).
            for ext in ["toml", "md"] {
                let link = (PathConstants.geminiCommands as NSString).appendingPathComponent("\(kebab).\(ext)")
                if symlinkTarget(of: link)?.hasPrefix(storePrefix) == true {
                    try? fm.removeItem(atPath: link)
                    try? fm.createSymbolicLink(atPath: link, withDestinationPath: dest)
                }
            }
        }

        // 전부 옮겨졌으면 store 디렉토리 자체를 없앤다 (.DS_Store만 남은 경우 포함).
        if let remaining = try? fm.contentsOfDirectory(atPath: legacyStoreDir),
           remaining.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(atPath: legacyStoreDir)
        }
    }

    /// symlink면 절대경로로 해석한 대상, 아니면 nil.
    private static func symlinkTarget(of path: String) -> String? {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return nil }
        if dest.hasPrefix("/") { return (dest as NSString).standardizingPath }
        let base = (path as NSString).deletingLastPathComponent
        return ((base as NSString).appendingPathComponent(dest) as NSString).standardizingPath
    }
}
