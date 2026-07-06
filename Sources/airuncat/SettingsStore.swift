import Foundation

// MARK: - Model

/// airuncat 사용자 설정. Claude Code 사용량 창 한도(D3)와 주간 리셋 시점(D7).
/// 단위 = 가중 토큰(D4b, UsageStore 소비 메트릭과 동일 단위).
struct AppSettings: Codable, Equatable {
    var fiveHourLimit: Int?     // 5시간 창 한도(가중 토큰). nil = 미설정 → 배너 유도(R4.2)
    var weeklyLimit: Int?       // 주간 창 한도(가중 토큰). nil = 미설정
    var weeklyResetWeekday: Int // 0=Mon .. 6=Sun (앱 전역 요일 컨벤션)
    var weeklyResetHour: Int    // 0..23, 로컬 시각

    static let `default` = AppSettings(
        fiveHourLimit: nil,
        weeklyLimit: nil,
        weeklyResetWeekday: 0,   // 월요일
        weeklyResetHour: 0
    )

    var hasLimits: Bool { fiveHourLimit != nil && weeklyLimit != nil }
}

/// 플랜 티어 프리셋(D10). 정확한 토큰 예산은 공개되지 않으므로 **근사 시작점**이며,
/// 사용자가 실제 벽에 부딪힌 시점을 보고 보정한다(C3).
struct TierPreset: Identifiable {
    let id: String        // 표시 이름
    let fiveHour: Int
    let weekly: Int

    // 단위 = 소비 메트릭(input+output+cache_creation, cache_read 제외) 토큰.
    // 실측 스케일(집중 사용 시 5h≈5M, 주≈12M)에 맞춘 근사 시작점 — 사용자가 보정.
    static let all: [TierPreset] = [
        TierPreset(id: "Pro",     fiveHour:  2_000_000, weekly:   8_000_000),
        TierPreset(id: "Max 5x",  fiveHour:  6_000_000, weekly:  30_000_000),
        TierPreset(id: "Max 20x", fiveHour: 20_000_000, weekly: 120_000_000),
    ]
}

// MARK: - Store

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private static var path: String { PathConstants.settings }

    init() {
        self.settings = Self.load()
    }

    // MARK: Mutation

    func setLimits(fiveHour: Int?, weekly: Int?) {
        settings.fiveHourLimit = fiveHour
        settings.weeklyLimit = weekly
        save()
    }

    func setWeeklyReset(weekday: Int, hour: Int) {
        settings.weeklyResetWeekday = min(6, max(0, weekday))
        settings.weeklyResetHour = min(23, max(0, hour))
        save()
    }

    func applyPreset(_ preset: TierPreset) {
        settings.fiveHourLimit = preset.fiveHour
        settings.weeklyLimit = preset.weekly
        save()
    }

    // MARK: IO

    private static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        let url = URL(fileURLWithPath: Self.path)
        let dir = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: url, options: .atomic)
    }
}
