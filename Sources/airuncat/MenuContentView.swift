import SwiftUI
import AppKit

// MARK: - Tab

private enum Tab { case sessions, skills, prompts, mcp, stats }

// MARK: - Filter Mode

private enum FilterMode: Equatable {
    case all, untagged
    case tag(String)
}

// MARK: - Main View

struct MenuContentView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var tagStore: TagStore
    @ObservedObject var usageStore: UsageStore
    @StateObject private var statsStore = StatsStore()
    @State private var activeTab: Tab = .sessions
    @State private var filter: FilterMode = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            if activeTab == .sessions {
                sessionsContent
            } else if activeTab == .skills {
                SkillsView(projectCwds: allClaudeCwds)
            } else if activeTab == .prompts {
                PromptLibraryView(store: store)
            } else if activeTab == .mcp {
                MCPView()
            } else {
                StatsView(statsStore: statsStore)
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .onChange(of: tagStore.sessionTags) {
            if case .tag(let t) = filter, !usedTags.contains(t) {
                filter = .all
            }
        }
    }

    // MARK: - Subviews

    private var tabBar: some View {
        HStack(spacing: 2) {
            TabButton("Sessions", icon: "rectangle.stack", active: activeTab == .sessions) { switchTab(.sessions) }
            TabButton("Skills", icon: "wand.and.stars", active: activeTab == .skills) { switchTab(.skills) }
            TabButton("Prompts", icon: "text.bubble", active: activeTab == .prompts) { switchTab(.prompts) }
            TabButton("MCP", icon: "puzzlepiece", active: activeTab == .mcp) { switchTab(.mcp) }
            TabButton("Stats", icon: "chart.bar", active: activeTab == .stats) { switchTab(.stats) }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func switchTab(_ tab: Tab) {
        withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
    }

    @ViewBuilder
    private var sessionsContent: some View {
        if !usedTags.isEmpty {
            filterBar
            Divider()
        }
        if filteredSessions.isEmpty && store.recentlyClosed.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let sorted = sortedSessions
                    let waiting = sorted.filter { $0.displayStatus == .waiting }
                    let others  = sorted.filter { $0.displayStatus != .waiting }
                    ForEach(waiting) { sessionRow($0) }
                    if !waiting.isEmpty && !others.isEmpty {
                        Rectangle()
                            .fill(Color.orange.opacity(0.22))
                            .frame(height: 2)
                            .padding(.vertical, 1)
                    }
                    ForEach(others) { sessionRow($0) }
                    if !store.recentlyClosed.isEmpty {
                        recentlyClosedSection
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        SessionRow(
            session: session,
            tagStore: tagStore,
            onTap: { store.resume(session) },
            onRename: { name in store.setCustomName(sessionId: session.sessionId, name: name) }
        )
        Divider().opacity(0.4)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("airuncat")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                // 응답 대기(나를 기다리는) 세션을 헤더에서 가장 먼저 알린다.
                if waitingCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8))
                            .foregroundColor(AiruncatDesign.statusColor(.waiting))
                        Text("\(waitingCount) 대기")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AiruncatDesign.statusColor(.waiting))
                    }
                }
                // C/G 카운트에 AI 정체성 색을 입혀 헤더도 같은 색 언어를 쓴다.
                summaryText
                    .font(.system(size: 11))
            }
            usageBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 사용량 (Anthropic 공식 API 실제 %)

    @ViewBuilder
    private var usageBar: some View {
        if let snap = usageStore.snapshot {
            HStack(spacing: 12) {
                usageGauge(label: "5h", percent: snap.fiveHourPercent, resetsAt: snap.fiveHourResetsAt,
                           stale: usageStore.isStale)
                if let wk = snap.weeklyPercent {
                    usageGauge(label: "wk", percent: wk, resetsAt: snap.weeklyResetsAt,
                               stale: usageStore.isStale)
                }
            }
        } else if let err = usageStore.error {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 8))
                Text("사용량 \(err.hint)").font(.system(size: 9))
                Spacer(minLength: 0)
            }
            .foregroundColor(.secondary)
            .help("Anthropic 사용량 API 호출 실패 — \(err.hint)")
        } else {
            Text("사용량 불러오는 중…")
                .font(.system(size: 9)).foregroundColor(Color.secondary.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// utilization %(서버 실제값) 게이지 + 리셋 카운트다운. stale=오류 중 직전 값 재사용(* 배지, R2).
    private func usageGauge(label: String, percent: Double, resetsAt: Date?, stale: Bool = false) -> some View {
        let pct = min(100, max(0, percent))
        let reset = Self.resetCountdown(resetsAt)
        return HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Self.gaugeColor(pct).opacity(stale ? 0.5 : 1))
                        .frame(width: max(2, geo.size.width * pct / 100))
                }
            }
            .frame(height: 5)
            Text("\(Int(pct.rounded()))%\(stale ? "*" : "")")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(stale ? .secondary : Self.gaugeColor(pct))
                .fixedSize()
            if let reset {
                Text(reset)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color.secondary.opacity(0.7))
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .help("\(label): \(Int(pct.rounded()))% 사용"
            + (reset.map { " · \($0) 후 리셋" } ?? "")
            + (stale ? " · 일시 오류 — 직전 값 표시 중" : ""))
    }

    /// 사용률 색(OMC 임계 70/90). 낮을수록 여유(Claude 보라), 높을수록 경고.
    private static func gaugeColor(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return AiruncatDesign.aiColor(.claude).opacity(0.75)
    }

    /// 리셋까지 남은 시간 "3h42m" / "2d5h". 지났으면 nil.
    private static func resetCountdown(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = Int(date.timeIntervalSinceNow)
        guard secs > 0 else { return nil }
        let m = secs / 60, h = m / 60, d = h / 24
        if d > 0 { return "\(d)d\(h % 24)h" }
        if h > 0 { return "\(h)h\(m % 60)m" }
        return "\(m)m"
    }

    private var waitingCount: Int {
        store.visibleSessions.filter { $0.displayStatus == .waiting }.count
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                FilterChip("All", active: filter == .all) { filter = .all }
                FilterChip("Untagged", active: filter == .untagged) { filter = .untagged }
                ForEach(usedTags, id: \.self) { tag in
                    FilterChip(tag, active: filter == .tag(tag)) { filter = .tag(tag) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var recentlyClosedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.4)
            Text("Recently Closed")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(store.recentlyClosed, id: \.info.id) { item in
                RecentlyClosedRow(item: item, onTap: { store.resumeClosed(item.info) })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No sessions")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("The cat naps until Claude gets to work.")
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { store.refresh() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            Button("G.md") {
                NSWorkspace.shared.open(URL(fileURLWithPath: ClaudeMdScanner.globalPath))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .help("글로벌 CLAUDE.md 열기")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Computed

    /// 헤더 요약. C는 Claude 보라, G는 Gemini 청록으로 칠해 색 언어를 유지한다.
    private var summaryText: Text {
        let c = store.claudeActiveCount
        let g = store.geminiActiveCount
        let a = c + g
        let i = store.idleCount
        let secondary = Color.secondary

        func dim(_ s: String) -> Text { Text(s).foregroundColor(secondary) }

        if a == 0 && i == 0 { return dim("all quiet") }
        if a == 0 { return dim("\(i) idle") }

        // 활성 파트: 색 입힌 C/G 스팬을 공백으로 잇는다.
        var active = Text("")
        var needSpace = false
        if c > 0 {
            active = Text("\(c)C").foregroundColor(AiruncatDesign.aiColor(.claude))
            needSpace = true
        }
        if g > 0 {
            if needSpace { active = active + dim(" ") }
            active = active + Text("\(g)G").foregroundColor(AiruncatDesign.aiColor(.gemini))
        }
        active = active + dim(" active")
        if i == 0 { return active }
        return active + dim(" · \(i) idle")
    }

    private var usedTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for s in store.visibleSessions {
            for tag in tagStore.tags(for: s.sessionId) where seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        return result
    }

    /// 보이는 Claude 세션들의 고유 cwd — 여러 프로젝트의 로컬 스킬을 모두 스캔하기 위함.
    private var allClaudeCwds: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in store.visibleSessions where s.aiKind == .claude && !s.cwd.isEmpty {
            if seen.insert(s.cwd).inserted { out.append(s.cwd) }
        }
        return out
    }

    private var filteredSessions: [SessionInfo] {
        switch filter {
        case .all:        return store.visibleSessions
        case .untagged:   return store.visibleSessions.filter { tagStore.tags(for: $0.sessionId).isEmpty }
        case .tag(let t): return store.visibleSessions.filter { tagStore.tags(for: $0.sessionId).contains(t) }
        }
    }

    /// 상태 우선 정렬: 응답 대기 > 작업 중 > idle > 휴식, 동률은 최근순.
    private var sortedSessions: [SessionInfo] {
        filteredSessions.sorted {
            $0.displayStatus.rawValue != $1.displayStatus.rawValue
                ? $0.displayStatus.rawValue < $1.displayStatus.rawValue
                : $0.lastActivity > $1.lastActivity
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let label: String
    let icon: String
    let active: Bool
    let action: () -> Void

    init(_ label: String, icon: String, active: Bool, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                // 활성 탭만 라벨을 펼쳐 320pt에 5탭이 깔끔히 들어가게.
                if active {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
            .foregroundColor(active ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Tag Color

private let tagPalette: [Color] = [
    .blue, .green, .orange, .purple, .red, .teal, .pink, .indigo
]

// DJB2: stable across launches (unlike hashValue which is randomized per process)
private func tagColor(_ tag: String) -> Color {
    var h: UInt32 = 5381
    for byte in tag.utf8 { h = h &* 31 &+ UInt32(byte) }
    return tagPalette[Int(h) % tagPalette.count]
}

private let tagIconEmpty  = NSImage(systemSymbolName: "tag",      accessibilityDescription: nil)!
private let tagIconFilled = NSImage(systemSymbolName: "tag.fill", accessibilityDescription: nil)!

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    init(_ label: String, active: Bool, action: @escaping () -> Void) {
        self.label = label
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(active ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundColor(active ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionInfo
    @ObservedObject var tagStore: TagStore
    let onTap: () -> Void
    let onRename: (String) -> Void

    @State private var hovering = false
    @State private var isEditing = false
    @State private var harness: HarnessInfo? = nil
    @State private var memoryCount: Int = 0
    @State private var claudeMdExists: Bool = false
    @State private var expanded = false

    /// 펼칠 상세(토큰/지속시간/payload)가 있을 때만 disclosure 노출.
    private var hasDetail: Bool {
        session.contextTokens != nil || session.durationSeconds != nil || session.activePayloadBytes != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .top, spacing: 9) {
            Capsule()
                .fill(AiruncatDesign.statusColor(session.displayStatus))
                .frame(width: 3, height: 28)
                .padding(.top, 3)

            Text(session.aiKind == .claude ? "C" : "G")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(AiruncatDesign.aiColor(session.aiKind).opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .foregroundColor(AiruncatDesign.aiColor(session.aiKind))
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(AiruncatDesign.statusLabel(session.displayStatus))
                        .font(.system(size: 9, weight: session.displayStatus == .waiting ? .bold : .medium))
                        .foregroundColor(AiruncatDesign.statusColor(session.displayStatus))
                        .fixedSize()
                    // R10: friction 배지 — 오류율↑/방치 갭이면 경고, 툴팁에 사유
                    if let friction = session.frictionReason {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                            .help(friction)
                    }
                    titleArea
                }
                if !session.lastUserMessage.isEmpty {
                    Text(session.lastUserMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let skill = session.activeSkill, session.workState == .working {
                    Text("/\(skill)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor.opacity(0.85))
                        .lineLimit(1)
                } else if !activity.isEmpty {
                    Text(activity)
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(relativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ClaudeMdBadgeButton(session: session)
                        .frame(width: 16, height: 14)
                        .opacity(claudeMdExists ? 1 : 0)
                    MemoryBadgeButton(session: session, memoryCount: $memoryCount)
                        .frame(width: 32, height: 14)
                        .opacity(memoryCount > 0 ? 1 : 0)
                    // Always reserve badge space to prevent layout shift when scan completes
                    HarnessBadgeButton(session: session, harness: $harness)
                        .frame(minWidth: 36, maxWidth: 52).frame(height: 14)
                        .opacity(harness != nil ? 1 : 0)
                    TagButton(sessionId: session.sessionId, tagStore: tagStore)
                        .frame(width: 14, height: 14)
                }
                if hovering && !isEditing {
                    Text(session.aiKind == .claude ? "resume" : "new session")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.top, 1)

            if hasDetail {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "접기" : "토큰·지속시간 보기")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onTap() } }

            if expanded { expandedDetail }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(rowBackground)
        .onHover { hovering = $0 }
        .task(id: session.cwd) {
            let info = await Task.detached(priority: .background) {
                HarnessScanner.scan(cwd: session.cwd)
            }.value
            harness = info
        }
        .task(id: session.id) {
            let jsonlPath = session.id
            let count = await Task.detached(priority: .background) {
                MemoryScanner.count(forJsonl: jsonlPath)
            }.value
            memoryCount = count
        }
        .task(id: session.cwd + "-claudemd") {
            let cwd = session.cwd
            let exists = await Task.detached(priority: .background) {
                ClaudeMdScanner.exists(cwd: cwd)
            }.value
            claudeMdExists = exists
        }
        .help(session.aiKind == .claude
            ? "Resume: claude -r \(session.sessionId)"
            : "Opens a new Gemini session in: \(session.cwd)")
    }

    @ViewBuilder
    private var titleArea: some View {
        if isEditing {
            InlineNameField(
                initialText: session.customName ?? session.projectName,
                onCommit: { name in
                    isEditing = false
                    onRename(name)
                },
                onCancel: { isEditing = false }
            )
            .frame(height: 16)
        } else {
            HStack(spacing: 4) {
                Text(session.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { isEditing = true }
                ForEach(tagStore.tags(for: session.sessionId), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(tagColor(tag).opacity(0.18))
                        )
                        .foregroundColor(tagColor(tag))
                }
                if !session.gitBranch.isEmpty {
                    Text(session.gitBranch)
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private var activity: String {
        if session.isThinking { return "생각 중…" }   // R9c: 도구 없이 추론 중일 때
        guard !session.toolName.isEmpty else { return "" }
        return session.toolDetail.isEmpty ? session.toolName : "\(session.toolName): \(session.toolDetail)"
    }

    /// 응답 대기 행은 주황 워시로 띄워 즉시 눈에 띄게.
    private var rowBackground: Color {
        if session.displayStatus == .waiting {
            return Color.orange.opacity(hovering ? 0.13 : 0.07)
        }
        return hovering ? Color.primary.opacity(0.08) : Color.clear
    }

    private var relativeTime: String {
        let s = Int(Date().timeIntervalSince(session.lastActivity))
        if s < 60 { return "\(max(s, 0))s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    // MARK: - 펼침 상세 (토큰·지속시간·활동)

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 14) {
                // R4: statusline 캐시의 네이티브 %가 있으면 우선(창 크기까지 정확), 없으면 합산 폴백.
                if let native = StatuslineManager.nativeContext(sessionId: session.sessionId) {
                    nativeContextGauge(native)
                } else if let tokens = session.contextTokens {
                    contextGauge(tokens)
                }
                if let dur = session.durationSeconds {
                    Text("\(Self.formatDuration(dur)) 지속 · \(relativeTime) 전 활동")
                        .font(.system(size: 9))
                        .foregroundColor(Color.secondary.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            // R7: API 요청 32MB 한계 압력 — 22MB↑에서만 노출(경고 22/위험 26)
            if let payload = session.activePayloadBytes, payload >= SessionScanner.payloadWarnBytes {
                payloadGauge(payload)
            }
        }
        .padding(.leading, 27)   // C 배지/텍스트 열 아래 정렬
        .padding(.trailing, 2)
    }

    /// payload 압력 게이지: "~23MB / 32MB" (22MB 노랑 / 26MB 빨강).
    private func payloadGauge(_ bytes: Int) -> some View {
        let limit = SessionScanner.payloadLimitBytes
        let ratio = min(1.0, Double(bytes) / Double(limit))
        let color: Color = bytes >= SessionScanner.payloadCritBytes ? .red : .yellow
        let mb = Double(bytes) / 1_048_576
        return HStack(spacing: 5) {
            Text(String(format: "payload ~%.0fMB / 32MB", mb))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color.opacity(0.8))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(width: 80, height: 4)
        }
        .help("API 요청 payload 근사치 — 32MB 한계에 가까워지면 /compact 권장")
    }

    /// 네이티브 컨텍스트 게이지 (R4): Claude Code가 계산한 %와 실제 창 크기(200k/1M) 표시.
    private func nativeContextGauge(_ native: StatuslineManager.NativeContext) -> some View {
        let ratio = Double(native.usedPercentage) / 100
        let sizeLabel = native.windowSize >= 1_000_000
            ? "\(native.windowSize / 1_000_000)M" : "\(native.windowSize / 1000)k"
        return VStack(alignment: .leading, spacing: 2) {
            Text("ctx \(native.usedPercentage)% · \(sizeLabel) 창")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(AiruncatDesign.aiColor(.claude).opacity(0.75))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
        .frame(width: 128)
        .help("Claude Code 네이티브 값 (statusline)")
    }

    /// 컨텍스트 창 채움 게이지: "82k / 200k (41%)" + 채움 바(200k 분모, 100% clamp).
    private func contextGauge(_ tokens: Int) -> some View {
        let limit = 200_000
        let ratio = min(1.0, Double(tokens) / Double(limit))
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(Self.formatK(tokens)) / 200k (\(Int(ratio * 100))%)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(AiruncatDesign.aiColor(.claude).opacity(0.75))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
        .frame(width: 128)
    }

    private static func formatK(_ n: Int) -> String {
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60, rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }
}

// MARK: - Tag Button (NSPopover)

private struct TagButton: NSViewRepresentable {
    let sessionId: String
    @ObservedObject var tagStore: TagStore

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.setButtonType(.momentaryLight)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.tapped(_:))
        applyImage(to: btn)
        return btn
    }

    func updateNSView(_ btn: NSButton, context: Context) {
        applyImage(to: btn)
        context.coordinator.sessionId = sessionId
    }

    private func applyImage(to btn: NSButton) {
        let tags = tagStore.tags(for: sessionId)
        if tags.isEmpty {
            btn.image = tagIconEmpty
            btn.contentTintColor = .tertiaryLabelColor
        } else {
            btn.image = tagIconFilled
            btn.contentTintColor = NSColor(tagColor(tags[0]))
        }
        btn.title = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, tagStore: tagStore)
    }

    @MainActor
    final class Coordinator: NSObject {
        var sessionId: String
        var tagStore: TagStore
        private var popover: NSPopover?

        init(sessionId: String, tagStore: TagStore) {
            self.sessionId = sessionId
            self.tagStore = tagStore
            super.init()
        }

        @objc func tapped(_ sender: NSButton) {
            if let p = popover, p.isShown { p.close(); return }
            let p = NSPopover()
            p.behavior = .transient
            let vc = NSHostingController(
                rootView: TagPopoverView(sessionId: sessionId, tagStore: tagStore)
            )
            p.contentViewController = vc
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            self.popover = p
        }
    }
}

// MARK: - Tag Popover

private struct TagPopoverView: View {
    let sessionId: String
    @ObservedObject var tagStore: TagStore
    @State private var newTag = ""
    @State private var editingTag: String? = nil
    @State private var editText = ""

    private var selected: Set<String> { Set(tagStore.tags(for: sessionId)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tagStore.tagPool, id: \.self) { tag in
                        tagRow(tag)
                    }
                }
            }
            .frame(maxHeight: 160)

            Divider()

            HStack(spacing: 4) {
                Text("+")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("new tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        tagStore.addTag(newTag, to: sessionId)
                        newTag = ""
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 200)
    }

    @ViewBuilder
    private func tagRow(_ tag: String) -> some View {
        let isSelected = selected.contains(tag)
        TagRowView(
            tag: tag,
            isSelected: isSelected,
            isEditing: editingTag == tag,
            editText: editingTag == tag ? $editText : .constant(""),
            onToggle: { toggleTag(tag) },
            onBeginEdit: { editingTag = tag; editText = tag },
            onCommitEdit: { commitRename(tag) }
        )
    }

    private func toggleTag(_ tag: String) {
        if selected.contains(tag) {
            tagStore.removeTag(tag, from: sessionId)
        } else {
            tagStore.addTag(tag, to: sessionId)
        }
    }

    private func commitRename(_ old: String) {
        tagStore.renameTag(old, to: editText)
        editingTag = nil
        editText = ""
    }
}

// MARK: - Tag Row

private struct TagRowView: View {
    let tag: String
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editText: String
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit { onCommitEdit() }
                Spacer()
                Button(action: onCommitEdit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(tag)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? tagColor(tag) : .primary)
                Spacer()
                if hovering {
                    Button(action: onBeginEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? tagColor(tag).opacity(0.12)
                : (hovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onToggle() } }
        .onHover { hovering = $0 }
    }
}

// MARK: - Recently Closed Row

private struct RecentlyClosedRow: View {
    let item: (info: SessionInfo, closedAt: Date)
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(item.info.aiKind == .claude ? "C" : "G")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(AiruncatDesign.aiColor(item.info.aiKind).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .foregroundColor(AiruncatDesign.aiColor(item.info.aiKind).opacity(0.7))

            Text(item.info.projectName.isEmpty ? item.info.displayName : item.info.projectName)
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 4)

            if hovering {
                Text(item.info.aiKind == .claude ? "Resume" : "Open new")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)
            } else {
                TimelineView(.periodic(from: item.closedAt, by: 1.0)) { ctx in
                    Text("\(Int(ctx.date.timeIntervalSince(item.closedAt)))s ago")
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
        .help(item.info.aiKind == .claude
            ? "Resume: claude -r \(item.info.sessionId)"
            : "Opens a new Gemini session in: \(item.info.cwd)")
    }
}

// MARK: - Inline Name Field

private struct InlineNameField: NSViewRepresentable {
    let initialText: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = initialText
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .labelColor
        field.cell?.sendsActionOnEndEditing = false
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: InlineNameField
        private var handled = false

        init(_ parent: InlineNameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                handled = true
                parent.onCommit((control as? NSTextField)?.stringValue ?? parent.initialText)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                handled = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !handled else { return }
            handled = true
            parent.onCommit((obj.object as? NSTextField)?.stringValue ?? parent.initialText)
        }
    }
}
