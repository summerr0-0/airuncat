# Spec: omc-gap-analysis

## Meta
- **Created**: 2026-07-08
- **Type**: dev (analysis/backlog 문서 — 이번 산출물은 코드가 아니라 문서)
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-07-08

## Goal
oh-my-claudecode(github.com/Yeachan-Heo/oh-my-claudecode) 소스 **전체**를 훑어,
airuncat이 수정해야 할 부분/추가할 만한 부분을 구체적으로 정리한다.
각 항목은 문서만 보고 나중에 구현 가능한 수준으로: OMC 소스 경로 ↔ airuncat 대상 파일,
동작 설명, 구현 방법, 우선순위를 명시한다.

## Non-goals
- 이번 작업에서 airuncat 코드 수정/구현 (문서만 산출).
- OMC 코드의 복사-이식 그 자체 (TypeScript → Swift 재설계 전제, 라이선스 확인 포함).
- airuncat 기존 로드맵(Phase 15 Hook 레시피 등)의 재기획 — 겹치면 참조만.

## Confirmed Goal
OMC 저장소 전체(HUD, usage, rate-limit-wait, hooks, skills, 오케스트레이션 포함)를 조사해
`specs/omc-gap-analysis/spec.md`에 **개선 백로그 문서**를 만든다.

**Done when**
- OMC 주요 서브시스템별로 "airuncat에 해당 기능이 있나 → 있으면 차이/보완점, 없으면 추가 가치"가 정리됨.
- 각 백로그 항목에: OMC 참조 경로(파일:역할), airuncat 대상 파일, 구체 동작, 구현 스케치, 우선순위(P1~P3)가 있음.
- 문서만 보고 별도 재조사 없이 후속 구현 착수 가능.

## Research

조사 방법: OMC 저장소 전체 트리(6,244파일) 표면 훑기 + 병렬 심층조사 3건
(HUD / 사용량·알림 / 훅·기능). 아래는 airuncat 관점으로 정리한 사실들.

### R-A. 사용량 API 주변 (OMC `src/hud/usage-api.ts`)

airuncat은 이미 `/api/oauth/usage` 호출(UsageAPIClient)을 이식했지만, OMC가 더 갖춘 것:

**A1. OAuth 토큰 리프레시** (airuncat 미보유 — 만료 시 "재인증 필요"만 표시)
- `POST platform.claude.com/v1/oauth/token`, URL-encoded body:
  `grant_type=refresh_token&refresh_token=<rt>&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`
  (client_id는 공개값, env `CLAUDE_CODE_OAUTH_CLIENT_ID`로 재정의 가능. 타임아웃 10s)
- 응답: `{access_token, refresh_token?(없으면 기존 유지), expires_in(초)}` →
  `expiresAt = now + expires_in*1000`
- **Keychain 재기록**: `security add-generic-password -s <service> -a <account> -w <json> -U`
  (-U=update). 기존 JSON의 `claudeAiOauth` 래퍼 구조 보존하며 accessToken/expiresAt/refreshToken만 병합.
  실패는 조용히 무시(best-effort). 서비스명 변형: `Claude Code-credentials-{sha256(CONFIG_DIR)[:8]}`.
- 파일 폴백: `~/.claude/.credentials.json` (atomic write, 0600).

**A2. 캐시/백오프** (airuncat은 단순 60s TTL만)
- 성공: pollInterval(기본 60s) / 네트워크 오류: max(2min, poll) / 기타 오류: 15s
- 429: 지수 백오프 `poll × 2^(count-1)`, 상한 5min. `rateLimitedCount/rateLimitedUntil` 저장.
- **stale 서빙**: 오류·429 중에도 `lastSuccessAt < 15min`이면 이전 데이터에 `stale: true`로 표시
  (UI에 * 배지). 15min 넘으면 폐기.
- 오류 분류: `network | auth | no_credentials | rate_limited`.

**A2-b. rate-limit-wait 데몬 (`src/features/rate-limit-wait/`)** — A2의 폴링 백오프와 별개 기능
- 상태 `~/.omc/rate-limit-daemon.json` + PID/로그 파일. 폴링 사이클: 사용량 API 확인 →
  tmux 팬 스캔으로 rate-limit에 막힌 프롬프트 감지(신뢰도 추적) → 리셋 시
  `tmux send-keys`로 **자동 재개**(사용자 개입 없음).
- airuncat 관점: tmux 의존 + 타 세션 입력 조작(read-only 철학 충돌). disposition은 D6.

**A3. 엔지니어링 패턴**
- atomic write: temp(O_EXCL, 0600) → fsync → rename. airuncat도 유사 패턴 보유(.atomic).
- file-lock(O_CREAT|O_EXCL + PID + stale 30s reap): 단일 프로세스인 airuncat엔 불필요.
- 커스텀 프로바이더(z.ai/MiniMax quota API): airuncat 비대상.

