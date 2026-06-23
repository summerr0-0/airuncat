import Foundation

/// Reads Gemini CLI session transcripts from ~/.gemini/tmp/*/chats/*.jsonl
struct GeminiScanner {

    private static let maxAge: TimeInterval = 48 * 3600

    /// Absolute path to the gemini binary; nil if not installed.
    static let geminiPath: String? = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "which gemini 2>/dev/null"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }()

    static var isAvailable: Bool { geminiPath != nil }

    static var tmpDir: URL {
        URL(fileURLWithPath: PathConstants.geminiTmp, isDirectory: true)
    }

    static func scan(cache: inout [String: (mtime: Date, info: SessionInfo)]) -> [SessionInfo] {
        guard isAvailable else { return [] }
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [SessionInfo] = []
        var seen = Set<String>()
        let cutoff = Date().addingTimeInterval(-maxAge)

        for dir in projectDirs {
            let chatsDir = dir.appendingPathComponent("chats")
            guard let files = try? fm.contentsOfDirectory(
                at: chatsDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: []
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let path = file.path
                seen.insert(path)
                let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = attrs?.contentModificationDate ?? Date.distantPast
                let size  = attrs?.fileSize ?? 0

                if mtime < cutoff { continue }   // skip files older than 48 hours

                if let cached = cache[path], cached.mtime == mtime {
                    result.append(cached.info)
                    continue
                }
                if let info = parse(path: path, size: size, mtime: mtime, projectDir: dir) {
                    cache[path] = (mtime, info)
                    result.append(info)
                }
            }
        }

        for key in cache.keys where !seen.contains(key) { cache.removeValue(forKey: key) }
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Parse one session file

    private static func parse(path: String, size: Int, mtime: Date, projectDir: URL) -> SessionInfo? {
        let url = URL(fileURLWithPath: path)

        let (forwardLines, backwardLines) = FileIOHelper.readLines(url: url, size: size)

        guard !forwardLines.isEmpty else { return nil }

        // Line 1 must be the header with sessionId
        guard let header = FileIOHelper.jsonObject(forwardLines[0]),
              let sessionId = header["sessionId"] as? String,
              !sessionId.isEmpty else { return nil }

        var cwd = ""
        var title = ""
        var messageCount = 0
        var cwdFound = false
        var titleFound = false

        // Forward pass: extract cwd + title
        for line in forwardLines.dropFirst() {
            guard let obj = FileIOHelper.jsonObject(line) else { continue }

            // Handle legacy $set batch format (contains all initial messages)
            if let setObj = obj["$set"] as? [String: Any],
               let msgs = setObj["messages"] as? [[String: Any]] {
                for msg in msgs where (msg["type"] as? String) == "user" {
                    if let text = userText(msg) {
                        if !cwdFound, let extracted = extractCwd(from: text) {
                            cwd = extracted; cwdFound = true
                        }
                    }
                }
                continue
            }

            let type = obj["type"] as? String
            if type == "user" {
                messageCount += 1
                if let text = userText(obj) {
                    if !cwdFound, let extracted = extractCwd(from: text) {
                        cwd = extracted; cwdFound = true
                    }
                    if !titleFound, isRealInstruction(text) {
                        title = FileIOHelper.trim(text, 200); titleFound = true
                    }
                }
            } else if type == "gemini" {
                messageCount += 1
            }
        }

        let projectName = cwd.isEmpty
            ? projectDir.lastPathComponent
            : (cwd as NSString).lastPathComponent

        if title.isEmpty { title = projectName }

        // Backward pass: determine workState + last user message + toolCalls + model
        var workState: WorkState = .working
        var lastUserMessage = ""
        var toolName = ""
        var toolDetail = ""
        var modelName: String? = nil
        var foundWorkState = false
        var foundLastUser = false
        var foundTool = false

        let preferredKeys = ["file_path", "path", "command", "query"]
        let fileKeys: Set<String> = ["file_path", "path"]

        for line in backwardLines.reversed() {
            guard let obj = FileIOHelper.jsonObject(line) else { continue }
            let type = obj["type"] as? String

            if !foundWorkState {
                if type == "user"   { workState = .working;   foundWorkState = true }
                if type == "gemini" { workState = .responded; foundWorkState = true }
            }

            if !foundLastUser, type == "user" {
                foundLastUser = true
                if let text = userText(obj) {
                    let line1 = FileIOHelper.firstLine(text)
                    if isRealInstruction(line1) {
                        lastUserMessage = FileIOHelper.trim(line1, 100)
                    }
                }
            }

            if type == "gemini" {
                if modelName == nil, let m = obj["model"] as? String, !m.isEmpty {
                    modelName = m
                }
                if !foundTool,
                   let calls = obj["toolCalls"] as? [[String: Any]],
                   let lastCall = calls.last,
                   let name = lastCall["name"] as? String, !name.isEmpty {
                    let args = lastCall["args"] as? [String: Any] ?? [:]
                    var detail = ""
                    for key in preferredKeys {
                        if let val = args[key] as? String, !val.isEmpty {
                            detail = fileKeys.contains(key)
                                ? (val as NSString).lastPathComponent
                                : val
                            break
                        }
                    }
                    if detail.isEmpty {
                        detail = args.keys.sorted().compactMap { args[$0] as? String }.first ?? ""
                    }
                    toolName = name
                    toolDetail = FileIOHelper.trim(detail, 60)
                    foundTool = true
                }
            }
        }

        return SessionInfo(
            id: path,
            sessionId: sessionId,
            title: title,
            customName: nil,
            projectName: projectName,
            cwd: cwd,
            gitBranch: "",
            firstInstruction: title,
            lastUserMessage: lastUserMessage,
            toolName: toolName,
            toolDetail: toolDetail,
            activeSkill: nil,
            lastActivity: mtime,
            messageCount: messageCount,
            category: .dev,
            workState: workState,
            aiKind: .gemini,
            modelName: modelName
        )
    }

    // MARK: - CWD extraction

    private static func extractCwd(from text: String) -> String? {
        guard let range = text.range(of: "Workspace Directories:") else { return nil }
        for line in text[range.upperBound...].split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("- ") {
                let p = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !p.isEmpty && p.hasPrefix("/") { return p }
            }
        }
        return nil
    }

    // MARK: - Text helpers

    private static func userText(_ obj: [String: Any]) -> String? {
        if let arr = obj["content"] as? [[String: Any]] {
            let parts = arr.compactMap { $0["text"] as? String }
            let joined = parts.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
        if let s = obj["content"] as? String { return s }
        return nil
    }

    private static func isRealInstruction(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.contains("<session_context>") { return false }
        if t.hasPrefix("<") { return false }
        if t.hasPrefix("```") { return false }
        return true
    }

}
