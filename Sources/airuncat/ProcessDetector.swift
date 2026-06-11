import Foundation

struct ProcessDetector {

    /// Returns the set of cwds that have a live `claude` process attached.
    static func liveCwds() -> Set<String> {
        cwdsForProcessName("claude")
    }

    /// Returns the set of cwds that have a live `gemini` process attached.
    /// Gemini CLI is a Node.js script so comm shows as "node"; match by gemini binary path in args.
    static func liveGeminiCwds() -> Set<String> {
        guard let geminiExe = GeminiScanner.geminiPath else { return [] }
        let safe = shellEscapeSingle(geminiExe)
        guard let pidsOut = shell(
            // -F: fixed-string match (no regex); single-quote escaping handles path special chars.
            "ps -eo pid,args | grep -F '\(safe)' | grep -v grep | awk '{print $1}' 2>/dev/null"
        ), !pidsOut.isEmpty else { return [] }
        return cwdsForPids(pidsOut)
    }

    private static func shellEscapeSingle(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func cwdsForProcessName(_ name: String) -> Set<String> {
        // pgrep -x misses foreground (S+) processes on macOS; use ps instead.
        guard let pidsOut = shell("ps -eo pid,comm | awk '$2==\"\(name)\"{print $1}' 2>/dev/null"),
              !pidsOut.isEmpty else {
            return []
        }
        return cwdsForPids(pidsOut)
    }

    private static func cwdsForPids(_ pidsOut: String) -> Set<String> {
        let pids = pidsOut.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        var cwds = Set<String>()
        for pid in pids {
            // awk: skip header (NR>1), match cwd fd, print last field (path)
            if let cwd = shell("lsof -p \(pid) 2>/dev/null | awk 'NR>1 && $4==\"cwd\"{print $NF}'") {
                let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { cwds.insert(trimmed) }
            }
        }
        return cwds
    }

    private static func shell(_ cmd: String, timeout: TimeInterval = 3.0) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", cmd]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let sema = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in sema.signal() }
        guard sema.wait(timeout: .now() + timeout) == .success else {
            proc.terminate()
            return nil
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
