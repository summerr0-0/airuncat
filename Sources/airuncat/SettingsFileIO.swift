import Foundation

/// `~/.claude/settings.json` 공용 read/write. HookRecipeManager·StatuslineManager가 각자
/// 복제하던 것을 한곳으로(드리프트 방지 — 과거 HarnessManager의 moveItem 버그가 그 증상).
/// 원자 쓰기(Data.write(.atomic))로 통일. 파싱 실패 시 nil(존재하나 파손인 경우 포함).
enum SettingsFileIO {

    static func read() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: PathConstants.claudeSettings)) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 존재하는데 파싱 불가(파손) — install 계열이 빈 {}로 덮는 사고 방지용 가드.
    static func isCorrupt() -> Bool {
        FileManager.default.fileExists(atPath: PathConstants.claudeSettings) && read() == nil
    }

    /// 원자 쓰기. 실패 시 오류 문자열, 성공 시 nil.
    static func write(_ root: [String: Any]) -> String? {
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
