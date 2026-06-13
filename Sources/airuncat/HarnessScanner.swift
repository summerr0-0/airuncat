import Foundation
import CryptoKit

// MARK: - Models

struct RuleFile: Identifiable {
    let id: String   // stem (also used as display name)
    let path: String
}

struct HookEntry: Identifiable {
    let id: String            // SHA256(event+matcher+command)[0..<8]
    let event: String         // "PreToolUse" | "PostToolUse"
    let matcher: String
    let commandSummary: String
    var enabled: Bool
}

struct HarnessInfo {
    let projectPath: String
    let settingsPath: String
    var settingsMtime: Date
    var rules: [RuleFile]
    var hooks: [HookEntry]
    var omcPresent: Bool
    var writeError: String?

    var enabledHookCount: Int { hooks.filter(\.enabled).count }
    var totalCount: Int { rules.count + hooks.count }
    var activeCount: Int { rules.count + enabledHookCount }
    var hasDisabledHook: Bool { hooks.contains { !$0.enabled } }

    var badgeLabel: String {
        guard totalCount > 0 else { return "" }
        if activeCount == totalCount { return "H \(totalCount)" }
        return "H \(activeCount)/\(totalCount)"
    }
}

// MARK: - Scanner

enum HarnessScanner {
    static func scan(cwd: String) -> HarnessInfo? {
        let claudeDir = (cwd as NSString).appendingPathComponent(".claude")
        guard FileManager.default.fileExists(atPath: claudeDir) else { return nil }

        let settingsPath = (claudeDir as NSString).appendingPathComponent("settings.json")
        let settingsMtime = mtime(of: settingsPath) ?? Date()

        let rules = scanRules(claudeDir: claudeDir)
        let hooks = scanHooks(settingsPath: settingsPath)
        let omcPresent = detectOMC(cwd: cwd)

        return HarnessInfo(
            projectPath: cwd,
            settingsPath: settingsPath,
            settingsMtime: settingsMtime,
            rules: rules,
            hooks: hooks,
            omcPresent: omcPresent
        )
    }

    // MARK: - Helpers

    private static func scanRules(claudeDir: String) -> [RuleFile] {
        let rulesDir = (claudeDir as NSString).appendingPathComponent("rules")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: rulesDir) else { return [] }
        return items
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { filename in
                let stem = String(filename.dropLast(3))
                let path = (rulesDir as NSString).appendingPathComponent(filename)
                return RuleFile(id: stem, path: path)
            }
    }

    private static func scanHooks(settingsPath: String) -> [HookEntry] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var entries: [HookEntry] = []
        entries += parseHookSection(json["hooks"], enabled: true)
        entries += parseHookSection(json["_disabledHooks"], enabled: false)
        return entries
    }

    private static func parseHookSection(_ section: Any?, enabled: Bool) -> [HookEntry] {
        guard let dict = section as? [String: Any] else { return [] }
        var entries: [HookEntry] = []
        for (event, groups) in dict {
            guard let groupArray = groups as? [[String: Any]] else { continue }
            for group in groupArray {
                let matcher = group["matcher"] as? String ?? ""
                let hooks = group["hooks"] as? [[String: Any]] ?? []
                let firstCmd = hooks.first?["command"] as? String ?? ""
                let summary = String(firstCmd.prefix(70))
                let hookCount = hooks.count
                let displaySummary = hookCount > 1 ? "\(summary) (외 \(hookCount - 1)개)" : summary
                let entryId = hookHash(event: event, matcher: matcher, command: firstCmd)
                entries.append(HookEntry(
                    id: entryId,
                    event: event,
                    matcher: matcher,
                    commandSummary: displaySummary,
                    enabled: enabled
                ))
            }
        }
        return entries.sorted { $0.event < $1.event || ($0.event == $1.event && $0.matcher < $1.matcher) }
    }

    static func hookHash(event: String, matcher: String, command: String) -> String {
        let input = Data((event + matcher + command).utf8)
        let digest = SHA256.hash(data: input)
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func detectOMC(cwd: String) -> Bool {
        let claudeMd = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        guard let content = try? String(contentsOfFile: claudeMd, encoding: .utf8) else { return false }
        return content.contains("oh-my-claudecode") || content.contains("OMC(")
    }

    static func mtime(of path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
    }
}
