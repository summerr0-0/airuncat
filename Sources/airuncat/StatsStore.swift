import Foundation

@MainActor
final class StatsStore: ObservableObject {

    enum Period: String, CaseIterable {
        case week  = "이번 주"
        case month = "이번 달"
        case all   = "전체"
    }

    @Published var data: StatsData = .empty
    @Published var isLoading: Bool = false
    @Published var period: Period = .week

    // MARK: - Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        data = await Task.detached(priority: .background) {
            StatsScanner.scan()
        }.value
        isLoading = false
    }

    // MARK: - Filtered

    func filtered() -> [SessionStat] {
        let cutoff = cutoffDate()
        guard let cutoff else { return data.sessions }
        return data.sessions.filter { $0.date >= cutoff }
    }

    // MARK: - Derived metrics

    /// 7×24 matrix: row=dayOfWeek(0=Mon), col=hourOfDay
    func heatmap() -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for s in filtered() {
            let row = max(0, min(6, s.dayOfWeek))
            let col = max(0, min(23, s.hourOfDay))
            grid[row][col] += 1
        }
        return grid
    }

    func topSkills(n: Int) -> [(name: String, count: Int)] {
        var freq: [String: Int] = [:]
        for s in filtered() {
            for skill in s.skillsUsed { freq[skill, default: 0] += 1 }
        }
        return freq.sorted { $0.value > $1.value }.prefix(n).map { (name: $0.key, count: $0.value) }
    }

    func sessionCount() -> Int { filtered().count }

    func totalMinutes() -> Int { filtered().reduce(0) { $0 + $1.durationMinutes } }

    // MARK: - Private

    private func cutoffDate() -> String? {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .week:
            guard let monday = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
            return dateString(monday)
        case .month:
            guard let first = cal.dateInterval(of: .month, for: now)?.start else { return nil }
            return dateString(first)
        case .all:
            return nil
        }
    }

    private func dateString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
