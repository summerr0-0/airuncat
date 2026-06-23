import Foundation

extension Date {
    /// Compact elapsed time: "20s", "5m", "2h", "3d"
    var compactAge: String {
        let s = Int(Date().timeIntervalSince(self))
        if s < 60    { return "\(max(s, 0))s" }
        if s < 3600  { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    /// Calendar-relative label in Korean: "오늘", "어제", "5일 전", "2개월 전"
    var relativeLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(self)     { return "오늘" }
        if cal.isDateInYesterday(self) { return "어제" }
        let days = cal.dateComponents([.day], from: self, to: Date()).day ?? 0
        if days < 30 { return "\(days)일 전" }
        return "\(days / 30)개월 전"
    }
}
