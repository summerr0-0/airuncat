import Foundation

enum SkillManager {
    static let skillsDir: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".airuncat/skills")

    // MARK: - Migration

    static func migrateFromObsidianIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: skillsDir) else { return }
        try? fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        let obsidianDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Obsidian/document/06_AI_Config")
        guard let items = try? fm.contentsOfDirectory(atPath: obsidianDir) else { return }
        for filename in items.sorted() {
            guard filename.hasPrefix("SKILL_") && filename.hasSuffix(".md") else { continue }
            let destPath = (skillsDir as NSString).appendingPathComponent(filename)
            guard !fm.fileExists(atPath: destPath) else { continue }
            let srcPath = (obsidianDir as NSString).appendingPathComponent(filename)
            try? fm.copyItem(atPath: srcPath, toPath: destPath)
        }
    }
}
