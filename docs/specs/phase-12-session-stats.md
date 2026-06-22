---
title: "Phase 12 — 세션 통계"
date: 2026-06-22
status: draft
---

# 목표

JSONL 파싱 결과를 집계해 Claude / Gemini 사용 패턴을 메뉴바에서 한눈에 확인한다.
기간 필터(주/월/전체), 히트맵, 자주 쓴 스킬 top-N.

# 현재 상태

- Sessions / Skills / Prompts / MCP 탭만 존재
- 사용 통계 없음

# 범위

**In:**
- `StatsScanner.swift` — `~/.claude/projects/` 전체 JSONL 집계, 캐시 증분 업데이트
- `StatsStore.swift` — `@MainActor ObservableObject`, 캐시 관리, 기간 필터 계산
- `StatsView.swift` — Stats 탭 UI (요약 바 + 히트맵 + 스킬 top-N)
- `MenuContentView.swift` — `Tab.stats` 케이스 추가

**Out:**
- Gemini 상세 통계 (Gemini JSONL 파싱은 Phase 4에서 처리)
- 프롬프트 사용 빈도 (palette-history가 이미 추적 — 향후 연동)
- 세션별 도구 사용 상세 분석

# 데이터 소스

| 필드 | 추출 방법 |
|------|---------|
| 시작 시간 | JSONL 첫 번째 `type=="user"` 이벤트의 `timestamp` |
| 종료 시간 | 파일 mtime |
| 세션 길이 | 종료 - 시작 (최대 2h 캡 — 잠든 사이 idle 제외) |
| 시간대 | 종료 시간의 `hour` (0-23) |
| 요일 | 종료 시간의 weekday (0=월, 6=일) |
| 날짜 | 종료 시간의 "YYYY-MM-DD" |
| 스킬 사용 | `type=="assistant"` 메시지의 `tool_use` 중 `name=="Skill"`의 `input.skill` |
| AI 종류 | `.claude` 고정 (Gemini는 Phase 4) |

# 모델

```swift
struct SessionStat: Codable, Sendable {
    let path: String           // JSONL 절대 경로 (캐시 키)
    let mtime: TimeInterval    // 마지막 수정 시각 (증분 업데이트 기준)
    let date: String           // "YYYY-MM-DD"
    let dayOfWeek: Int         // 0=월 .. 6=일
    let hourOfDay: Int         // 0 .. 23
    let durationMinutes: Int   // 캡 120분
    let skillsUsed: [String]   // 빈 배열 허용
}

struct StatsData: Codable, Sendable {
    var sessions: [SessionStat]
    var pathMtimes: [String: TimeInterval]  // 캐시 증분용
}
```

# StatsScanner.swift

```swift
enum StatsScanner {
    static let cachePath: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".airuncat/stats-cache.json")

    // 전체 스캔 — Task.detached(priority: .background)에서 호출
    // 기존 cache를 로드하고, mtime이 바뀐 파일만 재파싱, 삭제된 파일 제거
    static func scan() -> StatsData
}
```

**증분 전략:**
1. `stats-cache.json` 로드 (없으면 빈 StatsData)
2. `~/.claude/projects/*/*.jsonl` 목록 수집
3. 각 파일 mtime 비교 → 변경된 파일만 `parseStat(path:)`
4. 삭제된 경로는 `sessions` + `pathMtimes`에서 제거
5. 결과를 `stats-cache.json`에 저장 (`.atomic`)

**파일 1개 파싱 (`parseStat`):**
- 첫 번째 `type=="user"` 라인 찾기 (head 64KB) → `timestamp` 파싱
  - 못 찾으면 `startTime = mtime - 1800s` 근사 (시스템 메시지 다수 선행 케이스 대응)
- `tool_use name==Skill` 집계: 파일 크기 4MB 이하 전체 스캔, 초과 시 head+tail 512KB
  - tail 32KB는 초반 스킬이 잘리므로 사용하지 않음
- `durationMinutes` = `(mtime - startTime) / 60`, 최대 120분 캡 (잠든 후 재사용 시 idle 포함 방지)

