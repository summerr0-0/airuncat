import Foundation

/// 글로벌 레시피가 쌓는 `~/.airuncat/hook-state/` 읽기 전용 리더 (Phase 15.2).
/// 없으면 nil — 레시피 미설치/데이터 없음은 침묵이 원칙.
enum HookStateReader {

    struct SessionMetrics {
        let durationSeconds: Int?
        let toolUses: Int?
    }

    private static func sessionDir(_ sessionId: String) -> String {
        ((PathConstants.hookState as NSString).appendingPathComponent("sessions") as NSString)
            .appendingPathComponent(sessionId)
    }

    /// session-telemetry가 남긴 metrics.json. 캡션에 쓰는 필드만 파싱.
    /// user_messages는 tool_result 운반 메시지가 섞여 부풀므로 표시에 쓰지 않는다(리뷰어 6a).
    static func metrics(sessionId: String) -> SessionMetrics? {
        let path = (sessionDir(sessionId) as NSString).appendingPathComponent("metrics.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let dur = (obj["duration_seconds"] as? NSNumber)?.intValue
        let tools = (obj["tool_uses"] as? NSNumber)?.intValue
        guard dur != nil || tools != nil else { return nil }
        return SessionMetrics(durationSeconds: (dur ?? 0) > 0 ? dur : nil, toolUses: tools)
    }

    /// subagent-tracker가 누적한 subagents.jsonl의 이벤트 수. 0/부재면 nil.
    static func subagentCount(sessionId: String) -> Int? {
        let path = (sessionDir(sessionId) as NSString).appendingPathComponent("subagents.jsonl")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else { return nil }
        let count = data.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        return count > 0 ? count : nil
    }
}
