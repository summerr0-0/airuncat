import Foundation

enum HarnessManager {
    // MARK: - Toggle

    /// Toggle a hook's enabled state in settings.json.
    /// Returns updated HarnessInfo on success, or sets writeError on failure.
    static func toggle(hook: HookEntry, in info: HarnessInfo) -> HarnessInfo {
        var updated = info
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: info.settingsPath)),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            updated.writeError = "settings.json 읽기 실패"
            return updated
        }

        // Race condition guard: check mtime
        if let current = HarnessScanner.mtime(of: info.settingsPath),
           abs(current.timeIntervalSince(info.settingsMtime)) > 1 {
            updated.writeError = "외부에서 변경됨 — 재스캔 후 다시 시도"
            return updated
        }

        let targetEnabled = !hook.enabled
        let srcKey  = hook.enabled ? "hooks"          : "_disabledHooks"
        let dstKey  = hook.enabled ? "_disabledHooks" : "hooks"

        guard let group = extractGroup(id: hook.id, from: &json, key: srcKey, event: hook.event) else {
            updated.writeError = "hook을 찾지 못했습니다 (id: \(hook.id))"
            return updated
        }

        insertGroup(group, into: &json, key: dstKey, event: hook.event)

        if let err = writeJSON(json, to: info.settingsPath) {
            updated.writeError = err
            return updated
        }

        // Reflect state locally without re-scan
        if let idx = updated.hooks.firstIndex(where: { $0.id == hook.id }) {
            updated.hooks[idx].enabled = targetEnabled
        }
        updated.settingsMtime = HarnessScanner.mtime(of: info.settingsPath) ?? info.settingsMtime
        updated.writeError = nil
        return updated
    }

    // MARK: - Permission add/remove

    static func addPermission(pattern: String, kind: PermissionKind, in info: HarnessInfo) -> HarnessInfo {
        var updated = info
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: info.settingsPath)),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            updated.writeError = "settings.json 읽기 실패"
            return updated
        }
        if let current = HarnessScanner.mtime(of: info.settingsPath),
           abs(current.timeIntervalSince(info.settingsMtime)) > 1 {
            updated.writeError = "외부에서 변경됨 — 재스캔 후 다시 시도"
            return updated
        }

        var perms = json["permissions"] as? [String: Any] ?? [:]
        var list = perms[kind.rawValue] as? [String] ?? []
        guard !list.contains(pattern) else {
            updated.writeError = "이미 존재: \(pattern)"
            return updated
        }
        list.append(pattern)
        perms[kind.rawValue] = list.sorted()
        json["permissions"] = perms

        if let err = writeJSON(json, to: info.settingsPath) {
            updated.writeError = err
            return updated
        }
        updated.permissions = HarnessScanner.scanPermissions(settingsPath: info.settingsPath)
        updated.settingsMtime = HarnessScanner.mtime(of: info.settingsPath) ?? info.settingsMtime
        updated.writeError = nil
        return updated
    }

    static func removePermission(_ entry: PermissionEntry, in info: HarnessInfo) -> HarnessInfo {
        var updated = info
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: info.settingsPath)),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            updated.writeError = "settings.json 읽기 실패"
            return updated
        }
        if let current = HarnessScanner.mtime(of: info.settingsPath),
           abs(current.timeIntervalSince(info.settingsMtime)) > 1 {
            updated.writeError = "외부에서 변경됨 — 재스캔 후 다시 시도"
            return updated
        }

        guard var perms = json["permissions"] as? [String: Any] else { return updated }
        var list = perms[entry.kind.rawValue] as? [String] ?? []
        list.removeAll { $0 == entry.pattern }
        perms[entry.kind.rawValue] = list
        json["permissions"] = perms

        if let err = writeJSON(json, to: info.settingsPath) {
            updated.writeError = err
            return updated
        }
        updated.permissions = HarnessScanner.scanPermissions(settingsPath: info.settingsPath)
        updated.settingsMtime = HarnessScanner.mtime(of: info.settingsPath) ?? info.settingsMtime
        updated.writeError = nil
        return updated
    }

    // MARK: - Hook delete (disabled hooks only — extract-only, no re-insert)

    static func deleteHook(hook: HookEntry, in info: HarnessInfo) -> HarnessInfo {
        guard !hook.enabled else {
            var updated = info
            updated.writeError = "활성 hook은 삭제할 수 없습니다 (먼저 비활성화)"
            return updated
        }
        var updated = info
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: info.settingsPath)),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            updated.writeError = "settings.json 읽기 실패"
            return updated
        }
        if let current = HarnessScanner.mtime(of: info.settingsPath),
           abs(current.timeIntervalSince(info.settingsMtime)) > 1 {
            updated.writeError = "외부에서 변경됨 — 재스캔 후 다시 시도"
            return updated
        }

        guard extractGroup(id: hook.id, from: &json, key: "_disabledHooks", event: hook.event) != nil else {
            updated.writeError = "hook을 찾지 못했습니다 (id: \(hook.id))"
            return updated
        }

        if let err = writeJSON(json, to: info.settingsPath) {
            updated.writeError = err
            return updated
        }

        updated.hooks.removeAll { $0.id == hook.id }
        updated.settingsMtime = HarnessScanner.mtime(of: info.settingsPath) ?? info.settingsMtime
        updated.writeError = nil
        return updated
    }

    // MARK: - JSON helpers

    private static func extractGroup(
        id: String,
        from json: inout [String: Any],
        key: String,
        event: String
    ) -> [String: Any]? {
        guard var section = json[key] as? [String: Any],
              var groups  = section[event] as? [[String: Any]]
        else { return nil }

        for (i, group) in groups.enumerated() {
            let matcher = group["matcher"] as? String ?? ""
            let hooks   = group["hooks"] as? [[String: Any]] ?? []
            let cmd     = hooks.first?["command"] as? String ?? ""
            if hookHash(event: event, matcher: matcher, command: cmd) == id {
                groups.remove(at: i)
                if groups.isEmpty {
                    section.removeValue(forKey: event)
                } else {
                    section[event] = groups
                }
                json[key] = section.isEmpty ? nil : section
                return group
            }
        }
        return nil
    }

    private static func insertGroup(_ group: [String: Any], into json: inout [String: Any], key: String, event: String) {
        var section = json[key] as? [String: Any] ?? [:]
        var groups  = section[event] as? [[String: Any]] ?? []
        groups.append(group)
        section[event] = groups
        json[key] = section
    }

    private static func writeJSON(_ json: [String: Any], to path: String) -> String? {
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            let tmp  = path + ".airuncat.tmp"
            try data.write(to: URL(fileURLWithPath: tmp), options: .atomic)
            try FileManager.default.moveItem(atPath: tmp, toPath: path)   // atomic rename
            return nil
        } catch {
            return "저장 실패: \(error.localizedDescription)"
        }
    }

    private static func hookHash(event: String, matcher: String, command: String) -> String {
        HarnessScanner.hookHash(event: event, matcher: matcher, command: command)
    }
}
