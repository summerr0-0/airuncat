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
    static let cachePath: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".airuncat/stats-cache.json")

    private static let projectsDir: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")

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
            var statInfo = stat()
            guard lstat(path, &statInfo) == 0 else { continue }
            let mtime = Double(statInfo.st_mtimespec.tv_sec)
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
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? Int else { return [] }

        let maxFull: Int = 4 * 1024 * 1024  // 4MB
        let chunkSize: Int = 512 * 1024      // 512KB

        let text: String?
        if fileSize <= maxFull {
            text = try? String(contentsOfFile: path, encoding: .utf8)
        } else {
            guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
            defer { try? fh.close() }
            var combined = Data()
            if let head = try? fh.read(upToCount: chunkSize) { combined.append(head) }
            if let eof = try? fh.seekToEnd() {
                let tailStart = max(0, Int(eof) - chunkSize)
                try? fh.seek(toOffset: UInt64(tailStart))
                if let tail = try? fh.read(upToCount: chunkSize) { combined.append(tail) }
            }
            text = String(data: combined, encoding: .utf8)
        }

        guard let content = text else { return [] }

        var skills: [String] = []
        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
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
              let decoded = try? JSONDecoder().decode(StatsData.self, from: data) else {
            return .empty
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
