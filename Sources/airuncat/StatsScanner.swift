import Foundation

// MARK: - Models

struct SessionStat: Codable, Sendable {
    let path: String
    let mtime: TimeInterval
    let date: String          // "YYYY-MM-DD"
    let dayOfWeek: Int        // 0=Mon .. 6=Sun
    let hourOfDay: Int        // 0 .. 23
    let durationMinutes: Int  // capped at 120
    let skillsUsed: [String]
}

struct StatsData: Codable, Sendable {
    var sessions: [SessionStat]
    var pathMtimes: [String: TimeInterval]

    static let empty = StatsData(sessions: [], pathMtimes: [:])
}

// MARK: - Scanner

enum StatsScanner {
    static var cachePath: String { PathConstants.statsCache }
    private static var projectsDir: String { PathConstants.claudeProjects }
    private static let maxCacheAge: TimeInterval = 180 * 24 * 3600  // 6 months

    static func scan() -> StatsData {
        var data = loadCache()
        let fm = FileManager.default

        // Enumerate all JSONL files
        var currentPaths = Set<String>()
        if let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) {
            for proj in projectDirs {
                let projPath = (projectsDir as NSString).appendingPathComponent(proj)
                guard let files = try? fm.contentsOfDirectory(atPath: projPath) else { continue }
                for file in files where file.hasSuffix(".jsonl") {
                    let fullPath = (projPath as NSString).appendingPathComponent(file)
                    currentPaths.insert(fullPath)
                }
            }
        }

        // Remove deleted paths
        let deletedPaths = Set(data.pathMtimes.keys).subtracting(currentPaths)
        data.sessions.removeAll { deletedPaths.contains($0.path) }
        for p in deletedPaths { data.pathMtimes.removeValue(forKey: p) }

        // Re-parse changed/new files
        for path in currentPaths {
            guard let mtime = FileIOHelper.mtimeInterval(at: path) else { continue }
            if let cached = data.pathMtimes[path], cached == mtime { continue }

            // Remove old entry if exists
            data.sessions.removeAll { $0.path == path }

            if let stat = parseStat(path: path, mtime: mtime) {
                data.sessions.append(stat)
            }
            data.pathMtimes[path] = mtime
        }

        saveCache(data)
        return data
    }

    // MARK: - Parse one file

    private static func parseStat(path: String, mtime: TimeInterval) -> SessionStat? {
        let mtimeDate = Date(timeIntervalSince1970: mtime)

        // Derive date/dayOfWeek/hourOfDay from mtime
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .weekday], from: mtimeDate)
        guard let year = comps.year, let month = comps.month,
              let day = comps.day, let hour = comps.hour,
              let weekday = comps.weekday else { return nil }

        let dateStr = String(format: "%04d-%02d-%02d", year, month, day)
        // Calendar weekday: 1=Sun..7=Sat → convert to 0=Mon..6=Sun
        let dayOfWeek = (weekday + 5) % 7

        // Duration: last event timestamp - first user timestamp (capped at 120min)
        // Using event timestamps avoids mtime-based over-counting (mtime can be days after session end)
        let startTime = readStartTimestamp(path: path) ?? mtime - 1800
        let endTime   = readEndTimestamp(path: path) ?? startTime
        let durationSecs = max(0, endTime - startTime)
        let durationMinutes = min(120, Int(durationSecs / 60))

        // Scan skills — full file up to 4MB, else head+tail 512KB
        let skills = readSkillsUsed(path: path)

        return SessionStat(
            path: path,
            mtime: mtime,
            date: dateStr,
            dayOfWeek: dayOfWeek,
            hourOfDay: hour,
            durationMinutes: durationMinutes,
            skillsUsed: skills
        )
    }

    private static func readStartTimestamp(path: String) -> TimeInterval? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 65536),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  (json["type"] as? String) == "user",
                  let ts = json["timestamp"] as? String else { continue }
            if let date = iso.date(from: ts) ?? iso2.date(from: ts) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    private static func readEndTimestamp(path: String) -> TimeInterval? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        guard let eof = try? fh.seekToEnd() else { return nil }
        let tailStart = max(0, Int(eof) - 16384)
        guard (try? fh.seek(toOffset: UInt64(tailStart))) != nil,
              let data = try? fh.read(upToCount: 16384),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        // Scan lines in reverse for the last event with a timestamp
        let lines = text.components(separatedBy: "\n").reversed()
        for line in lines {
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ts = json["timestamp"] as? String else { continue }
            if let date = iso.date(from: ts) ?? iso2.date(from: ts) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    private static func readSkillsUsed(path: String) -> [String] {
        var st = stat()
        let size = (lstat(path, &st) == 0) ? Int(st.st_size) : 0
        let url = URL(fileURLWithPath: path)
        let (fwd, bwd) = FileIOHelper.readLines(url: url, size: size)
        // For large files, fwd and bwd are different chunks; concatenate for full coverage.
        // For small files, both point to the same lines — deduplicate.
        let lines = size <= FileIOHelper.smallFileLimit ? fwd : fwd + bwd

        var skills: [String] = []
        for line in lines {
            guard let json = FileIOHelper.jsonObject(line),
                  (json["type"] as? String) == "assistant",
                  let message = json["message"] as? [String: Any],
                  let contentArr = message["content"] as? [[String: Any]] else { continue }
            for block in contentArr
                where (block["type"] as? String) == "tool_use"
                   && (block["name"] as? String) == "Skill" {
                if let input = block["input"] as? [String: Any],
                   let skillName = input["skill"] as? String {
                    skills.append(skillName)
                }
            }
        }
        return skills
    }

    // MARK: - Cache IO

    private static func loadCache() -> StatsData {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
              var decoded = try? JSONDecoder().decode(StatsData.self, from: data) else {
            return .empty
        }
        // Prune entries older than 6 months to prevent unbounded cache growth.
        let cutoff = Date().timeIntervalSince1970 - maxCacheAge
        let stale = Set(decoded.sessions.filter { $0.mtime < cutoff }.map { $0.path })
        if !stale.isEmpty {
            decoded.sessions.removeAll { stale.contains($0.path) }
            stale.forEach { decoded.pathMtimes.removeValue(forKey: $0) }
        }
        return decoded
    }

    private static func saveCache(_ data: StatsData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        let url = URL(fileURLWithPath: cachePath)
        let dir = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try? encoded.write(to: url, options: .atomic)
    }
}
