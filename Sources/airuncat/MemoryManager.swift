import Foundation

enum MemoryManager {

    // Delete a memory record:
    // 1. Remove the file
    // 2. Remove the corresponding line from MEMORY.md (anchored match)
    static func delete(_ record: MemoryRecord, memoryDir: String) -> String? {
        let filename = (record.path as NSString).lastPathComponent
        let fm = FileManager.default

        // Step 1: delete file
        do {
            try fm.removeItem(atPath: record.path)
        } catch {
            return "삭제 실패: \(error.localizedDescription)"
        }

        // Step 2: update MEMORY.md index (best-effort; failure doesn't affect data integrity)
        let indexPath = (memoryDir as NSString).appendingPathComponent("MEMORY.md")
        guard let content = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return nil }

        // "](\(filename))" anchors on the markdown link target to avoid false matches
        let anchor = "](\(filename))"
        let updated = content.components(separatedBy: .newlines)
            .filter { !$0.contains(anchor) }
            .joined(separator: "\n")

        try? updated.write(toFile: indexPath, atomically: true, encoding: .utf8)
        return nil
    }
}
