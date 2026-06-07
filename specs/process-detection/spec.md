# Spec: process-detection

## Meta
- **Created**: 2026-06-06
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-06-06

## Goal
pgrep + lsof로 실제 claude 프로세스가 세션 cwd에서 돌고 있는지 탐지. 프로세스 없으면 드롭다운에서 숨김.

## Non-goals
- mtime 기반 active/idle/resting 상태 dot 색상 제거 (유지)
- 수동 dismiss 버튼 (이번 피처 범위 외)
- Gemini CLI 프로세스 탐지

## Confirmed Goal
`pgrep -x claude`로 실행 중인 claude 프로세스 PID를 수집하고, `lsof`로 각 PID의 cwd를 추출해 세션 cwd와 매칭. live process가 있는 cwd의 세션만 드롭다운에 표시.

## Decisions

### D1: pgrep -x claude + lsof -p <pid> cwd 컬럼으로 탐지
- **Status**: resolved
- **Rationale**: `pgrep -x claude`로 정확한 claude CLI PID 수집 후, `lsof -p <pid> | awk 'NR>1 && $4=="cwd"{print $NF}'`로 cwd 추출. 실제 검증 완료(~120ms/2프로세스). `ps aux | awk` 방식도 고려했지만 cwd를 직접 제공하지 않아 lsof 필요. `/proc`는 macOS에 없음.

### D2: visibleSessions = live cwds에 매칭되는 세션만
- **Status**: resolved
- **Rationale**: 기존 mtime 기반 idle 필터 대신 프로세스 존재 여부로 가시성 결정. dot 색상(active/idle/resting)은 mtime 기반 유지 — 가시성과 상태 표시는 별개. "live process 없는 세션은 숨김"이 사용자 멘탈 모델과 일치.

### D3: 프로세스 탐지는 refresh() 배경 스레드에서 실행
- **Status**: resolved
- **Rationale**: 기존 `DispatchQueue.global(qos: .utility)` 블록에 통합. 별도 타이머 추가 없음. JSONL 스캔과 동시 실행 가능 (독립적).

### D4: live process 0개 → empty state 표시
- **Status**: resolved
- **Rationale**: 기존 `emptyState` 뷰(`MenuContentView.swift:48-59`)가 `visibleSessions.isEmpty`일 때 자동 표시됨. 추가 UI 불필요.

### D5: stale-while-revalidate — 이전 live cwds 유지하며 갱신
- **Status**: resolved
- **Rationale**: `SessionStore`에 `liveCwds: Set<String>` 프로퍼티 유지. 새 탐지 완료 시 main thread에서 atomic 교체. lsof 실행 중에도 UI는 이전 결과 표시 — 눈에 띄는 깜빡임 없음.

## Constraints
- `~/.claude/projects/**/*.jsonl` 읽기 전용
- CLT 빌드만 허용 (xcodebuild 금지)
- 메뉴바 아이콘 template image 유지

## Requirements

### R0: 실행 중인 claude 프로세스의 cwd만 드롭다운에 표시

#### R0.1: live cwds 수집
- **Given**: 하나 이상의 `claude` 프로세스가 실행 중
- **When**: `refresh()` 배경 스레드 실행
- **Then**: `pgrep -x claude`로 PID 수집 후 각 PID의 lsof cwd를 `Set<String>`으로 반환

#### R0.2: live cwds 없으면 빈 set 반환
- **Given**: 실행 중인 `claude` 프로세스가 없음
- **When**: `refresh()` 배경 스레드 실행
- **Then**: 빈 `Set<String>` 반환, empty state 자동 표시

#### R0.3: visibleSessions = live cwds에 포함된 세션만
- **Given**: `liveCwds`가 갱신됨
- **When**: `visibleSessions` computed property 평가
- **Then**: `session.cwd`가 `liveCwds`에 포함된 세션만 반환

