# Spec: session-time-context

## Meta
- **Created**: 2026-07-03
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-07-03

## Goal
세션별로 시간(지속 시간·마지막 활동)과 context(컨텍스트 창 토큰 사용량)를 볼 수 있게 하고,
airuncat에서 Claude Code 사용량을 시간별(5시간 롤링) 세션 창과 주간(wk) 창으로 확인할 수 있게 한다.

## Non-goals
- 세션 JSONL 쓰기/이동/삭제 — 읽기 전용 유지(`read-only-sessions.md`).
- Claude 서버의 실제 사용 한도 자동 감지 — 플랜 한도는 사용자가 설정에 수동 입력.
- 정확한 과금/토큰 회계 재현 — airuncat 계산은 JSONL usage 합산 기반 **근사치**.
- Gemini 세션 사용량 — 이번 범위는 Claude Code 한정.
- 5시간/주간 창 리셋 타이밍의 Claude 서버 정책 정확 재현(롤링 윈도 근사).

## Confirmed Goal
두 부분으로 나뉜다.

**A. 세션별 시간·context (per-session)**
각 Claude 세션에 대해 다음을 표시:
- **컨텍스트 창 토큰 사용량**: 최신 assistant 메시지 `usage`(input + cache_read + cache_creation)로
  현재 컨텍스트가 얼마나 찼는지(예: 82k). 200k 대비 비율로도 표현 가능.
- **지속 시간(duration)**: 세션 첫 이벤트 timestamp ~ 마지막 활동까지 경과.
- **마지막 활동 시각**: 이미 있는 `lastActivity`(상대 표기).

**B. airuncat 전역 사용량 창 (usage windows)**
전체 Claude 세션(모든 프로젝트) JSONL의 **소비 메트릭(D4b: cache_read ≈0.1x 가중)**을
메시지 timestamp로 시간창별 합산:
- **5시간 롤링 세션 창**: now-5h 기준 누적 소비량.
- **주간(wk) 창**: 설정된 리셋 요일/시각 기준 누적 소비량.
- 각 창을 **별도 한도**(D3: `fiveHourLimit`/`weeklyLimit`, 단위=가중 토큰) 대비 "남은 %/양"으로 표시.
- per-session 컨텍스트 채움은 D4a(raw, vs 200k)로 별개 메트릭.

**Done when**
- 세션 행/상세에서 토큰 사용량·duration·마지막 활동을 볼 수 있다.
- airuncat 어딘가(헤더/전용 뷰)에서 5시간·주간 소비량과 남은 %를 볼 수 있다.
- 플랜 한도를 설정에서 입력·수정할 수 있다.
- `swift build` 그린, `./build.sh` 후 라이브에서 값이 그럴듯하게 뜬다.

## Research
**세션 파싱 / 데이터 모델**
- `SessionInfo`에 `lastActivity: Date`, `messageCount: Int`는 있으나 **duration·토큰 usage 필드 없음**
  (`Sources/airuncat/SessionScanner.swift:48-49`). per-session 표시는 신규 필드 파싱 필요.
- 세션 활성 판정은 mtime 기반(`SessionScanner.swift:8-9`, active<90s/idle<30m). 읽기 전용 규칙
  (`.claude/rules/read-only-sessions.md`) — 파싱만, 큰 파일은 head/tail.

**시간·집계 재사용 자산 (StatsScanner)**
- 이벤트 timestamp 파싱 이미 존재: `readStartTimestamp`/`readEndTimestamp`,
  ISO8601(withFractionalSeconds) (`Sources/airuncat/StatsScanner.swift:106-152`). duration·창 합산에 재사용.
- mtime 증분 캐시 패턴(`pathMtimes`, 변경 파일만 재파싱) (`StatsScanner.swift:53-62,183-190`).
  usage 창 집계도 같은 캐시 전략 적용 가능.
- `SessionStat`에 **토큰 필드 없음**(path/mtime/date/dow/hour/durationMinutes/skillsUsed only)
  (`StatsScanner.swift:5-13`). `durationMinutes`는 120분 캡 — 5h/주간 창엔 부적합, 별도 집계 필요.
- **`usage` 토큰(input/output/cache_read/cache_creation) 파싱은 코드 어디에도 없음** → 신규.
  창 집계는 세션 총합이 아니라 **메시지별 (timestamp, tokens)** 이 필요.

