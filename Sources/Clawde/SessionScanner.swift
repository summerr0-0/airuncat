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

enum SessionCategory: String {
    case dev = "dev"
    case learn = "learn"
}

struct SessionInfo: Identifiable {
    let id: String              // file path (stable & unique)
    let sessionId: String       // UUID stem of the .jsonl (for `claude -r`)
    var title: String           // ai-title or first instruction
    var projectName: String
    var cwd: String
    var gitBranch: String
    var firstInstruction: String
    var toolName: String        // last tool used, e.g. "Bash"
    var toolDetail: String      // summarized arg, e.g. "npx prisma migrate"
    var lastActivity: Date
    var messageCount: Int
    var category: SessionCategory

    var status: SessionStatus { SessionStatus(lastActivity: lastActivity) }
}

/// Reads Claude Code session transcripts from ~/.claude/projects/*/*.jsonl
struct SessionScanner {

    private static let smallFileLimit = 4_000_000          // parse whole file under this
    private static let chunkBytes = 512_000                // head/tail window for big files

    static var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
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

        let forwardLines: [String]
        let backwardLines: [String]
        if size <= smallFileLimit, let data = try? Data(contentsOf: url) {
            let lines = splitLines(data)
            forwardLines = lines
            backwardLines = lines
        } else {
            forwardLines = splitLines(headData(url: url, maxBytes: chunkBytes))
            backwardLines = splitLines(tailData(url: url, size: size, maxBytes: chunkBytes))
        }

        var title = ""
        var firstInstruction = ""
        var cwd = ""
        var gitBranch = ""
        var messageCount = 0

        // Forward pass: title, first real instruction, cwd/branch, rough message count.
        for line in forwardLines {
            guard let obj = json(line) else { continue }
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

        // Backward pass: most recent tool call (= what it's doing now).
        var toolName = ""
        var toolDetail = ""
        for line in backwardLines.reversed() {
            guard let obj = json(line) else { continue }
            captureContext(obj, cwd: &cwd, branch: &gitBranch)
            if obj["type"] as? String == "assistant",
               let msg = obj["message"] as? [String: Any],
               let (name, detail) = lastToolUse(msg) {
                toolName = name
                toolDetail = detail
                break
            }
        }

        let project = projectName(cwd: cwd, path: path)
        if title.isEmpty { title = firstInstruction.isEmpty ? project : firstInstruction }
        let sessionId = ((path as NSString).lastPathComponent as NSString).deletingPathExtension

        return SessionInfo(
            id: path,
            sessionId: sessionId,
            title: trim(title, 70),
            projectName: project,
            cwd: cwd,
            gitBranch: gitBranch,
            firstInstruction: trim(firstInstruction, 200),
            toolName: toolName,
            toolDetail: trim(toolDetail, 60),
            lastActivity: mtime,
            messageCount: messageCount,
            category: categorize(cwd: cwd, path: path)
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
            return firstLine(str("command"))
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

    // MARK: - Low-level IO helpers

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func splitLines(_ data: Data) -> [String] {
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        return s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func headData(url: URL, maxBytes: Int) -> Data {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? fh.close() }
        return (try? fh.read(upToCount: maxBytes)) ?? Data()
    }

    private static func tailData(url: URL, size: Int, maxBytes: Int) -> Data {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? fh.close() }
        let offset = UInt64(max(0, size - maxBytes))
        try? fh.seek(toOffset: offset)
        return (try? fh.readToEnd()) ?? Data()
    }

    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func basename(_ s: String) -> String {
        s.isEmpty ? "" : (s as NSString).lastPathComponent
    }

    private static func trim(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n)) + "…"
    }
}
