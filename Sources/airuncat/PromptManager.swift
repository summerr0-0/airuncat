import Foundation

enum PromptManager {
    static var promptsDir: String { PathConstants.prompts }

    // MARK: - Migration

    static func migrateFromObsidianIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: promptsDir) else { return }
        try? fm.createDirectory(atPath: promptsDir, withIntermediateDirectories: true)
        let obsidianDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Obsidian/document/07_Prompts")
        guard let items = try? fm.contentsOfDirectory(atPath: obsidianDir) else { return }
        for filename in items.sorted() {
            guard filename.hasPrefix("PROMPT_") && filename.hasSuffix(".md") else { continue }
            let stem = String(filename.dropFirst("PROMPT_".count).dropLast(".md".count)).lowercased()
            let destPath = (promptsDir as NSString).appendingPathComponent("\(stem).md")
            guard !fm.fileExists(atPath: destPath) else { continue }
            let srcPath = (obsidianDir as NSString).appendingPathComponent(filename)
            try? fm.copyItem(atPath: srcPath, toPath: destPath)
        }
    }

    // MARK: - Create

    static func createPrompt(
        id: String,
        title: String,
        category: String,
        body: String,
        pinned: Bool
    ) -> String? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: promptsDir) {
            do { try fm.createDirectory(atPath: promptsDir, withIntermediateDirectories: true) }
            catch { return "디렉토리 생성 실패: \(error.localizedDescription)" }
        }
        let filePath = (promptsDir as NSString).appendingPathComponent("\(id).md")
        if fm.fileExists(atPath: filePath) { return "이미 존재하는 프롬프트: \(id)" }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())

        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let cat = category.isEmpty ? "기타" : category
        let content = "---\ntitle: \"\(escapedTitle)\"\ncategory: \(cat)\ntags: []\npinned: \(pinned)\ndate: \(dateStr)\n---\n\n\(body)\n"

        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "파일 생성 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete

    static func deletePrompt(_ record: PromptRecord) -> String? {
        do {
            try FileManager.default.removeItem(atPath: record.filePath)
            return nil
        } catch {
            return "파일 삭제 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Toggle Pin

    static func togglePin(_ record: PromptRecord) -> String? {
        guard let content = try? String(contentsOfFile: record.filePath, encoding: .utf8) else {
            return "파일 읽기 실패: \(record.id)"
        }
        guard let updated = setPinnedInFrontmatter(content, pinned: !record.pinned) else {
            return "프론트매터 형식 오류 (닫는 --- 없음): \(record.id)"
        }
        do {
            try updated.write(toFile: record.filePath, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "파일 쓰기 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    /// Returns nil if frontmatter is malformed (missing closing ---), to avoid corrupting the file.
    private static func setPinnedInFrontmatter(_ text: String, pinned: Bool) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return "---\npinned: \(pinned)\n---\n\n\(text)"
        }
        var result: [String] = []
        var inFrontmatter = true
        var foundPinned = false

        for (i, line) in lines.enumerated() {
            if i == 0 { result.append(line); continue }
            if inFrontmatter && line.trimmingCharacters(in: .whitespaces) == "---" {
                if !foundPinned { result.append("pinned: \(pinned)") }
                result.append(line)
                inFrontmatter = false
                continue
            }
            if inFrontmatter && line.hasPrefix("pinned:") {
                result.append("pinned: \(pinned)")
                foundPinned = true
                continue
            }
            result.append(line)
        }
        // Malformed frontmatter: closing --- never found — refuse to modify
        guard !inFrontmatter else { return nil }
        return result.joined(separator: "\n")
    }
}
