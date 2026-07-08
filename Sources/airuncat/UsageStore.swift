import Foundation

/// Claude Code 사용량(5시간 세션 창 + 주간 창)을 Anthropic 공식 API에서 받아 게시한다.
/// utilization/resets_at은 서버 실제 값 — 토큰 합산 근사가 아니다.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot? = nil
    @Published private(set) var error: UsageFetchError? = nil

    private var lastFetch: Date? = nil
    private var refreshing = false
    private let ttl: TimeInterval = 60   // API 과호출 방지

    /// tick마다 호출되지만 TTL 안에서는 스킵. 실패해도 마지막 성공 스냅샷은 유지.
    func refresh() async {
        guard !refreshing else { return }
        if let last = lastFetch, Date().timeIntervalSince(last) < ttl, snapshot != nil { return }
        refreshing = true
        defer { refreshing = false }

        switch await UsageAPIClient.fetch() {
        case .success(let snap):
            snapshot = snap
            error = nil
            lastFetch = Date()
        case .failure(let e):
            error = e
            // 스냅샷은 유지(오프라인 순간에도 마지막 값 표시). 실패는 재시도 위해 lastFetch 갱신 안 함.
        }
    }
}
