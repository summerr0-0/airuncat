import Foundation

/// Claude Code statusline 통합 (백로그 R3, specs/omc-gap-analysis).
///
/// Claude Code는 statusline 커맨드에 렌더마다 JSON(stdin)을 파이프한다 — 네이티브 컨텍스트 %,
/// 모델명 등. airuncat 스크립트를 설치하면 그 JSON이 세션별로
/// `~/.airuncat/hook-state/statusline/<session_id>.json`에 캐시되어 다른 뷰가 재사용한다(R4).
///
/// C5: 사용자가 이미 statusLine을 설정했으면 절대 덮지 않는다(감지·안내만).
enum StatuslineManager {

    static var scriptPath: String {
        (PathConstants.airuncatBase as NSString).appendingPathComponent("statusline.sh")
    }
    static var cacheDir: String {
        (PathConstants.hookState as NSString).appendingPathComponent("statusline")
    }

    enum Status {
        case installed          // airuncat statusline 설치됨
        case foreign(String)    // 다른 statusline이 설정돼 있음(command) — 덮지 않음(C5)
        case notInstalled
    }

    static func status() -> Status {
        guard let root = readSettings(),
              let sl = root["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return .notInstalled }
        return cmd.contains("/.airuncat/statusline.sh") ? .installed : .foreign(cmd)
    }

    /// 설치: 스크립트 기록 + settings.json statusLine 등록. 기존(외부) 설정이 있으면 거부(C5).
    @discardableResult
    static func install() -> String? {
        if HookRecipeManager.settingsCorrupt() {
            return "settings.json 파싱 불가 — 수동 확인 필요(덮어쓰지 않음)"
        }
        if case .foreign(let cmd) = status() {
            return "기존 statusline이 있어 덮지 않습니다: \(cmd)"
        }
        do {
            try FileManager.default.createDirectory(atPath: PathConstants.airuncatBase,
                                                    withIntermediateDirectories: true)
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            return "스크립트 설치 실패: \(error.localizedDescription)"
        }
        var root = readSettings() ?? [:]
        root["statusLine"] = ["type": "command", "command": scriptPath]
        return writeSettings(root)
    }

    /// 제거: airuncat statusline일 때만 settings에서 키 제거 + 스크립트 삭제.
    @discardableResult
    static func remove() -> String? {
        if case .installed = status() {
            var root = readSettings() ?? [:]
            root.removeValue(forKey: "statusLine")
            if let err = writeSettings(root) { return err }
        }
        try? FileManager.default.removeItem(atPath: scriptPath)
        return nil
    }

    // MARK: - Script

    /// stdin JSON → 세션별 캐시(원자 쓰기, ±3% 지터 안정화=R9b) + 간단한 상태줄 출력.
    /// internal — Global 탭의 스크립트 미리보기(15.1)에서 사용.
    static let script = """
    #!/bin/sh
    # airuncat statusline: stdin JSON 캐시 + "모델 · ctx N%" 출력
    INPUT=$(cat)
    HOOK_INPUT="$INPUT" /usr/bin/python3 - <<'PY'
    import json, os, sys
    try:
        d = json.loads(os.environ.get("HOOK_INPUT") or "")
    except Exception:
        print("airuncat"); sys.exit(0)

    sid = d.get("session_id") or "unknown"
    cache_dir = os.path.expanduser("~/.airuncat/hook-state/statusline")
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, sid + ".json")

    # 네이티브 값 추출 (필드는 버전에 따라 다를 수 있어 방어적으로)
    cw = d.get("context_window") or {}
    pct = cw.get("used_percentage")
    model = ((d.get("model") or {}).get("display_name")) or ""

    # R9b 지터 안정화: 직전 캐시와 ±3% 이내면 직전 %를 유지(표시 흔들림 제거)
    try:
        prev = json.load(open(cache_path))
        prev_pct = (prev.get("context_window") or {}).get("used_percentage")
        if isinstance(pct, (int, float)) and isinstance(prev_pct, (int, float)) and abs(pct - prev_pct) <= 3:
            d["context_window"]["used_percentage"] = prev_pct
            pct = prev_pct
    except Exception:
        pass

    tmp = cache_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, cache_path)

    parts = [p for p in [model, ("ctx %d%%" % round(pct)) if isinstance(pct, (int, float)) else None] if p]
    print(" · ".join(parts) if parts else "airuncat")
    PY
    """

    // MARK: - 캐시 조회 (R4 — 네이티브 컨텍스트 %)

    struct NativeContext {
        let usedPercentage: Int
        let windowSize: Int      // 예: 200_000, 1_000_000 — 모델별 상이(고정 200k 가정 해소)
    }

    /// 세션의 statusline 캐시에서 네이티브 컨텍스트 %를 읽는다. 없으면 nil(합산 폴백).
    /// idle 세션이어도 컨텍스트는 변하지 않으므로 신선도 컷오프는 두지 않는다.
    static func nativeContext(sessionId: String) -> NativeContext? {
        let path = (cacheDir as NSString).appendingPathComponent("\(sessionId).json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cw = obj["context_window"] as? [String: Any],
              let pct = (cw["used_percentage"] as? NSNumber)?.intValue else { return nil }
        let size = (cw["context_window_size"] as? NSNumber)?.intValue ?? 200_000
        return NativeContext(usedPercentage: min(100, max(0, pct)), windowSize: size)
    }

    // MARK: - settings.json IO (HookRecipeManager와 동일 패턴)

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
