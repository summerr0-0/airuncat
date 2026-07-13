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

    /// R6a 세션 텔레메트리 / R6b 서브에이전트 트래커 / R6c rules 주입.
    static let recipes: [HookRecipe] = [sessionTelemetry, subagentTracker, rulesInjector]

    // MARK: R6a — 세션 텔레메트리 (SessionEnd)

    static let sessionTelemetry = HookRecipe(
        id: "session-telemetry",
        name: "세션 텔레메트리",
        description: "세션 종료 시 지속시간·메시지/도구 수·transcript 크기를 hook-state에 기록",
        event: "SessionEnd",
        matcher: nil,
        timeout: 5,
        script: """
        #!/bin/sh
        # airuncat hook recipe: session-telemetry (SessionEnd)
        # stdin: {session_id, transcript_path, cwd, hook_event_name, reason}
        INPUT=$(cat)
        HOOK_INPUT="$INPUT" /usr/bin/python3 - <<'PY'
        import json, sys, os, time
        try:
            d = json.loads(os.environ.get("HOOK_INPUT") or "")
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
            # 지속시간·카운트: 라인 단위 1패스(수 MB에 수백 ms 수준, timeout 5s 내)
            first_ts = last_ts = None
            users = assistants = tools = 0
            with open(tp, "r", errors="ignore") as f:
                for line in f:
                    if '"timestamp"' in line:
                        i = line.find('"timestamp"')
                        q1 = line.find('"', i + 12); q2 = line.find('"', q1 + 1)
                        if q1 > 0 and q2 > q1:
                            ts = line[q1 + 1:q2]
                            if first_ts is None: first_ts = ts
                            last_ts = ts
                    if '"type":"user"' in line: users += 1
                    elif '"type":"assistant"' in line: assistants += 1
                    tools += line.count('"type":"tool_use"')
            if first_ts and last_ts:
                from datetime import datetime
                def p(t):
                    return datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
                try:
                    metrics["duration_seconds"] = max(0, int(p(last_ts) - p(first_ts)))
                except Exception:
                    pass
            metrics.update(user_messages=users, assistant_messages=assistants, tool_uses=tools)
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

    // MARK: R6b — 서브에이전트 트래커 (SubagentStop)

    static let subagentTracker = HookRecipe(
        id: "subagent-tracker",
        name: "서브에이전트 트래커",
        description: "서브에이전트 종료 시 이벤트를 세션별 subagents.jsonl에 누적 기록",
        event: "SubagentStop",
        matcher: nil,
        timeout: 5,
        script: """
        #!/bin/sh
        # airuncat hook recipe: subagent-tracker (SubagentStop)
        # 스키마 드리프트에 대비해 stdin JSON을 통째로(+수신 시각) append 저장한다.
        INPUT=$(cat)
        HOOK_INPUT="$INPUT" /usr/bin/python3 - <<'PY'
        import json, sys, os, time
        try:
            d = json.loads(os.environ.get("HOOK_INPUT") or "")
        except Exception:
            sys.exit(0)
        sid = d.get("session_id") or "unknown"
        out_dir = os.path.expanduser("~/.airuncat/hook-state/sessions/" + sid)
        os.makedirs(out_dir, exist_ok=True)
        d["_recorded_at"] = time.time()
        with open(os.path.join(out_dir, "subagents.jsonl"), "a") as f:
            f.write(json.dumps(d) + "\\n")
        PY
        exit 0
        """
    )

    // MARK: R6c — rules 주입 (PreToolUse Edit|Write)

    static let rulesInjector = HookRecipe(
        id: "rules-injector",
        name: "Rules 주입기",
        description: "편집 파일 경로에 매칭되는 .claude/rules를 컨텍스트로 주입 (세션당 1회, 해시 중복 방지)",
        event: "PreToolUse",
        matcher: "Edit|Write",
        timeout: 5,
        script: """
        #!/bin/sh
        # airuncat hook recipe: rules-injector (PreToolUse, Edit|Write)
        # 룰 소스: <프로젝트>/.claude/rules/*.md + ~/.claude/rules/*.md
        # frontmatter `paths:` 글롭이 편집 파일에 맞거나 글롭이 없으면(전역) 주입.
        # 세션별 콘텐츠 해시 캐시로 같은 룰 재주입 방지.
        INPUT=$(cat)
        HOOK_INPUT="$INPUT" /usr/bin/python3 - <<'PY'
        import json, sys, os, glob, hashlib, fnmatch
        try:
            d = json.loads(os.environ.get("HOOK_INPUT") or "")
        except Exception:
            print(json.dumps({"continue": True})); sys.exit(0)
        tool_input = d.get("tool_input") or {}
        file_path = tool_input.get("file_path") or ""
        sid = d.get("session_id") or "unknown"
        cwd = d.get("cwd") or ""
        if not file_path:
            print(json.dumps({"continue": True})); sys.exit(0)

        cache_dir = os.path.expanduser("~/.airuncat/hook-state/sessions/" + sid)
        os.makedirs(cache_dir, exist_ok=True)
        cache_path = os.path.join(cache_dir, "injected-rules.json")
        try:
            injected = set(json.load(open(cache_path)))
        except Exception:
            injected = set()

        def rule_files():
            out = []
            if cwd:
                out += sorted(glob.glob(os.path.join(cwd, ".claude/rules/*.md")))
            out += sorted(glob.glob(os.path.expanduser("~/.claude/rules/*.md")))
            return out

        def parse(path):
            try:
                text = open(path, errors="ignore").read()
            except Exception:
                return None, None
            globs = []
            body = text
            if text.startswith("---"):
                end = text.find("---", 3)
                if end > 0:
                    fm, body = text[3:end], text[end + 3:]
                    for line in fm.splitlines():
                        s = line.strip()
                        if s.startswith("paths:"):
                            v = s[6:].strip().strip("[]")
                            globs += [g.strip().strip("'\\"") for g in v.split(",") if g.strip()]
                        elif s.startswith("- ") and globs is not None:
                            globs.append(s[2:].strip().strip("'\\""))
            return globs, body.strip()

        msgs = []
        for rf in rule_files():
            globs, body = parse(rf)
            if body is None or not body:
                continue
            if globs and not any(fnmatch.fnmatch(file_path, g) or fnmatch.fnmatch(os.path.basename(file_path), g) for g in globs):
                continue
            h = hashlib.sha256(body.encode()).hexdigest()[:16]
            if h in injected:
                continue
            injected.add(h)
            msgs.append("[rule: %s]\\n%s" % (os.path.basename(rf), body))

        if msgs:
            try:
                json.dump(sorted(injected), open(cache_path, "w"))
            except Exception:
                pass
            print(json.dumps({"continue": True, "systemMessage": "\\n\\n".join(msgs)[:8000]}))
        else:
            print(json.dumps({"continue": True}))
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

    /// settings.json이 존재하는데 JSON 파싱이 안 되는 상태 — 이때 install하면 빈 {} 기반으로
    /// 덮어써 파손 파일을 클로버하므로 거부한다(15.1 가드).
    static func settingsCorrupt() -> Bool { SettingsFileIO.isCorrupt() }

    /// 설치: 스크립트 파일 기록(0755) + settings.json에 항목 추가. 이미 있으면 no-op.
    @discardableResult
    static func install(_ recipe: HookRecipe) -> String? {
        if settingsCorrupt() { return "settings.json 파싱 불가 — 수동 확인 필요(덮어쓰지 않음)" }
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

    private static func readSettings() -> [String: Any]? { SettingsFileIO.read() }
    private static func writeSettings(_ root: [String: Any]) -> String? { SettingsFileIO.write(root) }
}