**설정/한도 저장**
- 전용 SettingsView/Store·`@AppStorage`·UserDefaults **미존재**(phase-9 스펙만 있고 미구현).
- 소형 JSON 스토어 관례: `PathConstants` + 원자 쓰기(`customNames`, `tags`, `paletteHistory`)
  (`Sources/airuncat/PathConstants.swift:27-34`). 플랜 한도는 `~/.airuncat/settings.json`(신규) 권장.

**UI 진입점**
- per-session 표시: `MenuContentView` SessionRow(제목/상태/툴 표기 부근, `MenuContentView.swift:360-400`).
- 전역 사용량 뷰: 헤더(`MenuContentView.swift:113-135`) 또는 Stats 탭(`StatsView.swift`) 확장.
- 색 언어: `AiruncatDesign`(aiColor/statusColor) 토큰 재사용.

## Decisions

### D1: per-session 표시 = 토큰 컨텍스트 사용량 + duration + 마지막 활동
- **Status**: resolved
- **Rationale**: 사용자 확인. duration은 첫 이벤트~마지막 활동, 활동은 기존 lastActivity 재사용.

### D2: 전역 사용량 두 창 = 5시간 롤링 + 주간
- **Status**: resolved
- **Rationale**: Claude Code 한도 구조(5h 세션 창 + weekly)에 대응. 단일 창(누적만)은 한도 감각을
  못 줘 기각.

### D3: 남은 양 = 소비량 / 사용자 입력 한도 (5h·주간 **각각 별도** 한도)
- **Status**: resolved (L2-reviewer fix)
- **Rationale**: Claude는 5시간 창과 주간 창에 **독립된 한도**를 건다 → 설정 필드는 하나가 아니라
  `fiveHourLimit` + `weeklyLimit` **둘**. 실제 한도는 서버측이라 JSONL에 없어 수동 입력.
  단위는 D10(가중 토큰) 참조. 로컬 한도 파일 조사(대안)는 존재 불확실 + read-only 부담으로 기각.

### D4: 메트릭 2종 — 컨텍스트 채움(raw) vs 소비량(가중)
- **Status**: resolved (L2-reviewer fix — 차원 불일치·cache 과대계상 해소)
- **D4a 컨텍스트 채움(per-session, D8)**: `input_tokens + cache_read + cache_creation`(**raw, 1:1**).
  컨텍스트 창 **점유량**은 cache 토큰도 실제로 창에 들어있으므로 raw 합산이 정확. 200k 대비 %.
- **D4b 소비량(5h·주간 창, D2/D3/D7)**: `input + output + cache_creation`은 1:1,
  **`cache_read`는 ~0.1x 가중**. Claude가 cache_read를 크게 할인 계상하므로 1:1 합산(기각)은
  긴 세션에서 소비를 5~10배 과대계상 → "남은 %"가 일관되게 '소진' 편향(방향성 오류). 가중이 근사 개선.
- **Rationale**: 두 목적(창 점유 vs 소비율)이 서로 다른 단위임을 분리. 단일 raw 합산(기각)은 소비
  창에서 편향, 단일 가중(기각)은 컨텍스트 점유를 과소표시. 가중치 0.1은 근사이며 C3/C6로 표기·보정.

### D10: 한도 단위 = 가중 토큰(D4b), 티어 프리셋 + 사용자 보정
- **Status**: resolved (L2-reviewer fix — 입력 단위 정의)
- **Rationale**: 실제 플랜은 티어명(Pro/Max 5x/20x)이라 사용자가 정확한 토큰 예산을 모름. 그래서
  ① 설정에 **티어 프리셋**(근사 기본 5h/주간 예산)을 두어 시작점 제공, ② 사용자가 실제 벽에 부딪힌
  시점을 보고 숫자를 **보정**. 한도 단위 = airuncat이 표시하는 **가중 토큰(D4b)**과 동일 단위라
  분자/분모 차원 일치. 프리셋 숫자는 근사(C3).

### D5: 렌더 위치 = per-session은 세션 행 확장, 전역 창은 헤더 요약
- **Status**: resolved
- **Rationale**: 상시 감각(헤더 게이지) vs 상세(행 펼침) 분리. Stats 탭 몰기는 상시성 약해 기각.

### D6: 한도 미입력 시 = 입력 유도 배너(소비량은 표시, 남은 %는 배너로 유도)
- **Status**: resolved
- **Rationale**: 소비량만 조용히 표시(대안)는 기능 발견성이 낮아 기각. 기본값 가정은 플랜이 틀리면
  오해 유발이라 기각. 배너가 명시적.

