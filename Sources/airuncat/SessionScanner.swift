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

enum SessionCategory: String {
    case dev = "dev"
    case learn = "learn"
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
    var category: SessionCategory
    var workState: WorkState
    var aiKind: AIKind
    var modelName: String? = nil  // Gemini model string; nil for Claude

    var status: SessionStatus { SessionStatus(lastActivity: lastActivity) }
    var displayName: String { customName ?? projectName }
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

        // Forward pass: title, first real instruction, cwd/branch, rough message count.
        for line in forwardLines {
            guard let obj = FileIOHelper.jsonObject(line) else { continue }
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
        var completedToolIds = Set<String>()  // tool_use IDs that already have a tool_result
        var activeSkill: String? = nil
        var foundSkillCheck = false           // true once we've examined the most recent Skill call

        for line in backwardLines.reversed() {
            guard let obj = FileIOHelper.jsonObject(line) else { continue }
            captureContext(obj, cwd: &cwd, branch: &gitBranch)
            let evType = obj["type"] as? String ?? ""
            guard evType == "user" || evType == "assistant" else { continue }

            if lastEventRole.isEmpty { lastEventRole = evType }

            // Collect completed tool IDs from tool_result blocks in user events.
            // Going backward, tool_results appear before their corresponding tool_use,
            // so completedToolIds is populated before we check the Skill tool_use below.
            if evType == "user",
               let msg = obj["message"] as? [String: Any],
               let arr = msg["content"] as? [[String: Any]] {
                for block in arr where (block["type"] as? String) == "tool_result" {
                    if let id = block["tool_use_id"] as? String { completedToolIds.insert(id) }
                }
            }

            if evType == "assistant" {
                if !foundLastAssistant {
                    foundLastAssistant = true
                    if let msg = obj["message"] as? [String: Any],
                       let (name, detail) = lastToolUse(msg) {
                        toolName = name
                        toolDetail = detail
                        lastAssistantHasTool = true
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
            category: categorize(cwd: cwd, path: path),
            workState: workState,
            aiKind: .claude
        )
    }

    // MARK: - Field extraction

    private static func captureContext(_ obj: [String: Any], cwd: inout String, branch: inout String) {
        if let c = obj["cwd"] as? String, !c.isEmpty { cwd = c }
        if let b = obj["gitBranch"] as? String, !b.isEmpty { branch = b }
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

    private static func categorize(cwd: String, path: String) -> SessionCategory {
        let hay = (cwd + " " + path).lowercased()
        let learnKeys = ["obsidian", "english", "algorithm", "interview", "study/english"]
        for k in learnKeys where hay.contains(k) { return .learn }
        return .dev
    }

    private static func basename(_ s: String) -> String {
        s.isEmpty ? "" : (s as NSString).lastPathComponent
    }
}