### R-B. HUD / 표시 요소 (OMC `src/hud/*`, 16개 element)

**B1. statusline stdin — airuncat이 안 쓰는 결정적 데이터 소스**
- Claude Code는 statusline 커맨드에 JSON을 stdin으로 파이프:
  `context_window.used_percentage`(네이티브 컨텍스트 %, 0-100), `context_window_size`,
  `total_input_tokens`, `current_usage{input/cache_creation/cache_read}`,
  `rate_limits.five_hour/seven_day{used_percentage, resets_at}`, `model.id/display_name`.
- OMC는 이를 세션별로 `~/.omc/state/hud-stdin-cache.json`에 캐시해 다른 컴포넌트가 재사용.
- 의미: airuncat의 컨텍스트 %(수동 usage 합산)와 사용량(API 폴링)을 **Claude Code가 직접 주는
  네이티브 값**으로 대체/보강 가능. 단, statusline 훅을 설치해야 들어옴(Phase 15와 연결).

**B2. payload 압력 (`payload-estimate.ts`)** — API 요청 32MB 한계 감시 (airuncat 미보유)
- transcript 파일 크기 stat → 뒤에서 64KB 청크로 `compact_boundary` 마커 역스캔
  (`/compact` 시 기록됨) → 활성 payload = size − boundaryOffset (마커 없으면 전체 size).
- 임계: <22MB 정상 / 22–26MB 경고 / ≥26MB 위험.

**B3. 컨텍스트 표시 안정화 (`stdin.ts`)** — 스냅샷 간 ±3% 흔들림이면 이전 값 유지(지터 제거).

**B4. 토큰 신뢰성 휴리스틱 (`token-usage.ts`)** — tail 파싱에서 세션ID가 2개 이상 감지되면
세션 합계 표시 생략(부분 읽기 오표시 방지). airuncat contextTokens에도 적용 가치.

**B5. transcript 파싱 최적화 (`transcript.ts`)** — >4MB면 tail 4MB만(첫 불완전 라인 스킵),
서브에이전트 맵 50–100 상한 + 오래된 완료건 축출, 30min 넘은 agent 자동 완료 처리.
extended thinking 감지: `type:"thinking"` 블록, <30s면 "thinking 중" 표시.

**B6. 표시 임계/포맷** — rate limit 70%=노랑/90%=빨강(airuncat 동일 적용됨),
리셋 카운트다운 `3h42m`/`2d5h` 포맷(동일 적용됨).

### R-C. OMC 표면 훑기 (오케스트레이션 등 나머지)
- 슬래시 커맨드 28종, 스킬 30여 종(autopilot/ralph/team/ultrawork 등 오케스트레이션 다수).
- `src/agents/`(11개 에이전트 정의), `src/mcp/`(자체 MCP 서버), `src/interop/`, `src/installer/`.
- 오케스트레이션 실행계는 airuncat(관제 앱) 성격과 다름 — 이식 비대상.
  단, 그 **상태 파일**(`.omc/state/*`)을 관제 표시할 수는 있으나 사용자가 OMC를 제거했으므로 비대상.

### R-D. 훅/기능 스윕 (OMC `src/hooks/*`, `src/features/*`)

**D1. 훅 설치 메커니즘 (`src/installer/hooks.ts`)** — Phase 15의 핵심 참조
- settings.json `hooks` 키 아래 이벤트별 배열: `{matcher:{paths,tools}, timeout(ms), command}`.
- 훅 스크립트 I/O 계약: stdin으로 `{session_id, transcript_path, cwd, permission_mode,
  hook_event_name, tool, file_path}` JSON → stdout으로 `{continue: bool, systemMessage?: string}`.
- 이벤트 종류: PreSessionStart / PreToolUse / PostToolUse / SessionEnd / Stop /
  SubagentStart / SubagentStop / PreCompact.
- 레시피 구현 순서: 템플릿 스크립트 보관 → `~/.claude/hooks/<name>.mjs` 복사 →
  settings.json 원자 갱신 → 비활성화 시 항목 제거.

**D2. 레시피 후보 훅** (standalone 가능성 기준)
- `session-end`: SessionEnd에서 세션 메트릭(에이전트 수·모드·지속시간)을
  `.omc/state/sessions/<id>/session-metrics.json`에 기록. 레시피화 가능(HIGH).
- `subagent-tracker`: SubagentStart/Stop에서 에이전트별 도구·토큰·소요시간 추적
  (`subagent-tracking-state.json`). 레시피화 가능(HIGH).
