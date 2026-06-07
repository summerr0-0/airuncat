# Spec: hide-resting-sessions

## Meta
- **Created**: 2026-06-06
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-06-06

## Goal
세션이 끝난 애들은 지우는거 — 창을 닫은(더 이상 활성이 아닌) 세션이 드롭다운에 계속 남아있는 문제 해결.

## Non-goals
- `.jsonl` 파일 실제 삭제 (read-only 규칙)
- 수동 dismiss UI (X 버튼, Clear 버튼 등)
- Gemini CLI 세션 처리 (Phase 4 예정)

## Confirmed Goal
`resting` 상태(마지막 활동 30분+ 경과)인 세션을 드롭다운에서 자동으로 숨긴다. 사용자가 창을 닫고 세션 작업이 끝나면 목록에서 사라지게 한다.

## Decisions

### D1: "종료된 세션" = resting 상태 (30분+ 비활동)
- **Status**: resolved
- **Rationale**: 사용자 멘탈 모델상 "창이 닫힌" = 오래 전에 활동이 끊긴 세션. `SessionStatus.resting`(30분+ 경과)이 이에 해당. 실제 프로세스 존재 여부를 파악하는 방식(ps/lsof)은 복잡도 대비 이점이 없음 — mtime 기반 상태로 충분.

### D2: visibleSessions에서 resting 제외
- **Status**: resolved
- **Rationale**: `SessionStore.visibleSessions`의 기존 8h 커트오프를 변경해 `active` + `idle`만 남김. 반론: 사용자가 보고 싶은 resting 세션이 동의 없이 사라진다는 agency 문제. 하지만 D3에서 확인했듯이 resting 세션은 영구 삭제가 아님 — 다시 활동하면 3초 안에 자동 재표시됨. 따라서 정보 손실 없음. 수동 dismiss UI는 이 tradeoff를 해소하는 대안이지만, 사용자가 "창이 닫혀있으면 없어져야 한다"고 명시했으므로 자동 필터가 의도된 동작.

### D3: resting → active/idle 전환 시 자동 재표시
- **Status**: resolved
- **Rationale**: `SessionInfo.status`는 `lastActivity` 기반 computed property. 세션이 다시 활성화되면 다음 스캔(3s)에서 자동으로 `visibleSessions`에 포함됨. 별도 로직 불필요.

### D4: 정렬은 최근 활동순 유지
- **Status**: resolved (assumed — 기존 구현 확인)
- **Rationale**: `SessionScanner.scan()`이 이미 `lastActivity` 내림차순 정렬 반환. 변경 없음.

## Constraints
- `~/.claude/projects/**/*.jsonl` 읽기 전용, 실제 파일 삭제 금지
- CLT 빌드만 허용 (xcodebuild 금지)
- 메뉴바 아이콘은 template image 유지

## Known Gaps
(none)

## Tasks

### T1: visibleSessions 필터에서 resting 세션 제외 [vertical]
- **Fulfills**: R0, R1
- **Depends on**: (none)
- **Files**: `Sources/Clawde/SessionStore.swift` (L32-35)
- **Note**: R1.1(자동 재표시)은 기존 computed property 구조상 T1 변경만으로 자동 충족됨 — 추가 코드 불필요

## External Dependencies

### Pre-work
(none)

### Post-work
- `./build.sh` 빌드 후 앱 재시작해 resting 세션이 드롭다운에서 사라지는지 확인

## Requirements

### R0: resting 세션을 드롭다운에서 자동으로 숨긴다

#### R0.1: resting 세션이 visibleSessions에 포함되지 않음
- **Given**: 마지막 활동이 30분 이상 전인 세션(resting 상태)이 존재
- **When**: `SessionStore.visibleSessions`가 평가됨
- **Then**: 해당 세션이 반환 목록에 포함되지 않음

#### R0.2: active/idle 세션은 계속 표시됨
- **Given**: 마지막 활동이 30분 이내인 세션(active 또는 idle 상태)이 존재
- **When**: `SessionStore.visibleSessions`가 평가됨
- **Then**: 해당 세션이 반환 목록에 포함됨

#### R0.3: 모든 세션이 resting이면 empty state 표시
- **Given**: 스캔된 모든 세션이 resting 상태임
- **When**: 드롭다운을 열었을 때
- **Then**: "No recent sessions" empty state가 표시됨 (기존 emptyState 뷰 그대로)

### R1: resting에서 활성화된 세션은 자동 재표시

#### R1.1: resting → idle/active 전환 후 자동 재표시
- **Given**: resting 상태로 드롭다운에서 숨겨진 세션이 있음
- **When**: 해당 세션에 새 활동이 발생해 mtime이 갱신되고 다음 스캔(≤3초)이 실행됨
- **Then**: 해당 세션이 active 또는 idle 상태로 드롭다운에 다시 나타남

## Research
- `SessionStatus` 열거형: `active`(< 90s), `idle`(< 30min), `resting`(30min+) (`SessionScanner.swift:3-13`)
- `visibleSessions`는 현재 8시간 커트오프만 적용, `resting` 포함 (`SessionStore.swift:32-35`)
- 드롭다운은 `store.visibleSessions`를 ForEach로 렌더 (`MenuContentView.swift:15`)
- `SessionInfo.status`는 `lastActivity`를 기반으로 한 computed property (`SessionScanner.swift:35`)
- `SessionRow.statusColor`에서 `resting` = gray dot 이미 정의됨 (`MenuContentView.swift:158-163`)
- 수정 포인트: `visibleSessions` 필터에 `.resting` 제외 조건 추가 — 1줄 변경 예상
- 빌드: `./build.sh` (CLT only, xcodebuild 금지) (`build.sh`, `.claude/rules/clt-build-only.md`)
