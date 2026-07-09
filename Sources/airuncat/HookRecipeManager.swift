import Foundation

// MARK: - Model

/// airuncat이 설치해주는 Claude Code 훅 레시피 (백로그 R5, specs/omc-gap-analysis).
/// settings.json 실제 형식: hooks.<Event> = [{matcher: "정규식"?, hooks: [{type:"command", command, timeout?}]}]
struct HookRecipe: Identifiable {
    let id: String            // kebab-case, 스크립트 파일명에도 사용
    let name: String          // 표시명
    let description: String
    let event: String         // "SessionEnd" | "PreToolUse" | ...
    let matcher: String?      // 도구 정규식. nil이면 matcher 키 생략(세션 이벤트 등)
    let timeout: Int?         // 초
    let script: String        // 스크립트 본문 (~/.claude/hooks/airuncat-<id>.sh 로 설치)

    var scriptFileName: String { "airuncat-\(id).sh" }
    var scriptPath: String { (PathConstants.claudeHooks as NSString).appendingPathComponent(scriptFileName) }
}

// MARK: - Manager

/// 레시피 설치/제거/상태. settings.json은 원자 병합 — airuncat 항목(command에 스크립트 경로 포함)만
/// 추가/제거하고 나머지 훅·키는 건드리지 않는다. 상태 출력은 ~/.airuncat/hook-state/ (D3).
enum HookRecipeManager {

    // MARK: Registry

    /// 파일럿: 세션 텔레메트리(R6a 최소형). R6b/c는 T5에서 추가.
    static let recipes: [HookRecipe] = [sessionTelemetry]

    static let sessionTelemetry = HookRecipe(
        id: "session-telemetry",
        name: "세션 텔레메트리",
        description: "세션 종료 시 세션 ID·cwd·transcript 크기·종료 시각을 hook-state에 기록",
        event: "SessionEnd",
        matcher: nil,
        timeout: 5,
        script: """
        #!/bin/sh
        # airuncat hook recipe: session-telemetry (SessionEnd)
        # stdin: {session_id, transcript_path, cwd, hook_event_name, reason}
        /usr/bin/python3 - <<'PY'
        import json, sys, os, time
        try:
            d = json.load(sys.stdin)
        except Exception:
            sys.exit(0)
        sid = d.get("session_id") or "unknown"
        out_dir = os.path.expanduser("~/.airuncat/hook-state/sessions/" + sid)
        os.makedirs(out_dir, exist_ok=True)
        metrics = {
            "session_id": sid,
            "cwd": d.get("cwd", ""),
            "reason": d.get("reason", ""),
            "ended_at": time.time(),
        }
        tp = os.path.expanduser(d.get("transcript_path", "") or "")
        try:
            metrics["transcript_bytes"] = os.stat(tp).st_size
        except Exception:
            pass
        tmp = os.path.join(out_dir, ".metrics.tmp")
        with open(tmp, "w") as f:
            json.dump(metrics, f)
        os.replace(tmp, os.path.join(out_dir, "metrics.json"))
        PY
        exit 0
        """
    )

    // MARK: Status

    static func isInstalled(_ recipe: HookRecipe) -> Bool {
        guard let root = readSettings() else { return false }
        return containsEntry(root, recipe: recipe)
    }

    // MARK: Install / Uninstall

    /// 설치: 스크립트 파일 기록(0755) + settings.json에 항목 추가. 이미 있으면 no-op.
    @discardableResult
    static func install(_ recipe: HookRecipe) -> String? {
        let fm = FileManager.default
        // 1. 스크립트 파일
        do {
            try fm.createDirectory(atPath: PathConstants.claudeHooks, withIntermediateDirectories: true)
            try recipe.script.write(toFile: recipe.scriptPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recipe.scriptPath)
        } catch {
            return "스크립트 설치 실패: \(error.localizedDescription)"
        }
        // 2. settings.json 병합
        var root = readSettings() ?? [:]
        guard !containsEntry(root, recipe: recipe) else { return nil }   // 이미 설치됨
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        var eventArr = (hooks[recipe.event] as? [[String: Any]]) ?? []

        var command: [String: Any] = ["type": "command", "command": recipe.scriptPath]
        if let t = recipe.timeout { command["timeout"] = t }
        var entry: [String: Any] = ["hooks": [command]]
        if let m = recipe.matcher { entry["matcher"] = m }

        eventArr.append(entry)
        hooks[recipe.event] = eventArr
        root["hooks"] = hooks
        return writeSettings(root)
    }

    /// 제거: settings.json에서 이 레시피 스크립트를 가리키는 항목만 제거 + 스크립트 삭제.
    /// 빈 배열/빈 hooks 키는 정리해 설치 전 원형으로 복원(R5.1).
    @discardableResult
    static func uninstall(_ recipe: HookRecipe) -> String? {
        if var root = readSettings(), var hooks = root["hooks"] as? [String: Any] {
            if var eventArr = hooks[recipe.event] as? [[String: Any]] {
                eventArr = eventArr.compactMap { entry in
                    var cmds = (entry["hooks"] as? [[String: Any]]) ?? []
                    cmds.removeAll { ($0["command"] as? String)?.contains(recipe.scriptFileName) == true }
                    if cmds.isEmpty { return nil }        // 이 항목이 통째로 airuncat 것이었음
                    var e = entry; e["hooks"] = cmds; return e
                }
                if eventArr.isEmpty { hooks.removeValue(forKey: recipe.event) }
                else { hooks[recipe.event] = eventArr }
            }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
            if let err = writeSettings(root) { return err }
        }
        try? FileManager.default.removeItem(atPath: recipe.scriptPath)
        return nil
    }

    // MARK: - settings.json IO (원자, 타 키 보존)

    private static func containsEntry(_ root: [String: Any], recipe: HookRecipe) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let eventArr = hooks[recipe.event] as? [[String: Any]] else { return false }
        for entry in eventArr {
            for cmd in (entry["hooks"] as? [[String: Any]]) ?? [] {
                if (cmd["command"] as? String)?.contains(recipe.scriptFileName) == true { return true }
            }
        }
        return false
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: PathConstants.claudeSettings)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeSettings(_ root: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            return "settings.json 직렬화 실패"
        }
        do {
            try data.write(to: URL(fileURLWithPath: PathConstants.claudeSettings), options: .atomic)
            return nil
        } catch {
            return "settings.json 쓰기 실패: \(error.localizedDescription)"
        }
    }
}
