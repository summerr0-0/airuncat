import Foundation

/// Antigravity CLI(agy) 대화를 읽는다 — gemini CLI 지원종료(2026-06)의 공식 후속.
/// agy는 `~/.gemini`을 홈으로 공유하며 대화를 SQLite(프로토버프 blob)로 저장하므로
/// 내용은 파싱하지 않는다(읽기 전용 원칙). 활동 = db/-wal **mtime**,
/// cwd·프롬프트 = `history.jsonl`(유저 입력 로그: display/timestamp/workspace/conversationId).
struct AgyScanner {

    private static let maxAge: TimeInterval = 48 * 3600
    private static let historyTailBytes = 262144

    /// agy 바이너리 절대경로. GUI 앱은 ~/.local/bin이 PATH에 없어 직접 확인부터 한다.
    static let agyPath: String? = {
        let local = (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/agy")
        if FileManager.default.isExecutableFile(atPath: local) { return local }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "which agy 2>/dev/null"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }()

    static var isAvailable: Bool { agyPath != nil }

    static func scan(cache: inout [String: (mtime: Date, info: SessionInfo)]) -> [SessionInfo] {
        guard isAvailable else { return [] }
        let fm = FileManager.default
        let dir = PathConstants.agyConversations
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        let history = loadHistory()
        let cwdById = loadLastConversations()
        var result: [SessionInfo] = []
        var seen = Set<String>()
        let cutoff = Date().addingTimeInterval(-maxAge)

        for f in files where f.hasSuffix(".db") {
            let conversationId = String(f.dropLast(3))
            let dbPath = (dir as NSString).appendingPathComponent(f)
            // 활동 시각 = db와 -wal 중 최신 (WAL 모드에선 쓰기가 -wal에 먼저 반영됨)
            let m = max(FileIOHelper.mtimeInterval(at: dbPath) ?? 0,
                        FileIOHelper.mtimeInterval(at: dbPath + "-wal") ?? 0)
            guard m > 0 else { continue }
            let mtime = Date(timeIntervalSince1970: m)
            if mtime < cutoff { continue }

            seen.insert(dbPath)
            if let cached = cache[dbPath], cached.mtime == mtime {
                result.append(cached.info)
                continue
            }

            let h = history[conversationId]
            // history는 인터랙티브 입력만 기록 — -p(print) 대화는 cache 매핑에서 cwd를 얻는다
            let cwd = (h?.workspace).flatMap { $0.isEmpty ? nil : $0 } ?? cwdById[conversationId] ?? ""
            let projectName = cwd.isEmpty ? "agy" : (cwd as NSString).lastPathComponent
            let title = (h?.firstPrompt).flatMap { $0.isEmpty ? nil : FileIOHelper.trim($0, 200) } ?? projectName
            // 마지막 유저 입력 이후 db가 더 갱신됐으면 모델이 응답을 쓴 것 → responded
            let workState: WorkState = {
                guard let lastTs = h?.lastTimestamp else { return .working }
                return mtime.timeIntervalSince(lastTs) > 5 ? .responded : .working
            }()

            let info = SessionInfo(
                id: dbPath,
                sessionId: conversationId,
                title: title,
                customName: nil,
                projectName: projectName,
                cwd: cwd,
                gitBranch: "",
                firstInstruction: title,
                lastUserMessage: (h?.lastPrompt).map { FileIOHelper.trim(FileIOHelper.firstLine($0), 100) } ?? "",
                toolName: "",
                toolDetail: "",
                activeSkill: nil,
                lastActivity: mtime,
                messageCount: h?.promptCount ?? 0,
                workState: workState,
                aiKind: .gemini,
                modelName: "agy"
            )
            cache[dbPath] = (mtime, info)
            result.append(info)
        }

        for key in cache.keys where !seen.contains(key) { cache.removeValue(forKey: key) }
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - history.jsonl

    private struct HistorySummary {
        var firstPrompt: String?
        var lastPrompt: String?
        var lastTimestamp: Date?
        var workspace: String = ""
        var promptCount = 0
    }

    /// `cache/last_conversations.json` — {cwd: conversationId} 매핑을 뒤집어 id→cwd로.
    private static func loadLastConversations() -> [String: String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: PathConstants.agyLastConversations)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        var out: [String: String] = [:]
        for (cwd, id) in obj { out[id] = cwd }
        return out
    }

    /// history.jsonl tail에서 conversationId별 요약을 만든다.
    /// 라인 형식: {"display","timestamp"(ms),"workspace","conversationId"?}
    private static func loadHistory() -> [String: HistorySummary] {
        let path = PathConstants.agyHistory
        guard let fh = FileHandle(forReadingAtPath: path) else { return [:] }
        defer { try? fh.close() }
        guard let eof = try? fh.seekToEnd() else { return [:] }
        let start = max(0, Int(eof) - historyTailBytes)
        guard (try? fh.seek(toOffset: UInt64(start))) != nil,
              let data = try? fh.readToEnd() else { return [:] }
        // tail 시작이 멀티바이트 문자 중간에 걸려도 전체가 죽지 않게 손실 허용 디코딩
        let text = String(decoding: data, as: UTF8.self)

        var out: [String: HistorySummary] = [:]
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let obj = FileIOHelper.jsonObject(line),
                  let cid = obj["conversationId"] as? String, !cid.isEmpty else { continue }
            var s = out[cid] ?? HistorySummary()
            if let display = obj["display"] as? String, !display.isEmpty {
                if s.firstPrompt == nil { s.firstPrompt = display }
                s.lastPrompt = display
                s.promptCount += 1
            }
            if let ws = obj["workspace"] as? String, !ws.isEmpty { s.workspace = ws }
            if let ms = obj["timestamp"] as? Double {
                s.lastTimestamp = Date(timeIntervalSince1970: ms / 1000)
            }
            out[cid] = s
        }
        return out
    }
}