- `rules-injector`: PreToolUse에서 `.claude/rules/*.md` + `~/.claude/rules/*`를 경로 글롭
  매칭해 주입, 콘텐츠 해시로 중복 방지. 레시피화 가능(HIGH) — airuncat rules 스캐너와 시너지.
- `pre-compact`: PreCompact에서 모드 상태/TODO 체크포인트 저장. 레시피화 가능(MED).
- `preemptive-compaction`: PostToolUse에서 컨텍스트 ~80% 경고(chars/4 추정, 경고 상한 5회·
  쿨다운 30min·500ms 디바운스). 실시간 훅 전용 — 레시피는 가능하나 airuncat 표시는 JSONL로 대체 가능.
- `codebase-map`: PreSessionStart에서 파일트리(≤200파일·4뎁스) 마크다운 주입. 완전 standalone.
- 낮은 가치: comment-checker, todo-continuation, background-notification, empty-message-sanitizer,
  auto-slash-command(키워드 트리거).

**D3. 관제 표시(훅 설치 불필요) 후보** — 상태 파일만 읽으면 됨
- `~/.claude/tasks/<sessionId>/*.json`: Claude Code 네이티브 태스크 → 세션별 "미완 태스크 N" 표시.
- session-friction-report 로직: JSONL에서 idle 갭(>45min)·오류율(>20%)·컨텍스트 % → 세션 건강 배지.
- session-history-search: JSONL 전문 검색(시간 필터) — airuncat 검색 패널 아이디어.
- `.omc/state/*`(boulder/mode/subagent): **사용자가 OMC를 제거해 현재 데이터 없음** —
  airuncat 자체 훅 레시피가 쓰는 상태 경로로 대체 설계 필요.

**D4. 카피할 아키텍처 패턴**
- 무상태 훅 + 구조화 상태 파일(훅=순수함수, 상태=JSON) / 세션 스코프 디렉토리
- rescan+merge(자동 감지 필드는 덮어쓰고 사용자 필드는 보존) / 콘텐츠 해시 중복 제거
- 고빈도 이벤트 500ms 디바운스

## Decisions

### D1: 4개 영역 모두 백로그 포함, 우선순위는 의존성·효용 기준으로 배정
- **Status**: resolved
- **Rationale**: 사용자가 4개 영역(사용량 안정화 / statusline stdin / 훅 레시피 / 세션 건강)을
  모두 선택하며 우선순위 판단을 위임("무슨 말인지 모르겠다"). → 배정 기준:
  이미 배포된 기능의 약점 보완이 최우선(P1=사용량 안정화), 새 데이터 소스는 그 다음
  (P2=statusline), 신규 기능군은 P2~P3. 각 항목에 "왜 이 우선순위인지" 명기.
  또한 사용자가 배경지식 없이 읽도록 각 항목에 쉬운 설명(왜 필요한가) 포함.

### D2: 토큰 리프레시의 Keychain 재기록 허용 (OMC 방식 + 레이스 완화)
- **Status**: resolved (L2-reviewer fix 반영)
- **Rationale**: 사용자 확인. `security add-generic-password -U`로 병합 저장, 실패는
  best-effort(조용히 무시). 메모리만 유지(대안)는 Claude Code와 토큰 불일치 가능성,
  리프레시 포기(대안)는 만료 때마다 수동 개입이라 기각.
- **트리거 정책**: **만료 후에만**(lazy) 리프레시 — `expiresAt <= now`일 때만 시도.
  선제(proactive) 리프레시는 Claude Code와의 동시 리프레시 확률을 높여 기각.
- **동시 리프레시 레이스 완화** (관제 앱이 주 도구의 인증을 깨는 blast-radius 역전 방지):
  1. 리프레시 직전 Keychain **재독** — 그 사이 Claude Code가 이미 갱신했으면
     (expiresAt이 미래로 바뀜) 새 토큰을 그대로 쓰고 리프레시 중단.
  2. 재기록 직전에도 재독-비교(compare) — 저장된 refreshToken이 내가 읽었던 것과
     다르면 내 결과를 버리고 Keychain 값을 채택(내 쓰기 포기).
  3. 그래도 refresh-token rotation으로 무효화되면 결과는 지금과 동일한 "재인증 필요"
     표시로 강등 — 즉 최악의 경우가 현재 동작과 같음(수용 가능한 위험으로 명시).

### D3: OMC 상태 표시는 자체 경로로 대체 설계
- **Status**: resolved
- **Rationale**: 사용자 확인. `.omc/state/*`는 OMC 제거로 데이터가 없음 →
  airuncat 훅 레시피가 `~/.airuncat/hook-state/` 자체 경로에 상태를 쓰도록 설계해
  같은 가치(세션 메트릭·에이전트 추적)를 OMC 의존 없이 제공. `.omc` 병행 지원은 복잡도로 기각.

