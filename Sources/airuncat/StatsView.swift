import SwiftUI

struct StatsView: View {
    @ObservedObject var statsStore: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            periodPicker
            Divider()
            if statsStore.isLoading {
                loadingRow
            } else if statsStore.sessionCount() == 0 {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        summarySection
                        Divider().padding(.vertical, 4)
                        heatmapSection
                        if !statsStore.topSkills(n: 5).isEmpty {
                            Divider().padding(.vertical, 4)
                            skillsSection
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
            }
        }
        .task { await statsStore.refresh() }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack {
            ForEach(StatsStore.Period.allCases, id: \.self) { p in
                Button(p.rawValue) { statsStore.period = p }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: statsStore.period == p ? .semibold : .regular))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        statsStore.period == p
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(statsStore.period == p ? .accentColor : .secondary)
            }
            Spacer()
            Button {
                Task { await statsStore.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("다시 스캔")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Summary

    private var summarySection: some View {
        let sessions = statsStore.sessionCount()
        let minutes  = statsStore.totalMinutes()
        let hours    = minutes / 60
        let mins     = minutes % 60
        let timeStr  = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"

        return HStack(spacing: 16) {
            statBadge(value: "\(sessions)", label: "세션")
            statBadge(value: timeStr,       label: "작업 시간")
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        let grid = statsStore.heatmap()
        let maxVal = grid.flatMap { $0 }.max() ?? 1

        let days = ["월", "화", "수", "목", "금", "토", "일"]

        return VStack(alignment: .leading, spacing: 3) {
            Text("시간대별 활동")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            // Hour axis labels aligned to grid cells (spacing: 1, cell width: 10)
            HStack(spacing: 1) {
                Spacer().frame(width: 17)  // matches day-label column
                ForEach(0..<24, id: \.self) { h in
                    if h % 3 == 0 {
                        Text("\(h)")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                            .frame(width: 10, alignment: .leading)
                    } else {
                        Spacer().frame(width: 10)
                    }
                }
            }

            // Grid rows
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 1) {
                    Text(days[row])
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .trailing)

                    ForEach(0..<24, id: \.self) { col in
                        let count = grid[row][col]
                        let density = maxVal > 0 ? Double(count) / Double(maxVal) : 0
                        Rectangle()
                            .fill(Color.accentColor.opacity(max(density * 0.9, count > 0 ? 0.15 : 0)))
                            .frame(width: 10, height: 8)
                            .cornerRadius(1)
                    }
                }
            }
        }
    }

    // MARK: - Skills

    private var skillsSection: some View {
        let top = statsStore.topSkills(n: 5)
        let maxCount = top.first?.count ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            Text("자주 쓴 스킬")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(top, id: \.name) { item in
                HStack(spacing: 6) {
                    Text("/\(item.name)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        let barWidth = geo.size.width * CGFloat(item.count) / CGFloat(maxCount)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: max(2, barWidth), height: 6)
                            .cornerRadius(2)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)
                    Text("\(item.count)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - States

    private var loadingRow: some View {
        HStack {
            ProgressView().scaleEffect(0.6)
            Text("스캔 중…")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private var emptyState: some View {
        Text("\(statsStore.period.rawValue) 활동 없음")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }
}
