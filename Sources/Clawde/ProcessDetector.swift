import Foundation

struct ProcessDetector {

    /// Returns the set of cwds that have a live `claude` process attached.
    static func liveCwds() -> Set<String> {
        guard let pidsOut = shell("pgrep -x claude 2>/dev/null"), !pidsOut.isEmpty else {
            return []
        }
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
