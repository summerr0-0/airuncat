import Foundation

// MARK: - Models

/// 한 assistant 메시지의 소비 이벤트(D4b). weighted = input + output + cache_creation + 0.1×cache_read.
struct UsageEvent: Codable, Sendable {
    let ts: TimeInterval   // 메시지 timestamp (epoch)
    let weighted: Int      // 가중 소비 토큰
}

struct UsageFileCache: Codable, Sendable {
    var files: [String: FileEntry]   // path -> entry

    struct FileEntry: Codable, Sendable {
        let mtime: TimeInterval
        let events: [UsageEvent]
    }

    static let empty = UsageFileCache(files: [:])
}

// MARK: - Scanner

/// 전체 Claude 세션 JSONL에서 메시지별 소비 이벤트를 수집한다(D4b, R3).
/// 창 범위(주간=최대 8일) 밖 파일은 스킵하고, mtime 증분 캐시로 재파싱을 피한다(C2).
enum UsageScanner {

    /// 주간 창(최대 7일) + 여유. 이보다 오래된 파일은 창에 기여 불가 → 스킵.
    private static let windowHorizon: TimeInterval = 8 * 24 * 3600

    private static var cachePath: String { PathConstants.airuncatBase + "/usage-cache.json" }
    private static var projectsDir: String { PathConstants.claudeProjects }

    /// 현재 시각 기준 창 지평 안의 모든 소비 이벤트.
    static func scan(now: TimeInterval) -> [UsageEvent] {
        var cache = loadCache()
        let fm = FileManager.default
        let cutoff = now - windowHorizon

        var currentPaths = Set<String>()
        if let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) {
            for proj in projectDirs {
                let projPath = (projectsDir as NSString).appendingPathComponent(proj)
                guard let files = try? fm.contentsOfDirectory(atPath: projPath) else { continue }
                for file in files where file.hasSuffix(".jsonl") {
                    currentPaths.insert((projPath as NSString).appendingPathComponent(file))
                }
            }
        }

        // 삭제/지평 밖 파일을 캐시에서 제거.
        for path in Array(cache.files.keys) where !currentPaths.contains(path) {
            cache.files.removeValue(forKey: path)
        }

        var events: [UsageEvent] = []
        for path in currentPaths {
            guard let mtime = FileIOHelper.mtimeInterval(at: path) else { continue }
            if mtime < cutoff {                       // 창 밖 파일 스킵(C2)
                cache.files.removeValue(forKey: path)
                continue
            }
            if let cached = cache.files[path], cached.mtime == mtime {
                events.append(contentsOf: cached.events)
                continue
            }
            let parsed = parseEvents(path: path)
            cache.files[path] = UsageFileCache.FileEntry(mtime: mtime, events: parsed)
            events.append(contentsOf: parsed)
        }

        saveCache(cache)
        return events
    }

    // MARK: - Parse one file

    private static func parseEvents(path: String) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        var out: [UsageEvent] = []
        for line in FileIOHelper.splitLines(data) {
            guard let obj = FileIOHelper.jsonObject(line),
                  (obj["type"] as? String) == "assistant",
                  let tsStr = obj["timestamp"] as? String,
                  let ts = parseTimestamp(tsStr),
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { continue }
            let w = weightedTokens(usage)
            if w > 0 { out.append(UsageEvent(ts: ts.timeIntervalSince1970, weighted: w)) }
        }
        return out
    }

    /// 소비 메트릭(D4b, 개정): input + output + cache_creation.
    /// cache_read(매 턴 컨텍스트 재읽기)는 새 작업이 아니고 실측상 소비를 지배(5h에 raw 181M,
    /// 나머지의 ~10배)하며 Claude 실제 한도엔 거의 안 잡혀 **제외**한다.
    private static func weightedTokens(_ usage: [String: Any]) -> Int {
        let input  = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheC = usage["cache_creation_input_tokens"] as? Int ?? 0
        return input + output + cacheC
    }

    private static let tsFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let tsPlain = ISO8601DateFormatter()
    private static func parseTimestamp(_ ts: String) -> Date? {
        tsFractional.date(from: ts) ?? tsPlain.date(from: ts)
    }

    // MARK: - Cache IO

    private static func loadCache() -> UsageFileCache {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
              let decoded = try? JSONDecoder().decode(UsageFileCache.self, from: data) else {
            return .empty
        }
        return decoded
    }

    private static func saveCache(_ cache: UsageFileCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        let url = URL(fileURLWithPath: cachePath)
        let dir = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: url, options: .atomic)
    }
}