### D4: 백로그 항목 포맷 고정
- **Status**: assumed (L0에서 정의, L2-reviewer fix로 검증 방법 추가)
- **Rationale**: 각 항목 = 쉬운 설명(왜) / OMC 참조(파일:로직) / airuncat 대상 파일 /
  구체 동작 / 구현 스케치 / **검증 방법**(됐다고 판단하는 기준) / 우선순위(P1~P3)·난이도(S/M/L).
  문서만으로 착수·완료판정 가능 조건.

### D5: 오케스트레이션 실행계(autopilot/ralph/team/agents/MCP서버) 제외
- **Status**: resolved (L0 non-goal + 리서치 확인)
- **Rationale**: airuncat은 관제 앱. OMC 실행계는 성격이 다르고 사용자가 OMC를 제거함.
  키워드 트리거·모드 레지스트리·**installer의 자동업데이트/설치 플로우**(hooks.ts의
  settings.json 기록 형식만 참조하고 나머지는 OMC 배포 메커니즘이라 비대상)도 동일 사유로 제외.

### D6: rate-limit-wait — 자동 재개는 제외, "리셋 알림"만 백로그 포함
- **Status**: resolved (L2-reviewer fix — 미처리 영역 disposition)
- **Rationale**: OMC의 rate-limit-wait(`src/features/rate-limit-wait/`)는 tmux 팬을 스캔해
  rate-limit로 막힌 세션을 감지하고 리셋 시 `tmux send-keys`로 **자동 재개**하는 데몬.
  tmux 의존 + 세션 입력 조작은 airuncat의 read-only 철학과 충돌 → 자동 재개는 기각.
  다만 같은 데이터(사용량 API의 resets_at)로 **"한도 도달 → 리셋됨" 알림**은 airuncat의
  기존 NotificationManager로 자연스럽게 제공 가능 → 백로그 포함(세션 건강 영역).

## Constraints
- C1: 세션 JSONL·`~/.gemini/tmp`는 읽기 전용(기존 규칙 유지).
- C2: Keychain 재기록은 `claudeAiOauth` 래퍼 구조를 보존한 병합만, 실패는 조용히(best-effort).
- C3: CLT 빌드만(swift build/build.sh). TypeScript 코드 복사가 아니라 Swift 재설계.
- C4: 훅 레시피는 무상태 스크립트 + 구조화 상태 파일 패턴(D4 패턴 카피), 상태는 자체 경로.
- C5: statusline 설치는 사용자의 기존 statusline 설정을 덮어쓰지 않음(있으면 감지·안내).

## Known Gaps
- statusline stdin의 정확한 JSON 필드는 Claude Code 버전에 따라 다를 수 있음 —
  구현 시 실제 stdin 샘플 캡처로 검증 필요.
- OMC 라이선스 확인 필요(설계 참조는 문제없으나 코드 직역 시).
- **Keychain ACL 불확실**: `Claude Code-credentials` 항목은 Claude Code가 생성했고
  airuncat은 자체 서명 앱. 읽기는 현재 동작 확인됐으나, `security add-generic-password -U`
  **쓰기**가 프롬프트 없이 되는지/partition-list 제약이 있는지 미검증 — 구현 첫 단계에서
  실검증 필요. 실패 시 D2의 best-effort 규칙대로 조용히 강등(메모리만 사용).

## Requirements

각 항목 = 백로그 1건. 포맷(D4): 쉬운 설명 / OMC 참조 / airuncat 대상 / 우선순위·난이도 /
sub-requirement(동작 GWT + 검증 방법). P1=바로 할 것, P2=다음, P3=여유 있을 때.
난이도 S=반나절, M=1~2일, L=3일+.

---

### R1: 토큰 자동 리프레시 — P1 · M (영역: 사용량 안정화)
**쉬운 설명**: 지금은 OAuth 토큰이 만료되면 헤더에 "재인증 필요"가 뜨고 사용자가 Claude Code를
한 번 써줘야 풀린다. airuncat이 스스로 토큰을 갱신하면 이 상태가 사라진다.
**OMC 참조**: `src/hud/usage-api.ts` — refresh flow (R-A A1).
**대상**: `UsageAPIClient.swift` (refresh 로직 추가), 신규 없음.
**구현 스케치**:
1. `readCredentials()`가 `refreshToken`도 파싱.
2. `expiresAt <= now`일 때만(D2 lazy): Keychain 재독 → 여전히 만료면
   `POST platform.claude.com/v1/oauth/token` (URL-encoded:
   `grant_type=refresh_token&refresh_token=<rt>&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`, 10s 타임아웃).
