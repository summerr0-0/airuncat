import Foundation

enum SessionStatus {
    case active     // worked within the last ~90s
    case idle       // worked within the last ~30 min
    case resting    // older than that

    init(lastActivity: Date) {
        let age = Date().timeIntervalSince(lastActivity)
        if age < 90 { self = .active }
        else if age < 30 * 60 { self = .idle }
        else { self = .resting }
    }
}

enum WorkState: Equatable {
    case working    // Claude actively invoking tools
    case responded  // Claude sent a text response (question or completion)
}

/// 행 표시·정렬용 통합 상태. recency(status) + workState를 사용자 관점으로 합친 것.
/// 우선순위: 응답 대기(나를 기다림) > 작업 중 > idle > 휴식.
enum SessionDisplayStatus: Int {
    case waiting = 0   // 응답 대기 — 사용자 입력 대기 (앱 핵심 가치)
    case working = 1   // 활발히 작업 중
    case idle    = 2   // 최근이지만 조용
    case resting = 3   // 오래됨
}

enum AIKind {
    case claude
    case gemini
}

struct SessionInfo: Identifiable {
    let id: String              // file path (stable & unique)
    let sessionId: String       // UUID stem of the .jsonl (for `claude -r`)
    var title: String           // ai-title or first instruction
    var customName: String?     // user-assigned display name (overrides title)
    var projectName: String
    var cwd: String
    var gitBranch: String
    var firstInstruction: String
    var lastUserMessage: String  // last user-typed message (shown when responded)
    var toolName: String        // last tool used, e.g. "Bash"
    var toolDetail: String      // summarized arg, e.g. "npx prisma migrate"
    var activeSkill: String?    // skill name currently running (nil if none or completed)
    var lastActivity: Date
    var messageCount: Int
    var workState: WorkState
    var aiKind: AIKind
    var modelName: String? = nil  // Gemini model string; nil for Claude
    var contextTokens: Int? = nil    // 최신 assistant usage: input + cache_read + cache_creation (raw, 창 점유)
    var durationSeconds: Int? = nil  // 첫 이벤트 timestamp ~ 마지막 활동(mtime)
    var activePayloadBytes: Int? = nil  // compact 이후 활성 payload 근사 (R7, ≥22MB일 때만 채움)
    var isThinking: Bool = false        // 최신 assistant에 thinking 블록 + 30s 내 활동 (R9c)
    var frictionReason: String? = nil   // 세션 friction 사유 (R10): 오류율↑/방치 갭. nil=건강

    var status: SessionStatus { SessionStatus(lastActivity: lastActivity) }
    var displayName: String { customName ?? projectName }

    /// 사용자 관점 통합 상태(정렬·표시용).
    var displayStatus: SessionDisplayStatus {
        if case .resting = status { return .resting }       // 오래되면 휴식 우선
        if workState == .responded { return .waiting }       // 최근 + 응답 대기 = 나를 기다림
        if case .active = status, workState == .working { return .working }
        return .idle
    }
}

/// Reads Claude Code session transcripts from ~/.claude/projects/*/*.jsonl
struct SessionScanner {

    static var projectsDir: URL {
        URL(fileURLWithPath: PathConstants.claudeProjects, isDirectory: true)
    }

    /// Scan all sessions. `cache` is reused across ticks: unchanged files
    /// (same modification date) are not re-parsed.
    static func scan(cache: inout [String: (mtime: Date, info: SessionInfo)]) -> [SessionInfo] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [SessionInfo] = []
        var seen = Set<String>()

        for dir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: []
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let path = file.path
                seen.insert(path)
                let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = attrs?.contentModificationDate ?? Date.distantPast
                let size = attrs?.fileSize ?? 0

