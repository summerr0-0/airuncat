# Spec: preemptive-compaction

## Meta
- **Created**: 2026-07-14
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-07-14

## Goal
세션 컨텍스트가 임계(기본 80%)를 넘으면 세션에 "정리(/compact) 권장" 넛지를 주입하는
글로벌 훅 레시피를 airuncat이 설치/제거할 수 있게 한다. Claude Code의 네이티브 자동
compact(≈한계 근처)보다 **일찍** 사용자가 정할 시점에 유도한다. 사용자 질문 "세션 80% 넘으면 알아서 정리하는 기능"의 안전한 구현(B안).
**결과는 항상 Claude/사용자 재량 — 자동 실행이 아니라 넛지(유도)다.**

## Non-goals
- **완전 자동 `/compact` 실행/주입** — airuncat은 세션 읽기 전용. 남의 세션에 키 입력/명령을
  주입하지 않는다(rate-limit-wait 자동재개를 거부한 것과 동일 사유). 넛지(권장 메시지)까지만.
- 프로젝트별 임계 설정 UI(초기엔 고정 80% 또는 상수). 세부 조절은 후속.
- airuncat 앱 자체의 알림(A안) — 이 스펙은 훅 레시피(B)만. A는 별도.
- Gemini 세션.

## Confirmed Goal
`HookRecipeManager`에 4번째 글로벌 레시피 `preemptive-compaction` 추가:
- PostToolUse 훅으로 매 도구 실행 후 세션 컨텍스트 사용률을 확인.
- 임계(기본 80%) 초과 시 stdout으로 "컨텍스트 N% — /compact 권장" 넛지 출력.
- 반복 스팸 방지: 세션당 쿨다운/횟수 제한 상태를 `~/.airuncat/hook-state/`에 기록.
- Global 탭에서 토글 설치/제거(기존 레시피 3종과 동일 UX + 스크립트 미리보기).

**Done when**
- Global 탭에 레시피가 뜨고 토글로 settings.json에 설치/제거된다(왕복 무손상).
- 설치 후 컨텍스트가 임계를 넘는 세션에서 넛지가 1회 출력되고, 쿨다운 내 재출력 안 된다.
- 임계 미만이면 아무것도 출력하지 않는다(조용).
- build·실행 그린.

## Research

**훅 레시피 모델 (`HookRecipeManager`, `ProjectHookRecipe`와 별개 — 글로벌 계열)**
- `HookRecipe`(id/name/description/event/matcher/timeout/script). script는
  `~/.claude/hooks/airuncat-<id>.sh`로 설치, settings.json에 원자 병합. 제거 시 원형 복원.
- `recipes: [HookRecipe]` 정적 배열에 **4번째로 추가**하면 Global 탭에 자동 노출
  (`GlobalRecipesView`가 `HookRecipeManager.recipes`를 순회 — UI 코드 무변경).
- 훅 스크립트 관례: `INPUT=$(cat); HOOK_INPUT="$INPUT" /usr/bin/python3 - <<'PY' ...
  json.loads(os.environ["HOOK_INPUT"]) ... print(json.dumps({...}))` (rules-injector와 동일).
- 상태 출력 경로: `PathConstants.hookState` = `~/.airuncat/hook-state/`.

**컨텍스트 사용률 소스 (핵심)**
- **PostToolUse stdin에 컨텍스트가 오는지 미확인** — 훅은 세션 시작 시 스냅샷되어 실행 중인
  세션에 probe를 걸 수 없음(직접 확인 시도 실패). → stdin 필드에 의존하지 않게 설계.
- **1순위: statusline 캐시** `~/.airuncat/hook-state/statusline/<session_id>.json` —
  Claude Code 네이티브 `context_window.used_percentage`(정확) + `context_window_size`
  (실측: used_percentage=88, size=1_000_000). statusline 레시피가 설치돼 있으면 사용.
- **2순위(폴백): transcript 추정** — 훅 stdin의 `transcript_path`에서 최신 assistant
  `usage`(input+cache_read+cache_creation) = 컨텍스트 점유(실측 921,855). 창 크기는
  점유>200k면 1M, 아니면 200k로 추정 → % 산출. statusline 미설치 세션도 동작.

**넛지 출력 스키마**
- PostToolUse는 **차단 불가**. **`hookSpecificOutput.additionalContext`만 Claude에 주입**되고,
  plain stdout/`systemMessage`는 Claude에 안 닿음(디버그 로그·사용자용). → 반드시 additionalContext
  JSON으로 출력해야 넛지가 효력(D4). claude-code-guide 확인 완료.