3. 응답 `{access_token, refresh_token?, expires_in}` → `expiresAt = now + expires_in*1000`.
4. 재기록 전 Keychain 재독-비교(D2): refreshToken 불일치 시 내 결과 폐기.
   일치 시 `claudeAiOauth` 래퍼 보존 병합 후 `security add-generic-password -s "Claude Code-credentials" -a <계정> -w <json> -U`.
5. 쓰기 실패는 조용히 — 메모리 토큰으로 이번 fetch만 진행(C2).

#### R1.1: 만료 토큰 자동 갱신
- **Given**: Keychain 토큰 `expiresAt`이 과거
- **When**: UsageStore.refresh가 fetch 시도
- **Then**: 리프레시 후 새 토큰으로 사용량 API 호출 성공, 헤더에 %가 표시된다("재인증 필요" 없음)
#### R1.2: 동시 갱신 레이스 방어
- **Given**: fetch 사이에 Claude Code가 먼저 토큰을 갱신함
- **When**: airuncat이 리프레시 직전 Keychain 재독
- **Then**: 새 토큰(미래 expiresAt)을 발견하고 자체 리프레시를 중단, 그 토큰을 사용한다
#### R1.3: 갱신 실패 강등
- **Given**: 리프레시 요청이 401/network 실패
- **When**: fetch 완료
- **Then**: 크래시 없이 `.expired`/`.network` 에러로 강등, 헤더에 기존 힌트 표시
**검증 방법**: (1) Keychain ACL 쓰기 실검증(Known Gap — 우선 확인), (2) expiresAt을 과거로
조작한 사본 시나리오 또는 실제 만료 시점 대기 후 헤더가 %로 복귀하는지, (3) build.sh 라이브.

---

### R2: 429 백오프 + stale 캐시 서빙 — P1 · S (영역: 사용량 안정화)
**쉬운 설명**: 사용량 API가 일시 오류/429를 반환할 때 지금은 게이지가 그냥 에러로 바뀐다.
직전 성공 데이터를 15분까지 "약간 오래된 값(*)"으로 계속 보여주고, 재시도는 점점 뜸하게.
**OMC 참조**: `usage-api.ts` 캐시 전략 (R-A A2).
**대상**: `UsageStore.swift`.
**구현 스케치**: `lastSuccessAt` 보존, 오류 시 TTL 차등(네트워크 2min/기타 15s),
429 시 `retryCount` 증가 → `60s × 2^(count-1)` 상한 5min. snapshot에 `stale: Bool` 추가,
`lastSuccessAt < 15min`이면 stale=true로 유지 표시(게이지 옆 `*`), 넘으면 폐기.
#### R2.1: 일시 오류 중 stale 표시
- **Given**: 직전 성공이 5분 전, 이번 fetch가 network 실패
- **When**: 헤더 렌더
- **Then**: 직전 %가 `*` 배지와 함께 그대로 표시된다(에러 문구로 바뀌지 않음)
#### R2.2: 429 지수 백오프
- **Given**: 연속 429 3회
- **When**: 다음 refresh tick
- **Then**: 4×60s=240s가 지나기 전엔 API를 호출하지 않는다(로그/카운터로 확인)
**검증 방법**: URLProtocol 목 또는 네트워크 차단(기내모드)으로 stale 배지 확인; 백오프는
디버그 로그 타임스탬프 간격으로 확인.

---

### R3: statusline 설치 + stdin 캐시 — P2 · M (영역: statusline stdin 통합)
**쉬운 설명**: Claude Code는 상태줄(statusline) 스크립트에 컨텍스트 %·rate limit·모델명을
JSON으로 직접 준다. airuncat이 작은 스크립트를 설치해 이 JSON을 파일로 받아두면,
지금처럼 토큰을 직접 합산해 추정하는 것보다 정확한 값을 공짜로 얻는다.
**OMC 참조**: `src/hud/stdin.ts`(파싱), `~/.omc/state/hud-stdin-cache.json`(캐시 패턴).
**대상**: 신규 `StatuslineRecipe.swift`(설치/제거) + 스크립트 템플릿, `HarnessSetup.swift` 패턴 참조.
**구현 스케치**:
1. 스크립트(예: `~/.airuncat/statusline.sh`): stdin JSON을
   `~/.airuncat/hook-state/statusline/<session_id>.json`에 원자 기록 후, 기존 출력(있으면) 유지.
2. `~/.claude/settings.json`의 `statusLine` 키에 등록 — **기존 statusline이 있으면 덮지 않고
   감지·안내만**(C5). 없을 때만 설치 제안.
3. 필드: `context_window.used_percentage`, `rate_limits.five_hour/seven_day`, `model.display_name`.
   실제 stdin 샘플 캡처로 필드 검증(Known Gap).
