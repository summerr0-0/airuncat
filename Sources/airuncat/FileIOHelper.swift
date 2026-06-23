import Foundation

/// Shared file I/O primitives for JSONL scanners.
/// Centralises the head/tail-read pattern, JSON line parsing, and string utilities
/// that were previously duplicated in SessionScanner, GeminiScanner, and StatsScanner.
enum FileIOHelper {
    static let smallFileLimit = 4_000_000   // parse whole file under this size
    static let chunkBytes     = 512_000     // head/tail window for large files

    // MARK: - Data reading

    static func readLines(url: URL, size: Int) -> (forward: [String], backward: [String]) {
        if size <= smallFileLimit, let data = try? Data(contentsOf: url) {
            let lines = splitLines(data)
            return (lines, lines)
        }
        return (
            splitLines(headData(url: url, maxBytes: chunkBytes)),
            splitLines(tailData(url: url, size: size, maxBytes: chunkBytes))
        )
    }

    static func headData(url: URL, maxBytes: Int) -> Data {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? fh.close() }
        return (try? fh.read(upToCount: maxBytes)) ?? Data()
    }

    static func tailData(url: URL, size: Int, maxBytes: Int) -> Data {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? fh.close() }
        let offset = UInt64(max(0, size - maxBytes))
        try? fh.seek(toOffset: offset)
        return (try? fh.readToEnd()) ?? Data()
    }

    static func splitLines(_ data: Data) -> [String] {
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        return s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - Parsing

    static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    // MARK: - String utilities

    static func firstLine(_ s: String) -> String {
        s.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    static func trim(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n)) + "…"
    }

    // MARK: - Filesystem metadata

    /// Returns the file's last-modified date via lstat (does not follow symlinks).
    static func mtime(at path: String) -> Date {
        var st = stat()
        guard lstat(path, &st) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
    }

    /// Returns the mtime as a raw TimeInterval for cache keys.
    static func mtimeInterval(at path: String) -> TimeInterval? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Double(st.st_mtimespec.tv_sec)
    }
}