## Round 1 — Unknown/Unknown Detection
- **Tier 1 (Actor)**: user / 세션파일 / 설정스토어 / Claude(소비원) — 모두 D3·D5·D6가 커버. 신규 없음.
- **Tier 2 (Implication)**:
  - D4 → 5h 롤링 창은 파일-총합 캐시로 불충분, **메시지별 시간 버킷** 필요 → +DM4(집계 캐시 세분화).
  - D6 → 한도 입력 UI 진입점 필요(L1: 설정 UI 미존재) → +CB6(한도 입력 UI 위치).
  - D5 → 세션 행 확장 상호작용 필요(현 행에 disclosure 없음) → assumed(disclosure 추가).
- **Tier 3 (Pair)**: 고위험 도메인(동시성/권한/물리) 없음 → skip.

### D7: 창 경계 = 5h는 now-5h 롤링, 주간은 설정된 리셋 요일/시각 기준
- **Status**: resolved
- **Rationale**: 5h는 롤링이 Claude 세션 창 감각에 맞음. 주간은 캘린더 고정(월 00:00)/롤링 7일보다
  **리셋 요일 설정**이 실제 플랜 리셋에 맞출 수 있어 채택(플랜마다 리셋 요일 다름). 설정 스키마에
  weeklyResetWeekday(+시각) 추가.

### D8: per-session 컨텍스트 분모 = 고정 200k
- **Status**: resolved
- **Rationale**: 대부분 Claude 모델이 200k. 모델별 감지(대안)는 복잡도 대비 이득 적고, 절대값만은
  '얼마나 찼나' 감각을 못 줘 기각. 1M 베타 등 200k 초과 시 100%로 clamp + 실제 수치 병기(assumed).

### D9: 한도/리셋 입력 UI = Stats 탭 설정 영역
- **Status**: resolved
- **Rationale**: 사용량 맥락(Stats)과 같은 곳에 한도 입력을 묶음. 헤더 배너(D6)는 **유도만** 하고
  클릭 시 Stats 탭으로 유도. 별도 설정 패널 신규는 범위 과대라 기각.

## Round 2 — Unknown/Unknown Detection
- **Tier 2 (Implication)**:
  - D7 → 설정 스키마에 weeklyResetWeekday/time 필요 → D9 설정 영역이 커버.
  - D7(롤링) → 매 tick "now" 재계산 → StatsStore period 갱신 패턴 재사용(assumed).
  - D8 → 200k 초과 세션 clamp 처리 → assumed(100% clamp + 실제 수치).
  - EE1(usage 없는 오래된/부분 메시지) → 해당 메시지 0 처리·스킵(assumed).
- **Tier 1/3**: 신규 액터/페어 텐션 없음.

## Inversion Probe (composite ≥ 0.80)
- **Inversion — 모든 요구 충족해도 실패할 시나리오**: airuncat의 토큰 합산 근사가 Claude의 실제
  한도 회계(요청 복잡도·cache 가중치 등 서버 정책)와 크게 어긋나면 "남은 %"가 **확신에 찬 오답**이
  되어 잘못된 안심을 줄 수 있음. → 완화: UI에 **"근사치(approx)"** 명시(Constraint C3). 새 미해결
  체크포인트 없음(제품 정책으로 흡수).
- **Implication — 가장 영향 큰 결정(D4×D7)**: 모든 프로젝트 JSONL을 메시지 단위로 매 tick 합산하면
  대용량 히스토리에서 성능 부담. → 완화: 메시지별 시간버킷을 **파일 mtime 증분 캐시**, 창 범위 밖
  파일은 스킵(Constraint C2, DM4). 새 미해결 체크포인트 없음.

## Constraints
- C1: 세션 JSONL·`~/.gemini/tmp`는 읽기 전용(파싱만). 쓰기/이동/삭제 금지.
- C2: 창 집계는 mtime 증분 캐시 + 창 범위 밖 파일 스킵으로 매 tick 전체 재파싱 회피.
- C3: 소비량·남은 %는 **근사치**임을 UI에 표기(서버 실제 한도와 다를 수 있음).
- C4: CLT 빌드만(`swift build`/`build.sh`), Xcode/xcodeproj 금지.
- C5: 색은 `AiruncatDesign` 토큰 재사용, 신규 하드코딩 색 금지.
- C6: 소비 메트릭은 `cache_read` **가중(≈0.1x)** 적용(D4b). 가중치는 상수로 두어 후일 조정 가능.
  컨텍스트 채움(D4a)은 raw 합산 유지(별도 목적).

## Known Gaps
- L2 provisional: cache_read 가중치 0.1은 관측 기반 추정 — 실제 Claude 계상비와 다르면 상수 조정 필요.
- (그 외 체크포인트 모두 resolved/assumed.)