#### R3.1: stdin 캐시 생성
- **Given**: 레시피 설치 후 Claude Code 세션이 활동
- **When**: statusline이 갱신될 때
- **Then**: `hook-state/statusline/<session>.json`에 최신 JSON이 쌓인다
#### R3.2: 기존 statusline 보호
- **Given**: settings.json에 이미 statusLine 설정 존재
- **When**: 레시피 설치 시도
- **Then**: 덮어쓰지 않고 "기존 설정 있음" 안내만 표시
**검증 방법**: 설치 → 이 세션에서 몇 턴 대화 → 캐시 파일 내용 눈으로 확인(필드 존재).

---

### R4: 네이티브 컨텍스트 %를 세션 행에 사용 — P2 · S (영역: statusline stdin 통합)
**쉬운 설명**: 세션 행의 "82k/200k" 게이지를 Claude Code가 계산해준 네이티브 %로 업그레이드.
stdin 캐시가 있으면 그걸 쓰고, 없으면 지금 방식(토큰 합산) 유지.
**OMC 참조**: `elements/context.ts` (±3% 지터 안정화 포함, R-B B3).
**대상**: `SessionScanner.swift`(또는 행 렌더 시 조회), `MenuContentView.swift` 행 확장.
**의존**: R3.
#### R4.1: stdin 우선, 합산 폴백
- **Given**: 세션의 stdin 캐시에 used_percentage=41 존재
- **When**: 행 확장 게이지 렌더
- **Then**: 41%(네이티브)가 표시되고, 캐시 없는 세션은 기존 합산 값이 표시된다
**검증 방법**: R3 설치된 세션 vs 미설치 세션 나란히 확인.

---

### R5: 훅 레시피 설치 인프라 — P2 · M (영역: Phase 15 훅 레시피)
**쉬운 설명**: "이 훅 켜기" 토글을 누르면 airuncat이 스크립트를 복사하고 settings.json에
등록해주는 공통 장치. Phase 15의 토대.
**OMC 참조**: `src/installer/hooks.ts` — settings.json hooks 형식(R-D D1):
이벤트별 배열 `{matcher:{paths,tools}, timeout, command}`, 스크립트 I/O 계약
(stdin: session_id/transcript_path/cwd/hook_event_name..., stdout: `{continue, systemMessage?}`).
**대상**: 신규 `HookRecipeManager.swift`(설치/제거/상태), 템플릿은 앱 번들 or `~/.airuncat/hook-templates/`.
**구현 스케치**: 템플릿 → `~/.claude/hooks/<name>.sh|mjs` 복사 → settings.json 원자 갱신
(기존 hooks 배열 보존, 항목 추가/제거만). 상태 출력은 `~/.airuncat/hook-state/`(D3).
#### R5.1: 레시피 설치/제거 왕복
- **Given**: 미설치 레시피
- **When**: 설치 토글 → 해제 토글
- **Then**: settings.json에 항목이 추가됐다가 원형 그대로 복원된다(다른 훅 항목 불변)
**검증 방법**: 설치 전후 settings.json diff가 해당 항목만 다름을 확인.

---

### R6: 레시피 3종 — P2~P3 · 각 M (영역: Phase 15 훅 레시피)
**쉬운 설명**: OMC에서 검증된 훅 3개를 airuncat 레시피로 제공.
**의존**: R5. 상태는 모두 `~/.airuncat/hook-state/`(D3).
- **R6a 세션 텔레메트리** (SessionEnd): 세션 종료 시 지속시간·도구 수 등 메트릭 JSON 기록.
  OMC `src/hooks/session-end/` 참조. → Stats 탭 데이터 소스로도 활용 가능.
- **R6b 서브에이전트 트래커** (SubagentStart/Stop): 에이전트별 시작/종료·소요시간 기록.
  OMC `src/hooks/subagent-tracker/` 참조. → 세션 행에 "에이전트 N개 동작 중" 뱃지.
- **R6c rules 상태 강화**: OMC `rules-injector`는 주입까지 하지만, airuncat은 이미 rules
  스캐너가 있으므로 **주입 훅 설치(레시피)** + 콘텐츠 해시 중복 방지 로직만 이식.
#### R6.1: 텔레메트리 기록
- **Given**: R6a 설치 후 세션 하나 종료
- **When**: SessionEnd 훅 실행
- **Then**: `hook-state/sessions/<id>/metrics.json`이 생성되고 duration이 실제와 일치
**검증 방법**: 짧은 세션 열고 닫아 파일 생성·내용 확인. R6b는 서브에이전트 스폰 세션으로 확인.

---

