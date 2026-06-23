import Foundation

// MARK: - Model

struct PromptRecord: Identifiable {
    let id: String        // file stem (e.g. "code-review")
    let title: String
    let tags: [String]
    let category: String
    var pinned: Bool
    let body: String
    let filePath: String  // absolute path to ~/.airuncat/prompts/<id>.md
}

// MARK: - Scanner

enum PromptScanner {
    static func scan() -> [PromptRecord] {
        PromptManager.migrateFromObsidianIfNeeded()
        let dir = PromptManager.promptsDir
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return items
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .compactMap { filename in
                let stem = String(filename.dropLast(3))
                let path = (dir as NSString).appendingPathComponent(filename)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let (meta, body) = FrontmatterParser.parse(content)
                return PromptRecord(
                    id: stem,
                    title: meta["title"] as? String ?? stem,
                    tags: meta["tags"] as? [String] ?? [],
                    category: meta["category"] as? String ?? "기타",
                    pinned: meta["pinned"] as? Bool ?? false,
                    body: body,
                    filePath: path
                )
            }
    }

}