## Requirements

### R0: 세션 시간·context 가시화 + Claude Code 사용량 창 (goal)
#### R0.1: 드롭다운에서 세션 상세와 사용량 창 확인
- **Given**: airuncat 실행 중, Claude 세션이 하나 이상 존재
- **When**: 메뉴바 드롭다운을 연다
- **Then**: 헤더에 5h·주간 사용량 요약이 보이고, 세션 행을 펼치면 토큰·duration·마지막 활동이 보인다

### R1: per-session 데이터 파싱 (D1, D4a, D8)
#### R1.1: 컨텍스트 채움 토큰 파싱(raw)
- **Given**: 세션 JSONL 최신 assistant 메시지에 `usage`(input_tokens, cache_read_input_tokens, cache_creation_input_tokens)
- **When**: SessionScanner가 세션(tail)을 파싱
- **Then**: `contextTokens = input + cache_read + cache_creation`가 SessionInfo에 채워진다
#### R1.2: duration 파싱
- **Given**: 세션 첫 이벤트 timestamp와 마지막 활동 시각
- **When**: 파싱(첫 timestamp는 head, 마지막은 mtime/last event)
- **Then**: `durationSeconds = last − first`가 채워진다(첫 timestamp 없으면 nil)
#### R1.3: usage 없는 세션 안전 처리
- **Given**: `usage` 필드가 없는 오래된/부분 세션
- **When**: 파싱
- **Then**: `contextTokens = nil`(표시 생략), 크래시·예외 없음
#### R1.4: 200k 초과 clamp
- **Given**: `contextTokens > 200_000`
- **When**: 비율 계산
- **Then**: 게이지는 100%로 clamp하되 실제 수치는 병기

### R2: per-session 행 확장 UI (D1, D5)
#### R2.1: 행 펼침 disclosure
- **Given**: 세션 행 목록(현재 disclosure 없음)
- **When**: 사용자가 행의 펼침 토글을 누른다
- **Then**: 그 행 아래에 토큰 게이지·duration·마지막 활동이 나타나고, 다시 누르면 접힌다
#### R2.2: 컨텍스트 채움 게이지
- **Given**: `contextTokens = 82_000`
- **When**: 행을 펼친다
- **Then**: "82k / 200k (41%)" 텍스트 + 채움 바(AiruncatDesign 색)로 표시된다
#### R2.3: duration·활동 표기
- **Given**: `durationSeconds = 5400`, lastActivity = 2분 전
- **When**: 행을 펼친다
- **Then**: "1h 30m 지속 · 2분 전 활동"로 표기된다(contextTokens=nil이면 토큰 줄 생략)

### R3: 사용량 창 집계 (D2, D4b, D7, C2)
#### R3.1: 소비 메트릭 가중 집계
- **Given**: 기간 내 assistant 메시지들의 `usage`
- **When**: 창 집계
- **Then**: `consumption = Σ(input + output + cache_creation + 0.1×cache_read)` (가중 상수 C6)
#### R3.2: 5시간 롤링 창
- **Given**: 현재 시각 now
- **When**: 5h 창 집계
- **Then**: 메시지 timestamp ≥ now−5h 인 것만 합산한다
#### R3.3: 주간 창(리셋 요일 기준)
- **Given**: 설정 `weeklyResetWeekday`(+시각)
- **When**: 주간 창 집계
- **Then**: now 이전의 가장 최근 리셋 시점 이후 메시지만 합산한다
#### R3.4: 증분 캐시로 재집계 비용 절감
- **Given**: 파일 mtime 캐시(StatsScanner 패턴)
- **When**: tick마다 재집계
- **Then**: mtime 불변 파일은 캐시된 메시지 시간버킷을 재사용하고, 창 범위 밖 파일은 스킵한다

### R4: 전역 헤더 사용량 요약 UI (D5, D6)
#### R4.1: 5h·주간 게이지 표시
- **Given**: 5h 소비=X, 주간 소비=Y, 두 한도 모두 입력됨
- **When**: 헤더를 렌더
- **Then**: "5h X/limit (n%)", "wk Y/limit (m%)" 게이지가 근사 표기(C3)와 함께 보인다
#### R4.2: 한도 미입력 시 유도 배너
- **Given**: `fiveHourLimit`/`weeklyLimit` 미설정
- **When**: 헤더를 렌더
- **Then**: 소비 절대값은 표시하되 "한도 설정" 배너를 띄우고, 클릭 시 Stats 탭 설정 영역으로 이동