### R7: payload 압력 게이지 — P2 · S (영역: 세션 건강)
**쉬운 설명**: Claude API 요청엔 32MB 상한이 있는데 지금은 전혀 안 보인다. transcript 크기로
근사해 "곧 한계" 경고를 세션 행에 표시.
**OMC 참조**: `src/hud/payload-estimate.ts` (R-B B2).
**대상**: `SessionScanner.swift` + 행 확장 UI.
**구현 스케치**: 파일 size stat → 뒤에서 64KB 청크로 `compact_boundary` 역스캔 →
활성 payload = size − boundary. 임계 22MB 경고/26MB 위험(색만, 상시 텍스트 없음).
#### R7.1: 압력 표시
- **Given**: 활성 payload 23MB인 세션
- **When**: 행 확장
- **Then**: 노란 경고 게이지("~23MB/32MB")가 표시된다; <22MB 세션엔 표시 없음
**검증 방법**: 큰 세션 JSONL(수십 MB)로 확인, /compact 이후 boundary 반영 확인.

---

### R8: rate-limit 리셋 알림 — P2 · S (영역: 세션 건강, D6)
**쉬운 설명**: 사용량이 90%를 넘으면 알림, `resets_at`이 지나 다시 여유가 생기면 "리셋됨" 알림.
자동으로 뭔가 실행하진 않는다(D6).
**대상**: `UsageStore.swift` + `NotificationManager.swift`.
#### R8.1: 임계/리셋 알림
- **Given**: 5h 창이 88%→92%로 상승
- **When**: refresh tick
- **Then**: 로컬 알림 1회 발송(중복 없음); 이후 resets_at 경과 시 "리셋됨" 알림 1회
**검증 방법**: 임계값을 임시로 낮춰(예: 10%) 실사용 중 알림 수신 확인.

---

### R9: 표시 품질 소품 — P3 · S (영역: 세션 건강)
**쉬운 설명**: 자잘한 정확도 개선 묶음.
- **R9a 토큰 신뢰성**: tail 파싱에서 세션ID 2개 이상 감지되면 contextTokens 표시 생략
  (부분 읽기 오표시 방지, OMC `token-usage.ts`).
- **R9b 컨텍스트 지터 안정화**: 새 값이 직전과 ±3% 이내면 직전 값 유지(OMC `stdin.ts`).
- **R9c thinking 표시**: tail에 `type:"thinking"` 블록이 30초 내면 행에 "생각 중" 힌트
  (OMC `transcript.ts`).
#### R9.1: (대표) 신뢰성 가드
- **Given**: 4MB 초과 파일의 tail에 두 세션ID 혼재
- **When**: 파싱
- **Then**: contextTokens=nil로 표시 생략(틀린 숫자 미표시)
**검증 방법**: 해당 조건 세션 확보 또는 单위 시나리오로 확인; R9b/c는 라이브 관찰.

---

### R10: 세션 friction 배지 — P3 · M (영역: 세션 건강)
**쉬운 설명**: 세션이 "매끄러웠는지"를 배지로. 45분+ 방치 갭, 오류율 20%+ 등이면 경고색.
**OMC 참조**: `src/features/session-friction-report/` 임계값 (R-D D3).
**대상**: `SessionScanner.swift` + 행/확장 UI.
**검증 방법**: 오류 많은 세션·방치 세션에서 배지 발현 확인.
#### R10.1: friction 감지
- **Given**: 오류율 25%인 세션
- **When**: 행 렌더
- **Then**: 경고 배지가 표시되고 툴팁에 사유(오류율)가 보인다

## Tasks

파일 겹침 기준으로 직렬화, 나머지는 병렬 가능. 각 태스크는 워크플로우 8단계
(스펙은 본 문서로 갈음 가능, 개발→리뷰→문서→커밋)를 따른다.

### T1: 사용량 안정화 (R1 토큰 리프레시 + R2 백오프/stale) [P1] — **완료 (7b61c4a)**
- **Fulfills**: R1, R2
- **Depends on**: (none) — Pre-work 1(Keychain ACL 실검증) **통과**(동일 내용 재기록 무손상)
- 같은 파일(UsageAPIClient/UsageStore)이라 한 태스크로 묶음.
- 잔여 검증: 실제 토큰 만료 시점(≤5h 내 자연 발생)에 헤더가 %로 자동 복귀하는지 관찰.

### T2: 훅 레시피 설치 인프라 (R5) [P2] — **완료**
- **Fulfills**: R5
- **Depends on**: (none) — T1과 병렬 가능(다른 파일)
- settings.json 원자 갱신 유틸은 T3도 재사용.
- 구현 노트: **실제 settings.json hooks 형식은 OMC 리포트와 다름** —
  `{matcher: "도구정규식"?, hooks: [{type:"command", command, timeout?}]}` (로컬 실물 기준).
  파일럿 레시피 session-telemetry(R6a 최소형) 포함. `--hook-recipe` 디버그 CLI로
  R5.1 왕복 검증 통과(의미상 원형 복원). 알려진 한계: settings.json read-modify-write는
  무락(無lock) — Claude Code 동시 갱신과 이론상 레이스(Claude Code 자체 동작과 동일 수준).