**스팸 방지(OMC preemptive-compaction 참고)**
- 세션당 경고 상한(예: 3회)·쿨다운(예: 20분) 상태를
  `~/.airuncat/hook-state/sessions/<sid>/compaction.json`에 기록. 매 PostToolUse는 저렴해야
  하므로 python 1패스, 임계 미만이면 즉시 종료.

**신뢰/철학**
- 넛지만, 자동 `/compact` 실행/주입 없음(non-goal). Claude Code 네이티브 auto-compact와
  공존(더 이른 임계로 사용자 개입 기회 제공).

## Decisions

### D1: 컨텍스트 소스 = statusline 캐시 우선, transcript 폴백
- **Status**: resolved
- **Rationale**: statusline 캐시가 있으면 네이티브 정확값(used_percentage) 사용, 없으면
  transcript 최신 usage로 추정(점유>200k→1M, 아니면 200k 창). 모든 세션 동작 + 정확도 최선.
  statusline-only(대안)는 둘 다 켜야 해 기각, transcript-only는 창 크기 추론 오차라 차선.

### D2: 임계 80% · 쿨다운 20분 · 세션당 최대 3회
- **Status**: resolved
- **Rationale**: 사용자 요청("80% 넘으면")에 정합. Claude 네이티브 auto-compact(≈한계)보다
  일찍. 20분/3회로 스팸 억제(OMC preemptive-compaction 준거). 상태는
  `hook-state/sessions/<sid>/compaction.json`(lastNudgeAt, count).

### D3: 넛지 = 정보+권장(중간 강도)
- **Status**: resolved
- **Rationale**: "컨텍스트 N% — 적절한 지점에 /compact를 권장합니다" 수준. 강한 지시(대안)는
  Claude가 맥락과 무관히 즉시 정리해 작업 흐름을 끊을 수 있어 기각. 조용한 알림은 행동 유도가
  약해 기각. 판단은 Claude/사용자에게.

### D4: 넛지 출력 = hookSpecificOutput.additionalContext (JSON, bare print 금지)
- **Status**: resolved (claude-code-guide 확인)
- **Rationale**: PostToolUse에서 **additionalContext만 Claude 컨텍스트에 주입**된다(넛지가 실제
  닿음). 반면 bare `print()`/plain stdout은 디버그 로그로만 가고 보이지 않음. 스크립트는 반드시
  `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}` 형태로 출력.
  systemMessage(사용자용)은 부차. → verify-first 소진.

### D5: 4번째 글로벌 레시피로 추가(신규 UI 없음)
- **Status**: resolved (브라운필드 자동 해결)
- **Rationale**: `HookRecipeManager.recipes`에 추가 → `GlobalRecipesView`가 자동 렌더.
  설치/제거/미리보기/원자 병합은 기존 경로 재사용. 신규 쓰기 로직 없음.

## Constraints
- C1: 세션 JSONL·transcript는 읽기 전용. 자동 명령 주입 없음(넛지 stdout만).
- C2: 매 PostToolUse 실행은 저렴해야 함 — 임계 미만이면 python 1패스 후 즉시 종료.
- C3: settings.json은 기존 원자 병합(`SettingsFileIO`/HookRecipeManager) 경로만, 타 훅 불변.
- C4: CLT 빌드만. hook-state 경로는 `~/.airuncat/hook-state/`.

## Known Gaps
- PostToolUse stdin의 컨텍스트 필드 유무 미확인 → statusline 캐시/transcript로 우회(D1).
- (해소) 넛지 스키마 확정: additionalContext(D4).
- 주의: PostToolUse stdin의 `tool_output_tokens`는 **도구별**이지 세션 누적 컨텍스트가 아님 —
  컨텍스트 %로 오인 금지(설계는 stdin 컨텍스트 필드 미사용이라 안전).

## Requirements

### R1: 레시피 등록·설치 (D5)
#### R1.1: Global 탭에 노출
- **Given**: `HookRecipeManager.recipes`에 preemptive-compaction 추가됨
- **When**: Global 탭을 연다
- **Then**: "선제 정리 알림" 행이 토글·스크립트 미리보기와 함께 보인다(기존 3종과 동일 UX)
#### R1.2: 설치/제거 왕복
- **Given**: 미설치 상태
- **When**: 토글 ON → OFF
- **Then**: `~/.claude/settings.json` PostToolUse에 airuncat-preemptive-compaction 항목이
  추가됐다가 원형 복원되고, 스크립트 파일이 생성·삭제된다(타 훅·키 불변)