**dayOfWeek 변환:**
Swift `Calendar.component(.weekday)` = 1=일 .. 7=토.
`0=월` 기준 변환: `(weekday + 5) % 7` → 0=월, 1=화, ..., 6=일

# StatsStore.swift

```swift
@MainActor
final class StatsStore: ObservableObject {
    enum Period { case week, month, all }

    @Published var data: StatsData = StatsData(sessions: [], pathMtimes: [:])
    @Published var isLoading: Bool = false
    @Published var period: Period = .week

    func refresh() async          // guard !isLoading 후 Task.detached 스캔 → data 갱신
    func filtered() -> [SessionStat]   // period 기준 필터
    func heatmap() -> [[Int]]     // 7×24, filtered() 기준
    func topSkills(n: Int) -> [(String, Int)]  // filtered() 기준 빈도 상위 n개
    func totalMinutes() -> Int
    func sessionCount() -> Int
}
```

# StatsView.swift

```
[이번 주 ▾]                            [새로고침]
────────────────────────────────
  Claude   47세션   ████████░░  12.4h
────────────────────────────────
  시간대별 활동 히트맵
       00 03 06 09 12 15 18 21
  월   ░░░░░░████████████░░░░░░
  화   ░░░░░░░░████████████░░░░
  수   ░░░░░░░██████████░░░░░░░
  목   ░░░░░░░░░░░░░░░░░░░░░░░░
  금   ░░░░░░████████████████░░
  토   ░░░░░░░░░░░░░░░░░░░░░░░░
  일   ░░░░░░░░░░░░░░░░░░░░░░░░
────────────────────────────────
  자주 쓴 스킬 (이번 주)
  /ultrawork      ████  23회
  /run-clawde     ███   18회
  /gemini-review  ██    11회
```

**히트맵 구현:**
- SwiftUI `Grid` (7행 × 24열) — `Rectangle().fill(accentColor.opacity(density))`
- `density = min(1.0, Double(count) / Double(maxCell + 1))` (0이면 투명)
- 셀 크기: 10×8pt (고정, 스크롤 없음)

**레이아웃:**
- 전체 너비 300pt (MenuBarExtra 기본 폭)
- 요약 섹션 + 히트맵 섹션 + 스킬 섹션 (VStack)
- 최대 높이: 480pt (스크롤 없음, 섹션 자체 압축)

# MenuContentView.swift 수정

```swift
private enum Tab { case sessions, skills, prompts, mcp, stats }
```
- 탭 버튼에 `TabButton("Stats", ...)` 추가
- Stats 탭 선택 시 `StatsView(store: statsStore)`
- `@StateObject private var statsStore = StatsStore()` 추가

# 수정·신규 파일

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/StatsScanner.swift` | 신규 |
| `Sources/airuncat/StatsStore.swift` | 신규 |
| `Sources/airuncat/StatsView.swift` | 신규 |
| `Sources/airuncat/MenuContentView.swift` | Tab.stats 추가 |
| `~/.airuncat/stats-cache.json` | 런타임 생성 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| JSONL 파일 없음 | "데이터 없음" 빈 상태 표시 |
| 타임스탬프 파싱 실패 | `startTime = mtime - 1800s` 근사 |
| 이번 주 세션 0건 | "이번 주 활동 없음" 표시 |
| 스캔 중 파일 삭제 | `try?` 실패 → 해당 파일 스킵 |
| 히트맵 전체 0 | 모든 셀 투명 (accentColor.opacity(0)) |
| 캐시 JSON 손상 | decode 실패 → 빈 StatsData로 전체 재스캔 |

# 검증

1. `swift build` 통과
2. Stats 탭 클릭 → 로딩 스피너 → 통계 표시
3. 기간 필터 변경 → 히트맵 즉시 갱신
4. 히트맵 셀: 낮 시간대가 밤보다 진하게 표시 (실제 사용 패턴 반영)
5. 자주 쓴 스킬 top-N 표시
6. 새로고침 버튼 → 재스캔
7. 두 번째 열기 → 캐시에서 즉시 로드 (백그라운드 재스캔 병행)