                if let cached = cache[path], cached.mtime == mtime {
                    result.append(cached.info)
                    continue
                }
                if let info = parse(path: path, size: size, mtime: mtime) {
                    cache[path] = (mtime, info)
                    result.append(info)
                }
            }
        }

        // Drop cache entries for files that disappeared.
        for key in cache.keys where !seen.contains(key) { cache.removeValue(forKey: key) }

        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Parsing one session

    private static func parse(path: String, size: Int, mtime: Date) -> SessionInfo? {
        let url = URL(fileURLWithPath: path)

        let (forwardLines, backwardLines) = FileIOHelper.readLines(url: url, size: size)

        var title = ""
        var firstInstruction = ""
        var cwd = ""
        var gitBranch = ""
        var messageCount = 0
        var firstTimestamp: Date? = nil   // duration 시작점

        // Forward pass: title, first real instruction, cwd/branch, rough message count.
        for line in forwardLines {
            guard let obj = FileIOHelper.jsonObject(line) else { continue }
            if firstTimestamp == nil, let ts = obj["timestamp"] as? String {
                firstTimestamp = parseTimestamp(ts)
            }
            let type = obj["type"] as? String
            switch type {
            case "ai-title":
                if let t = obj["aiTitle"] as? String, !t.isEmpty { title = t }
            case "user":
                if let msg = obj["message"] as? [String: Any] {
                    messageCount += 1
                    if firstInstruction.isEmpty, let t = userText(msg), isRealInstruction(t) {
                        firstInstruction = t
                    }
                }
                captureContext(obj, cwd: &cwd, branch: &gitBranch)
            case "assistant":
                messageCount += 1
                captureContext(obj, cwd: &cwd, branch: &gitBranch)
            default:
                break
            }
        }

        // Backward pass: last tool call + last user message + last event role for WorkState detection.
        var toolName = ""
        var toolDetail = ""
        var lastUserMessage = ""
        var lastEventRole = ""       // type of the newest user/assistant event
        var lastAssistantHasTool = false
        var foundLastAssistant = false
        var foundLastUser = false
        var contextTokens: Int? = nil        // 최신 assistant usage 합산(raw)
        var tailSessionIds = Set<String>()    // R9a: tail에 세션ID 2개↑면 부분 읽기 오표시 방지
        var isThinking = false                // R9c: 최신 assistant의 thinking 블록
        var toolResults = 0                   // R10: tail의 tool_result 표본
        var toolErrors = 0                    //      그중 is_error
        var newerTs: Date? = nil              // R10: 방치 갭(뒤에서 앞으로 인접 이벤트 간격)
        var maxGapSeconds = 0.0
        var maxGapEnd: Date? = nil            //      갭이 끝난 시각(최근 갭만 배지 대상)
        var completedToolIds = Set<String>()  // tool_use IDs that already have a tool_result
        var activeSkill: String? = nil
        var foundSkillCheck = false           // true once we've examined the most recent Skill call

        for line in backwardLines.reversed() {
            guard let obj = FileIOHelper.jsonObject(line) else { continue }
            captureContext(obj, cwd: &cwd, branch: &gitBranch)
            if let sid = obj["sessionId"] as? String { tailSessionIds.insert(sid) }
            let evType = obj["type"] as? String ?? ""
            guard evType == "user" || evType == "assistant" else { continue }

            // R10: 인접 이벤트 간 최대 갭(newest→oldest 순회라 newer가 먼저 옴).
            if let ts = (obj["timestamp"] as? String).flatMap(parseTimestamp) {
                if let newer = newerTs {
                    let gap = newer.timeIntervalSince(ts)
                    if gap > maxGapSeconds { maxGapSeconds = gap; maxGapEnd = newer }
                }
                newerTs = ts
            }

            if lastEventRole.isEmpty { lastEventRole = evType }

            // Collect completed tool IDs from tool_result blocks in user events.
            // Going backward, tool_results appear before their corresponding tool_use,
            // so completedToolIds is populated before we check the Skill tool_use below.
            if evType == "user",
               let msg = obj["message"] as? [String: Any],
               let arr = msg["content"] as? [[String: Any]] {
                for block in arr where (block["type"] as? String) == "tool_result" {
                    if let id = block["tool_use_id"] as? String { completedToolIds.insert(id) }
                    toolResults += 1                                          // R10 표본
                    if (block["is_error"] as? Bool) == true { toolErrors += 1 }
                }
            }

            if evType == "assistant" {
                // 컨텍스트 채움: 가장 최근 assistant 메시지의 usage 합산(raw, D4a).
                if contextTokens == nil,
                   let msg = obj["message"] as? [String: Any],
                   let usage = msg["usage"] as? [String: Any] {
                    contextTokens = contextTokenSum(usage)
                }
                if !foundLastAssistant {
                    foundLastAssistant = true
                    if let msg = obj["message"] as? [String: Any],
                       let (name, detail) = lastToolUse(msg) {
                        toolName = name
                        toolDetail = detail
                        lastAssistantHasTool = true
                    }
                    // R9c: 최신 assistant에 thinking 블록이 있고 30초 내 활동이면 "생각 중".
                    if let msg = obj["message"] as? [String: Any],
                       let arr = msg["content"] as? [[String: Any]],
                       arr.contains(where: { ($0["type"] as? String) == "thinking" }),
                       Date().timeIntervalSince(mtime) < 30 {
                        isThinking = true
                    }
                } else if toolName.isEmpty {
                    // keep scanning earlier assistant events until we find a tool call
                    if let msg = obj["message"] as? [String: Any],
                       let (name, detail) = lastToolUse(msg) {
                        toolName = name
                        toolDetail = detail
                    }
                }

                // Detect active skill: find the most recent Skill tool_use with no matching tool_result.
                if !foundSkillCheck,
                   let msg = obj["message"] as? [String: Any],
                   let arr = msg["content"] as? [[String: Any]] {
                    for block in arr.reversed() where (block["type"] as? String) == "tool_use"
                                                   && (block["name"] as? String) == "Skill" {
                        foundSkillCheck = true
                        if let id = block["id"] as? String,
                           !completedToolIds.contains(id),
                           let input = block["input"] as? [String: Any],
                           let skillName = input["skill"] as? String {
                            activeSkill = skillName
                        }
                        break
                    }
                }
            }

            if !foundLastUser, evType == "user" {
                foundLastUser = true
                if let msg = obj["message"] as? [String: Any],
                   let text = userText(msg) {
                    let line1 = FileIOHelper.firstLine(text)
                    if isRealInstruction(line1) {
                        lastUserMessage = FileIOHelper.trim(line1, 100)
                    }
                }
            }

            // toolName scan continues past foundLastAssistant until a tool_use is found;
            // tailData 512KB cap bounds the worst case.
            if !lastEventRole.isEmpty && foundLastAssistant && foundLastUser && !toolName.isEmpty { break }
        }

        let project = projectName(cwd: cwd, path: path)
        if title.isEmpty { title = firstInstruction.isEmpty ? project : firstInstruction }
        let sessionId = ((path as NSString).lastPathComponent as NSString).deletingPathExtension

        // duration: 첫 이벤트 ~ 마지막 활동(mtime). 첫 timestamp 없으면 nil.
        let durationSeconds: Int? = firstTimestamp.map { max(0, Int(mtime.timeIntervalSince($0))) }

        // R9a 신뢰성 가드: tail에 서로 다른 세션ID가 섞여 있으면(부분 읽기/브랜치)
        // 최신 usage가 이 세션 것이라 보장 못 함 → 틀린 숫자 대신 미표시.
        if tailSessionIds.count >= 2 { contextTokens = nil }

        // R7 payload 압력: 22MB 미만이면 boundary를 빼도 임계 미달이라 스캔 생략.
        let activePayloadBytes: Int? = size >= payloadWarnBytes
            ? activePayload(path: path, size: size) : nil

        // R10 friction: 오류율 >20%(표본 ≥5) / 방치 갭 >45min (OMC friction-report 임계).
        var frictions: [String] = []
        if toolResults >= 5, Double(toolErrors) / Double(toolResults) > 0.2 {
            frictions.append("도구 오류율 \(toolErrors * 100 / toolResults)% (\(toolErrors)/\(toolResults))")
        }
        // 갭은 "최근에 끝난" 것만(2h) — 어제 닫고 오늘 재개한 세션의 자연 공백은 오탐이라 제외.
        if maxGapSeconds > 45 * 60,
           let end = maxGapEnd, Date().timeIntervalSince(end) < 2 * 3600 {
            frictions.append("\(Int(maxGapSeconds / 60))분 방치 갭")
        }
        let frictionReason = frictions.isEmpty ? nil : frictions.joined(separator: " · ")

        let sessionStatus = SessionStatus(lastActivity: mtime)
        let workState: WorkState
        if lastEventRole == "user" || lastAssistantHasTool {
            workState = .working
        } else if case .active = sessionStatus {
            // Last JSONL event was assistant text, but file was touched within 90s →
            // Claude is likely mid-generation (not yet written to JSONL).
            workState = .working
        } else {
            workState = .responded
        }

        return SessionInfo(
            id: path,
            sessionId: sessionId,
            title: FileIOHelper.trim(title, 70),
            customName: nil,
            projectName: project,
            cwd: cwd,
            gitBranch: gitBranch,
            firstInstruction: FileIOHelper.trim(firstInstruction, 200),
            lastUserMessage: lastUserMessage,
            toolName: toolName,
            toolDetail: FileIOHelper.trim(toolDetail, 60),
            activeSkill: activeSkill,
            lastActivity: mtime,
            messageCount: messageCount,
            workState: workState,
            aiKind: .claude,
            contextTokens: contextTokens,
            durationSeconds: durationSeconds,
            activePayloadBytes: activePayloadBytes,
            isThinking: isThinking,
            frictionReason: frictionReason
        )
    }

    // MARK: - Payload pressure (R7)

    /// 경고 임계 22MB — 이 미만 파일은 스캔 자체를 생략(성능).
    static let payloadWarnBytes = 22 * 1024 * 1024
    static let payloadCritBytes = 26 * 1024 * 1024
    static let payloadLimitBytes = 32 * 1024 * 1024

    /// compact 이후 활성 payload 근사(OMC payload-estimate.ts 방식):
    /// 파일 뒤에서 64KB 청크로 `compact_boundary` 마커를 역스캔, 있으면 size - offset.
    private static func activePayload(path: String, size: Int) -> Int? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return size }
        defer { try? fh.close() }
        let chunk = 65536
        let marker = Data("compact_boundary".utf8)
        var end = size
        while end > 0 {
            let start = max(0, end - chunk)
            guard (try? fh.seek(toOffset: UInt64(start))) != nil,
                  let data = try? fh.read(upToCount: end - start) else { break }
            if let range = data.range(of: marker, options: .backwards) {
                return size - (start + range.lowerBound)   // 마커 위치부터가 활성 payload
            }
            // 청크 경계에 마커가 걸치는 경우 대비, 마커 길이만큼 겹쳐서 후퇴.
            end = start + (start > 0 ? marker.count - 1 : 0)
            if end <= marker.count { break }
        }
        return size   // 마커 없음 = compact 이력 없음 → 전체가 활성
    }

    // MARK: - Field extraction

    private static func captureContext(_ obj: [String: Any], cwd: inout String, branch: inout String) {
        if let c = obj["cwd"] as? String, !c.isEmpty { cwd = c }
        if let b = obj["gitBranch"] as? String, !b.isEmpty { branch = b }
    }

    /// 컨텍스트 창 점유량 = input + cache_read + cache_creation (raw, D4a).
    /// 창에 실제로 들어있는 토큰이므로 가중 없이 합산한다. output은 제외(이미 생성된 것).
    private static func contextTokenSum(_ usage: [String: Any]) -> Int? {
        let input   = usage["input_tokens"] as? Int ?? 0
        let cacheR  = usage["cache_read_input_tokens"] as? Int ?? 0
        let cacheC  = usage["cache_creation_input_tokens"] as? Int ?? 0
        let sum = input + cacheR + cacheC
        return sum > 0 ? sum : nil
    }

    private static let tsFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let tsFormatterPlain = ISO8601DateFormatter()

    private static func parseTimestamp(_ ts: String) -> Date? {
        tsFormatterFractional.date(from: ts) ?? tsFormatterPlain.date(from: ts)
    }

    private static func userText(_ message: [String: Any]) -> String? {
        if let s = message["content"] as? String { return s }
        if let arr = message["content"] as? [[String: Any]] {
            let parts = arr.compactMap { block -> String? in
                (block["type"] as? String) == "text" ? block["text"] as? String : nil
            }
            let joined = parts.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func lastToolUse(_ message: [String: Any]) -> (String, String)? {
        guard let arr = message["content"] as? [[String: Any]] else { return nil }
        for block in arr.reversed() where (block["type"] as? String) == "tool_use" {
            let name = block["name"] as? String ?? "?"
            let input = block["input"] as? [String: Any] ?? [:]
            return (name, summarizeTool(name: name, input: input))
        }
        return nil
    }

    private static func summarizeTool(name: String, input: [String: Any]) -> String {
        func str(_ k: String) -> String { (input[k] as? String) ?? "" }
        switch name {
        case "Bash":
            return FileIOHelper.firstLine(str("command"))
        case "Read", "Edit", "Write", "NotebookEdit":
            return basename(str("file_path"))
        case "Grep":
            return str("pattern")
        case "Glob":
            return str("pattern")
        case "Task", "Agent":
            return str("description")
        case "WebFetch", "WebSearch":
            return str("url").isEmpty ? str("query") : str("url")
        case "TodoWrite":
            return "updating todos"
        default:
            return ""
        }
    }

    private static func isRealInstruction(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.hasPrefix("<") { return false }                 // command/system wrappers
        if t.hasPrefix("Caveat:") { return false }
        if t.hasPrefix("[Request interrupted") { return false }
        if t.hasPrefix("```") { return false }               // code block marker
        return true
    }

    // MARK: - Naming / classification

    private static func projectName(cwd: String, path: String) -> String {
        if !cwd.isEmpty { return (cwd as NSString).lastPathComponent }
        // Fall back to the encoded folder name: -Users-foo-bar -> bar
        let folder = (path as NSString).deletingLastPathComponent
        let name = (folder as NSString).lastPathComponent
        return name.split(separator: "-").last.map(String.init) ?? name
    }

    private static func basename(_ s: String) -> String {
        s.isEmpty ? "" : (s as NSString).lastPathComponent
    }
}