### R2: 컨텍스트 사용률 판정 (D1)
#### R2.1: statusline 캐시 우선
- **Given**: `~/.airuncat/hook-state/statusline/<session_id>.json`에 used_percentage=82 존재
- **When**: 훅이 실행됨
- **Then**: 82%를 사용률로 채택(transcript 파싱 없이)
#### R2.2: transcript 폴백
- **Given**: statusline 캐시 없음, transcript 최신 usage 점유 = 921k
- **When**: 훅이 실행됨
- **Then**: 창 크기 추론(>200k→1M)으로 ~92% 산출
#### R2.3: 소스 없음 안전 종료
- **Given**: 캐시도 transcript도 못 읽음
- **When**: 훅이 실행됨
- **Then**: 아무 출력 없이 `{"continue":true}` 또는 무출력으로 종료(크래시 없음)

### R3: 임계·쿨다운·상한 넛지 (D2, D3, D4)
#### R3.1: 임계 초과 시 넛지 1회
- **Given**: 사용률 82%(≥80), 이번 세션 첫 감지
- **When**: 훅 실행
- **Then**: `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":
  "컨텍스트 82% — 적절한 지점에 /compact를 권장합니다"}}` 출력, compaction.json에
  lastNudgeAt·count=1 기록
#### R3.2: 쿨다운 내 재출력 안 함
- **Given**: 직전 넛지가 5분 전(쿨다운 20분 이내)
- **When**: 다시 82%로 훅 실행
- **Then**: 넛지 출력 없음(조용), count 불변
#### R3.3: 세션당 상한
- **Given**: 이번 세션 이미 3회 넛지함
- **When**: 다시 임계 초과
- **Then**: 더 이상 출력 안 함
#### R3.4: 임계 미만 무출력
- **Given**: 사용률 60%
- **When**: 훅 실행
- **Then**: 아무 넛지 없음(C2: 판정 후 즉시 종료)

### R4: 비용·안전 (C1, C2)
#### R4.1: 저렴한 실행
- **Given**: 임계 미만 세션
- **When**: 매 PostToolUse
- **Then**: 캐시 1회 읽기+파싱만 하고 종료(transcript 전체 파싱은 폴백 시에만, tail 위주)
#### R4.2: 읽기 전용
- **Given**: 훅 실행
- **When**: 어떤 경로든
- **Then**: 세션 JSONL/transcript를 수정하지 않고, 자동 명령 주입도 없음(넛지 stdout만)

## Tasks

### T1: preemptive-compaction 레시피 추가 (R1~R4)
- **Fulfills**: R1, R2, R3, R4
- **Depends on**: (none)
- `HookRecipeManager`에 `preemptiveCompaction` HookRecipe(PostToolUse, matcher nil, timeout 5)
  + `recipes` 배열에 추가. 스크립트(python 1패스):
  1. stdin `session_id`/`transcript_path` 파싱.
  2. 사용률 = statusline 캐시(`hook-state/statusline/<sid>.json`) used_percentage 우선,
     없으면 transcript tail의 최신 usage로 점유 계산 + 창 추론(>200k→1M else 200k).
  3. <80%면 무출력 종료(R3.4/R4.1).
  4. compaction.json(lastNudgeAt,count) 읽어 쿨다운 20분·상한 3회 확인(R3.2/R3.3).
  5. 통과 시 `hookSpecificOutput.additionalContext` 넛지 출력 + 상태 갱신(원자 쓰기).
- Global 탭 노출·설치/제거는 기존 GlobalRecipesView/HookRecipeManager 경로 자동 재사용.

### T2: 헤드리스 검증 (R2, R3)
- **Fulfills**: R2, R3 (검증)
- **Depends on**: T1
- 스크립트를 합성 stdin으로 직접 실행: (a) statusline 캐시 82% → 넛지 JSON 출력,
  (b) 60% → 무출력, (c) 쿨다운 내 재실행 → 무출력, (d) 캐시 없음 + transcript만 → 폴백 %,
  (e) 3회 후 → 무출력. + Global 탭 설치/제거 왕복(settings 무손상).

## External Dependencies

### Pre-work
- (none) — 넛지 스키마(additionalContext)는 L2에서 확인 완료. statusline 캐시·transcript
  형식도 실측 확인.

### Post-work
- build.sh + Global 탭에서 토글 라이브 확인. 실제 80% 도달 세션에서 넛지 발현은 자연 관찰
  (이 세션이 이미 92%라 statusline 켜져 있으면 관찰 가능).