#### R0.4: claude 종료 후 다음 스캔에서 세션 사라짐
- **Given**: cwd `/foo`의 claude 프로세스가 종료됨
- **When**: 3초 이내 다음 `refresh()` 실행
- **Then**: `/foo` cwd를 가진 세션이 드롭다운에서 사라짐

### R1: dot 색상은 mtime 기반 유지

#### R1.1: 기존 active/idle/resting 색상 그대로
- **Given**: 세션이 `visibleSessions`에 포함됨
- **When**: `SessionRow`가 렌더됨
- **Then**: `statusColor` 로직 변경 없음 — mtime 기반 그린/오렌지/그레이 유지

### R2: stale-while-revalidate로 UI 안정성 보장

#### R2.1: 탐지 중 이전 결과 유지
- **Given**: 이전 스캔의 `liveCwds` = `{"/foo"}`
- **When**: 새 lsof 탐지가 실행 중
- **Then**: 탐지 완료 전까지 `visibleSessions`는 이전 `liveCwds` 기준으로 렌더

#### R2.2: 탐지 완료 후 main thread에서 atomic 교체
- **Given**: 새 live cwds 탐지 완료
- **When**: `DispatchQueue.main.async` 블록 실행
- **Then**: `liveCwds` 단번에 교체, `visibleSessions` 재평가

## Tasks

### T1: ProcessDetector 신규 파일 작성 [infra]
- **Fulfills**: R0.1, R0.2
- **Depends on**: (none)
- **Files**: `Sources/Clawde/ProcessDetector.swift` (신규)
- **Note**: `static func liveCwds() -> Set<String>` — `pgrep -x claude` PIDs 수집 후 각 PID에 대해 `lsof -p <pid> | awk 'NR>1 && $4=="cwd"{print $NF}'` 실행, 결과를 Set으로 반환

### T2: SessionStore에 liveCwds 통합 + visibleSessions 교체 [vertical]
- **Fulfills**: R0.3, R0.4, R1.1, R2.1, R2.2
- **Depends on**: T1
- **Files**: `Sources/Clawde/SessionStore.swift`
- **Note**: `@Published var liveCwds: Set<String> = []` 추가. `refresh()` 배경 블록에서 `ProcessDetector.liveCwds()` 호출 후 main thread에서 `self.liveCwds = detected`로 교체. `visibleSessions`를 `sessions.filter { liveCwds.contains($0.cwd) }`로 변경.

## External Dependencies

### Pre-work
(none)

### Post-work
- `./build.sh` 후 앱 재시작
- claude 세션 하나 종료 후 3초 내 드롭다운에서 사라지는지 확인
- 모든 claude 종료 후 empty state 표시 확인

## Known Gaps
- lsof 반환 경로와 JSONL cwd 필드 간 심볼릭 링크 처리 차이 가능성 — macOS에서는 낮은 위험이나 실제 테스트 필요

## Research
- `pgrep -x claude` → 실행 중인 claude CLI PID 반환 (`<5ms`)
- `lsof -p <pid> | awk 'NR>1 && $4=="cwd"{print $NF}'` → cwd 추출 (pid당 ~60ms)
- 2개 프로세스 기준 총 ~120ms — 3초 스캔 주기에 허용 가능
- `SessionStore.refresh()`가 이미 `DispatchQueue.global(qos: .utility)`에서 실행됨 (`SessionStore.swift:43`) — 프로세스 탐지도 여기에 통합 가능
- `SessionInfo.cwd`에 세션 cwd 이미 존재 (`SessionScanner.swift:26`)
- 현재 `visibleSessions`는 mtime 기반 idle 필터 사용 (`SessionStore.swift:32-38`) — 프로세스 존재 기반으로 교체
- mtime 기반 `SessionStatus`(active/idle/resting)는 dot 색상 전용으로 유지 (`MenuContentView.swift:158-163`)
- 빌드: `./build.sh` (CLT only)
