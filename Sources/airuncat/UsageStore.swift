import Foundation

/// Claude Code 사용량(5시간 세션 창 + 주간 창)을 Anthropic 공식 API에서 받아 게시한다.
/// utilization/resets_at은 서버 실제 값 — 토큰 합산 근사가 아니다.
/// R2: 오류별 TTL 차등 + 429 지수 백오프 + stale 서빙(15min)로 일시 오류에 견고.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot? = nil
    @Published private(set) var error: UsageFetchError? = nil
    /// 지금 보이는 snapshot이 직전 성공값의 재사용(오류 중)인지 — 헤더에 * 배지.
    @Published private(set) var isStale = false

    private var refreshing = false
    private var lastSuccessAt: Date? = nil
    private var nextAllowedFetch: Date? = nil
    private var rateLimitedCount = 0   // 연속 429 횟수(지수 백오프)
    private var alertedWindows: Set<String> = []   // R8: 임계 초과 알림을 보낸 창("5h"/"wk")

    // R8 임계: 상향 90%에서 경고, 하향 80% 밑으로 내려오면 "리셋/여유 회복" 알림(히스테리시스).
    private let alertHighPct = 90.0
    private let alertLowPct = 80.0

    // R2 상수 (OMC usage-api.ts 준거)
    private let successTTL: TimeInterval = 60
    private let networkErrorTTL: TimeInterval = 120
    private let otherErrorTTL: TimeInterval = 15
    private let maxBackoff: TimeInterval = 300      // 429 백오프 상한 5min
    private let maxStaleAge: TimeInterval = 15 * 60 // stale 서빙 한도

    /// tick마다 호출되지만 TTL/백오프 안에서는 스킵. 실패해도 15min까지 직전 값을 stale로 유지.
    func refresh() async {
        guard !refreshing else { return }
        if let next = nextAllowedFetch, Date() < next { return }
        refreshing = true
        defer { refreshing = false }

        let now = Date()
        switch await UsageAPIClient.fetch() {
        case .success(let snap):
            snapshot = snap
            error = nil
            isStale = false
            lastSuccessAt = now
            rateLimitedCount = 0
            nextAllowedFetch = now.addingTimeInterval(successTTL)
            checkUsageAlerts(snap)

        case .failure(let e):
            error = e
            // 오류별 재시도 간격(R2): 429는 지수 백오프, 네트워크는 2min, 그 외 15s.
            if case .http(429) = e {
                rateLimitedCount += 1
                let backoff = min(successTTL * pow(2, Double(rateLimitedCount - 1)), maxBackoff)
                nextAllowedFetch = now.addingTimeInterval(backoff)
            } else if case .network = e {
                nextAllowedFetch = now.addingTimeInterval(networkErrorTTL)
            } else {
                nextAllowedFetch = now.addingTimeInterval(otherErrorTTL)
            }
            // stale 서빙: 직전 성공이 15min 이내면 그 값을 * 배지로 유지, 지나면 폐기.
            if let s = lastSuccessAt, now.timeIntervalSince(s) < maxStaleAge {
                isStale = true
            } else {
                snapshot = nil
                isStale = false
            }
        }
    }

    // MARK: - 임계/리셋 알림 (R8, D6)

    /// 상향 90% 교차 시 경고 1회, 이후 하향 80% 교차 시(리셋 등) "여유 회복" 1회.
    /// 임계 교차 기반이라 resets_at 시각을 따로 추적하지 않아도 리셋을 감지한다.
    private func checkUsageAlerts(_ snap: UsageSnapshot) {
        checkWindow(key: "5h", label: "5시간 창", percent: snap.fiveHourPercent,
                    resetsAt: snap.fiveHourResetsAt)
        if let wk = snap.weeklyPercent {
            checkWindow(key: "wk", label: "주간 창", percent: wk, resetsAt: snap.weeklyResetsAt)
        }
    }

    private func checkWindow(key: String, label: String, percent: Double, resetsAt: Date?) {
        if percent >= alertHighPct, !alertedWindows.contains(key) {
            alertedWindows.insert(key)
            var body = "사용량 \(Int(percent.rounded()))% — 한도 임박"
            if let r = resetsAt, r > Date() {
                let mins = Int(r.timeIntervalSinceNow / 60)
                body += " (리셋까지 \(mins >= 60 ? "\(mins / 60)시간 \(mins % 60)분" : "\(mins)분"))"
            }
            NotificationManager.shared.sendUsageAlert(id: key, title: "Claude \(label)", body: body)
        } else if percent < alertLowPct, alertedWindows.contains(key) {
            alertedWindows.remove(key)
            NotificationManager.shared.sendUsageAlert(
                id: key, title: "Claude \(label)",
                body: "여유 회복 — 현재 \(Int(percent.rounded()))%")
        }
    }
}