### R5: 설정 저장 + Stats 탭 입력 UI (D3, D9, D10)
#### R5.1: 설정 원자 저장
- **Given**: 사용자가 5h/주간 한도·리셋 요일을 입력
- **When**: 저장
- **Then**: `~/.airuncat/settings.json`에 원자 쓰기(customNames/tags 패턴)로 기록된다
#### R5.2: Stats 탭 설정 영역
- **Given**: Stats 탭이 열림
- **When**: 설정 영역을 표시
- **Then**: `fiveHourLimit`/`weeklyLimit` 입력 필드 + 리셋 요일 선택 + 티어 프리셋 버튼이 보인다
#### R5.3: 티어 프리셋 적용
- **Given**: 사용자가 "Max 5x" 프리셋을 누른다
- **When**: 적용
- **Then**: 근사 기본 한도값이 두 필드에 채워지고, 이후 수동 보정이 가능하다
#### R5.4: 설정 로드
- **Given**: `settings.json` 존재/부재
- **When**: 앱 시작
- **Then**: 있으면 한도·리셋 요일을 로드, 없으면 미설정 상태(R4.2 배너)로 둔다

### R6: 남은 % 계산 (D3)
#### R6.1: 남은 % 산출·초과 처리
- **Given**: 소비=X, 한도=L(L>0)
- **When**: 남은 % 계산
- **Then**: `remaining% = max(0, (1 − X/L))×100`, X>L이면 0%·"초과" 표기
#### R6.2: 한도 0/미설정 방어
- **Given**: L이 nil 또는 0
- **When**: 계산
- **Then**: 남은 % 대신 절대 소비량만 반환(0 나눗셈 없음)

## Tasks

### T1: 설정 스토어 + 스키마 [infra]
- **Fulfills**: R5.1, R5.4
- **Depends on**: (none)
- 신규 `SettingsStore` + `~/.airuncat/settings.json`(원자 쓰기): `fiveHourLimit`, `weeklyLimit`,
  `weeklyResetWeekday`(+시각), 티어 프리셋 상수. `PathConstants`에 경로 추가. load/save.

### T2: SessionScanner 토큰·duration 파싱 [infra]
- **Fulfills**: R1.1, R1.2, R1.3, R1.4
- **Depends on**: (none) — T1과 병렬(다른 파일)
- `SessionInfo`에 `contextTokens: Int?`, `durationSeconds: Int?` 추가. tail에서 최신 usage 합산(raw),
  head 첫 timestamp로 duration. usage 없으면 nil. 파싱만(read-only).

### T3: 사용량 창 집계 + 남은 % [infra/service]
- **Fulfills**: R3.1, R3.2, R3.3, R3.4, R6.1, R6.2
- **Depends on**: T1 (남은 % 계산에 한도 소비)
- 신규 `UsageScanner`(메시지별 timestamp+가중토큰, mtime 증분 캐시, StatsScanner 패턴 재사용) +
  `UsageStore`(5h/주간 창 합산, remaining% 산출·0방어). 창 밖 파일 스킵.

### T4: per-session 행 확장 UI [vertical]
- **Fulfills**: R2.1, R2.2, R2.3
- **Depends on**: T2 (contextTokens/duration 소비)
- `MenuContentView` SessionRow에 disclosure 토글 + 펼침 영역(토큰 게이지·duration·활동). 디자인 토큰 색.

### T5: 헤더 사용량 요약 + 유도 배너 [vertical]
- **Fulfills**: R0.1, R4.1, R4.2
- **Depends on**: T3 (사용량 데이터), T4 (MenuContentView 파일 겹침 → 직렬화)
- `MenuContentView` 헤더에 5h/주간 게이지, 근사(C3) 표기. 한도 미입력 시 배너 → 클릭 시 Stats 탭 이동.

### T6: Stats 탭 설정 영역 + 프리셋 [vertical]
- **Fulfills**: R5.2, R5.3
- **Depends on**: T1 (SettingsStore 소비) — T4/T5와 병렬(StatsView, 다른 파일)
- `StatsView` 하단에 한도 입력 필드 + 리셋 요일 선택 + 티어 프리셋 버튼. 저장 시 T1 스토어 갱신.

## External Dependencies

### Pre-work
- (none) — 모든 데이터는 로컬 JSONL/설정 파일, 신규 외부 의존 없음.

### Post-work
- `./build.sh` + `/run-clawde`로 헤더 게이지·행 확장·Stats 설정 라이브 검증(수동 시나리오).
- cache_read 0.1x 가중치를 실제 사용 관측과 대조해 상수 보정(Known Gaps).
