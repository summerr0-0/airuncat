import Foundation

enum RuleManager {

    // MARK: - Create

    static func create(name: String, scope: RuleScope, projectCwd: String) -> String? {
        let rulesDir: String
        switch scope {
        case .global:
            rulesDir = HarnessScanner.globalRulesDir
        case .project:
            let claudeDir = (projectCwd as NSString).appendingPathComponent(".claude")
            rulesDir = (claudeDir as NSString).appendingPathComponent("rules")
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: rulesDir) {
            do {
                try fm.createDirectory(atPath: rulesDir, withIntermediateDirectories: true)
            } catch {
                return "디렉토리 생성 실패: \(error.localizedDescription)"
            }
        }

        let filePath = (rulesDir as NSString).appendingPathComponent("\(name).md")
        if fm.fileExists(atPath: filePath) {
            return "이미 존재하는 Rule: \(name)"
        }

        let template = "# \(name)\n\n여기에 AI에게 강제할 제약이나 동작을 기술한다.\n"
        do {
            try template.write(toFile: filePath, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "파일 생성 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete

    static func delete(_ rule: RuleFile) -> String? {
        do {
            try FileManager.default.removeItem(atPath: rule.path)
            return nil
        } catch {
            return "삭제 실패: \(error.localizedDescription)"
        }
    }
}
