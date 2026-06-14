import AppKit

/// Drives iTerm2 via AppleScript to focus the existing tab running a session,
/// or open a new one. Unlike Warp, iTerm2 has full AppleScript support, so we
/// can enumerate sessions, read each session's TTY, map TTY -> working dir, and
/// select the exact tab.
enum ITermController {

    static let bundleID = "com.googlecode.iterm2"
    static let logPath = "/tmp/airuncat-focus.log"

    /// Focus the existing iTerm tab for `session`, else open a new one.
    static func open(_ session: SessionInfo) {
        if focus(for: session) { return }
        openNew(session)
    }

    // MARK: - Focus existing

    @discardableResult
    static func focus(for session: SessionInfo) -> Bool {
        var diag = ["--- iterm focus \(Date()) ---",
                    "session cwd=\(session.cwd) title=\(session.title)"]
        defer { writeLog(diag.joined(separator: "\n")) }

        guard !session.cwd.isEmpty else { diag.append("no cwd; cannot match."); return false }
        guard let id = findSessionID(for: session.cwd, diag: &diag) else {
            diag.append("no iTerm tab matches cwd.")
            return false
        }

        let focusScript = """
        tell application id "\(bundleID)"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if (id of s) is "\(id)" then
                  tell t to select
                  tell s to select
                  activate
                  return "ok"
                end if
              end repeat
            end repeat
          end repeat
          return "notfound"
        end tell
        """
        let r = runAppleScript(focusScript, diag: &diag)
        diag.append("focus result: \(r ?? "nil")")
        return r == "ok"
    }

    // MARK: - Open new

    static func openNew(_ session: SessionInfo) {
        let dir = session.cwd.isEmpty ? NSHomeDirectory() : session.cwd
        let cmd: String
        switch session.aiKind {
        case .claude:
            cmd = "cd '\(shellEscapeSingle(dir))' && claude -r \(session.sessionId)"
        case .gemini:
            let exe = shellEscapeSingle(GeminiScanner.geminiPath ?? "gemini")
            cmd = "cd '\(shellEscapeSingle(dir))' && \(exe)"
        }
        // Open in a new tab of the existing window if one exists; otherwise create a window.
        let script = """
        tell application id "\(bundleID)"
          if (count of windows) > 0 then
            tell current window to create tab with default profile
          else
            create window with default profile
          end if
          tell current session of current window to write text "\(appleScriptEscape(cmd))"
          activate
        end tell
        """
        var diag = ["--- iterm openNew \(Date()) --- cmd=\(cmd)"]
        _ = runAppleScript(script, diag: &diag)
        writeLog(diag.joined(separator: "\n"))
    }

    // MARK: - Insert text (Prompt Library)

    /// Write `text` to the clipboard then Cmd+V into the iTerm tab matching `cwd`.
    /// Returns true on success. Caller is responsible for writing to clipboard before calling.
    @discardableResult
    static func insertText(cwd: String) -> Bool {
        var diag = ["--- iterm insertText \(Date()) cwd=\(cwd) ---"]
        defer { writeLog(diag.joined(separator: "\n")) }
        guard !cwd.isEmpty else { return false }

        guard let id = findSessionID(for: cwd, diag: &diag) else {
            diag.append("no iTerm tab matches cwd")
            return false
        }

        // Activate the matching session, then Cmd+V via System Events.
        let pasteScript = """
        tell application id "\(bundleID)"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if (id of s) is "\(id)" then
                  tell t to select
                  tell s to select
                  activate
                end if
              end repeat
            end repeat
          end repeat
        end tell
        delay 0.2
        tell application "System Events"
          keystroke "v" using {command down}
        end tell
        return "ok"
        """
        let r = runAppleScript(pasteScript, diag: &diag)
        diag.append("insertText result: \(r ?? "nil")")
        return r == "ok"
    }

    // MARK: - Session lookup

    /// Returns the iTerm2 session ID whose cwd matches `cwd`, or nil if not found.
    private static func findSessionID(for cwd: String, diag: inout [String]) -> String? {
        let listScript = """
        tell application id "\(bundleID)"
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                set out to out & (id of s) & "\t" & (tty of s) & linefeed
              end repeat
            end repeat
          end repeat
          return out
        end tell
        """
        guard let listed = runAppleScript(listScript, diag: &diag) else {
            diag.append("could not list iTerm sessions (not running / not authorized).")
            return nil
        }
        for line in listed.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let sid = parts[0], tty = parts[1]
            let dirs = cwdsForTTY(tty)
            diag.append("session \(sid) tty=\(tty) cwds=\(dirs)")
            let match = dirs.contains { dir in
                dir == cwd || cwd.hasPrefix(dir + "/") || dir.hasPrefix(cwd + "/")
            }
            if match { return sid }
        }
        return nil
    }

    // MARK: - TTY -> cwd

    private static func cwdsForTTY(_ tty: String) -> [String] {
        let name = (tty as NSString).lastPathComponent   // /dev/ttys005 -> ttys005
        guard !name.isEmpty else { return [] }
        let pidOut = runProcess("/bin/ps", ["-t", name, "-o", "pid="])
        let pids = pidOut.split(whereSeparator: { $0 == "\n" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var dirs = Set<String>()
        for pid in pids {
            let out = runProcess("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pid, "-Fn"])
            for line in out.split(separator: "\n") where line.hasPrefix("n") {
                dirs.insert(String(line.dropFirst()))
            }
        }
        return Array(dirs)
    }

    // MARK: - Helpers

    private static func runAppleScript(_ source: String, diag: inout [String]) -> String? {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let res = script.executeAndReturnError(&err)
        if let err = err {
            let msg = err["NSAppleScriptErrorMessage"] ?? err
            diag.append("AppleScript error: \(msg)")
            return nil
        }
        return res.stringValue
    }

    private static func runProcess(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func shellEscapeSingle(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func writeLog(_ s: String) {
        let line = s + "\n\n"
        let url = URL(fileURLWithPath: logPath)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            if let d = line.data(using: .utf8) { h.write(d) }
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}