### T3: statusline 레시피 (R3) [P2]
- **Fulfills**: R3
- **Depends on**: T2 (settings.json 갱신 유틸 공유) + Pre-work 2(stdin 샘플 캡처)

### T4: 네이티브 컨텍스트 % (R4) [P2]
- **Fulfills**: R4
- **Depends on**: T3

### T5: 레시피 3종 (R6a/b/c) [P2~P3] — **완료**
- **Fulfills**: R6
- **Depends on**: T2 — T3/T4와 병렬 가능
- 구현 노트: R6a 완성형(duration·메시지/도구 수 — 실측 검증), R6b는 SubagentStop만
  (SubagentStart 이벤트 실재 미확인 → raw JSON append로 스키마 드리프트 대비),
  R6c는 paths 글롭 매칭 + 세션별 해시 캐시(2회차 무주입 검증). 함정 발견·수정:
  `python3 - <<heredoc`은 heredoc이 stdin을 점유해 훅 JSON을 못 읽음 → `INPUT=$(cat)`
  후 env(HOOK_INPUT) 전달 패턴으로 확립. 레시피 UI는 Phase 15에서(현재 --hook-recipe CLI).

### T6: 세션 표시 개선 1 (R7 payload + R9 소품) [P2~P3] — **완료**
- **Fulfills**: R7, R9a, R9c (R9b 지터 안정화는 stdin 데이터 의존 → **T4로 이관**)
- **Depends on**: (none) — SessionScanner/행 UI 묶음, T1·T2와 병렬 가능
- 구현 노트: compact_boundary 마커 실물 확인(`"subtype":"compact_boundary"` system 이벤트).
  payload 스캔은 22MB↑ 파일에서만(성능). R9a는 tail의 `sessionId` 필드 distinct 카운트.

### T7: rate-limit 리셋 알림 (R8) [P2] — **완료**
- **Fulfills**: R8
- **Depends on**: T1 (UsageStore snapshot의 resets_at 사용)
- 구현 노트: 임계 교차 기반(상향 90% 경고 / 하향 80% "여유 회복" — 히스테리시스로 플래핑 방지).
  resets_at 시각 추적 없이 리셋 자동 감지. 잔여 검증: 실사용에서 90% 도달 시 알림 관찰.

### T8: friction 배지 (R10) [P3] — **완료**
- **Fulfills**: R10
- **Depends on**: T6 (같은 파일: SessionScanner + 행 UI)
- 구현 노트: tail 표본 기준 — 도구 오류율 >20%(표본 ≥5) / 방치 갭 >45min.
  갭은 **끝이 최근 2h 이내인 것만** 배지(재개 세션의 자연 공백 오탐 방지 — OMC 원안에서 보정).
  행 상태 라벨 옆 주황 삼각형 + 툴팁 사유.

```
T1 (P1) ──→ T7
T2 ──→ T3 ──→ T4
  └──→ T5
T6 ──→ T8
(T1 · T2 · T6 는 서로 병렬 가능)
```

## External Dependencies

### Pre-work
1. **Keychain ACL 쓰기 실검증** (T1 선행): 터미널에서 `security add-generic-password -U`로
   Claude Code 항목 갱신이 프롬프트 없이 되는지 확인. 실패 시 R1은 "메모리만" 모드로 축소.
2. **statusline stdin 샘플 캡처** (T3 선행): 임시 statusline 스크립트로 실제 JSON 필드 확인
   (버전에 따라 필드 상이 가능 — Known Gap).
3. OMC 라이선스 확인(코드 직역 시에만 해당 — 설계 참조는 무관).

### Post-work
- 각 태스크마다 build.sh 라이브 검증 + CLAUDE.md 갱신 + 커밋(워크플로우 4~7단계).
- 전체 완료 후 docs/ui-redesign.md 또는 로드맵에 반영.

### R-E. airuncat 현재 상태 (이번 세션 기준)
- 사용량: `UsageAPIClient`(Keychain 토큰 → oauth/usage, 60s TTL) + 헤더 게이지(실제 %·리셋 카운트다운).
  리프레시 없음, 백오프 없음, stale 배지 없음.
- per-session: contextTokens(최신 usage raw 합산) / durationSeconds / 행 확장 UI.
- Skills: 글로벌(~/.airuncat)+프로젝트(.claude/{commands,skills} 멀티)+네이티브(~/.claude/skills) 접이식 섹션.
- Stats: 히트맵/스킬바. Harness Score(정적 5축). Phase 15(훅 레시피)는 기획 문서만(`docs/specs/phase-15-hook-recipes.md`).
