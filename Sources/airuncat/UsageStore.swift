import Foundation

/// Claude Code 사용량 창(5시간 롤링 + 주간) 소비량을 계산·게시한다(R3, R6).
/// 소비량은 설정과 무관하게 집계하고, 남은 %는 한도가 있을 때만 산출한다.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var fiveHourConsumed = 0
    @Published private(set) var weeklyConsumed = 0

    private var refreshing = false   // 재진입 가드 — 겹친 스캔의 캐시 lost-update 방지(M1)

    /// 창 소비량 재계산. tick마다 호출(UsageScanner가 mtime 증분 캐시로 비용 절감).
    func refresh(resetWeekday: Int, resetHour: Int) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let now = Date()
        let nowEpoch = now.timeIntervalSince1970
        let events = await Task.detached(priority: .utility) {
            UsageScanner.scan(now: nowEpoch)
        }.value

        let fiveHourStart = nowEpoch - 5 * 3600
        let weekStart = Self.lastWeeklyReset(now: now, weekday: resetWeekday, hour: resetHour)

        var five = 0, week = 0
        for e in events {
            if e.ts >= fiveHourStart { five += e.weighted }
            if e.ts >= weekStart { week += e.weighted }
        }
        fiveHourConsumed = five
        weeklyConsumed = week
    }

    // MARK: - Remaining % (R6)

    /// remaining% = max(0, (1 − 소비/한도)×100). 한도 nil/0이면 nil(0 나눗셈 방어, R6.2).
    static func remainingPercent(consumed: Int, limit: Int?) -> Double? {
        guard let l = limit, l > 0 else { return nil }
        return max(0, (1 - Double(consumed) / Double(l)) * 100)
    }

    /// 소비가 한도를 넘었는지(R6.1 "초과" 표기용).
    static func isOverLimit(consumed: Int, limit: Int?) -> Bool {
        guard let l = limit, l > 0 else { return false }
        return consumed > l
    }

    // MARK: - Weekly reset anchor (D7)

    /// now 이전의 가장 최근 리셋 시점. weekday: 0=Mon..6=Sun(앱 컨벤션), hour: 0..23.
    static func lastWeeklyReset(now: Date, weekday: Int, hour: Int) -> TimeInterval {
        let cal = Calendar.current
        // 앱 0=Mon..6=Sun → Calendar 1=Sun..7=Sat
        let targetCal = ((weekday + 1) % 7) + 1

        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = min(23, max(0, hour)); comps.minute = 0; comps.second = 0
        guard var candidate = cal.date(from: comps) else {
            return now.timeIntervalSince1970 - 7 * 24 * 3600
        }
        for _ in 0..<8 {
            if cal.component(.weekday, from: candidate) == targetCal && candidate <= now {
                return candidate.timeIntervalSince1970
            }
            candidate = cal.date(byAdding: .day, value: -1, to: candidate) ?? candidate
        }
        return now.timeIntervalSince1970 - 7 * 24 * 3600
    }
}
