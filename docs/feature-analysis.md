---
title: "airuncat 기능 분석 — 무엇을 / 왜 / 어떻게"
date: 2026-07-13
status: active
---

# 0. 한눈에

**airuncat = Harness Engineering을 위한 메뉴바 콕핏(cockpit).**
메뉴바 고양이가 병렬 AI 코딩 세션(Claude Code + Gemini CLI)을 관제하고, 그 위에
"AI 코딩 하네스를 진단·정비·심화"하는 도구가 얹혀 있다. Swift 6 / SwiftUI MenuBarExtra /
AppKit, CLT 빌드(Xcode 불필요). 소스 49파일 · 약 11K줄 · Phase 1~17b.

정체성 상세는 `docs/direction.md`, 로드맵은 `docs/ROADMAP.md`.

## 왜 이 도구인가 (문제 정의)

1. **병렬 세션이 안 보인다** — Claude Code를 여러 탭/프로젝트에서 돌리면 "지금 뭐가
   나를 기다리는지, 뭐가 바쁜지"가 안 보인다. → 세션 관제(고양이 + 목록 + 복귀).
2. **하네스 품질이 안 보인다** — CLAUDE.md·rules·hooks·permissions가 얼마나 잘 갖춰졌는지
   점수화된 피드백이 없다. → Harness Score + 자동 세팅 + 마법사.
3. **좋은 하네스를 만들기가 번거롭다** — 매번 CLAUDE.md 쓰고 rule 짜고 훅 설정하는 게 수동.
   → 큐레이팅 레시피/템플릿을 "고르고 → 보고 → 켠다".
4. **사용량 한도가 안 보인다** — 5시간/주간 한도에 얼마나 근접했는지 터미널에선 안 보인다.
   → 공식 사용량 API 게이지.

## 복리 루프 (제품의 심장)

```
관찰(Sessions·Stats) → 진단(Harness Score) → 보완(자동 세팅·마법사)
    → 심화(훅 레시피·rule 템플릿·LLM 진단) → 다시 관찰
```
"51번째 작업이 50번째보다 낫게" 만드는 하네스 개선 사이클을 GUI로 구현한 것.

---

# 1. 세션 관제 (관찰 레이어)

## 1.1 메뉴바 고양이 (`CatRenderer`, `SessionStore`)
- **무엇**: 메뉴바 아이콘이 벡터로 그린 고양이. AI가 바쁠수록(활성 세션 많을수록) 빨리
  질주하고, 조용하면 웅크려 잔다. 응답 대기 세션이 있으면 우상단에 빨간 배지.
- **왜**: "개발 인프라 도구"를 늘 곁에 있고 귀엽게(ambient delight) 만들어 차별점(soul)을
  유지. 숫자 없이도 힐끗 보고 상태를 안다.
- **어떻게**: `SessionStore.tick()`이 0.07s 타이머로 `phase`를 증가, 속도 = `0.28 + 0.16 ×
  min(active,4)`. 프레임마다 NSBezierPath로 몸/머리/귀/꼬리/다리 재렌더. template image라
  다크/라이트 자동 틴팅(대기 버블만 컬러). 상세: `docs/cat-design.md`.

## 1.2 세션 목록 · 상태 (`SessionScanner`, `MenuContentView`)
- **무엇**: 드롭다운에 Claude/Gemini 세션 목록. 각 행 = AI 색 배지(Claude 보라/Gemini 청록),
  상태(응답 대기/working/idle/resting), 제목, 지금 하는 일(마지막 툴/스킬), 상대 시각.
  행을 펼치면 **컨텍스트 토큰 채움·지속시간·payload 압력** 상세.
- **왜**: 여러 세션 중 "나를 기다리는 것(응답 대기)"을 최우선으로 띄워, 병렬 작업의
  컨텍스트 스위칭 비용을 줄인다.
- **어떻게**: `~/.claude/projects/*/*.jsonl`를 읽기 전용 파싱(mtime 캐시, 큰 파일은
  head/tail). 활성 판정은 mtime 기준(active<90s / idle<30m / resting). 상세: `docs/data-sources.md`.
  Gemini는 `~/.gemini/tmp/*/chats/*.jsonl`(`GeminiScanner`).

## 1.3 세션 복귀 (`ITermController`, `ProcessDetector`)
- **무엇**: 세션 행 클릭 → 그 세션이 떠 있는 iTerm2 탭으로 포커스, 없으면 새 탭에서 `claude -r`.
- **왜**: "봤으니 이제 돌아가자"를 원클릭으로. 관제의 목적은 결국 복귀.
- **어떻게**: AppleScript로 iTerm 세션(id,tty) 나열 → `ps -t`+`lsof`로 각 tty의 cwd를 세션
  cwd와 매칭 → 정확한 탭 select. Warp는 AppleScript 미지원이라 iTerm2로 결정.

## 1.4 최근 종료 세션 복구 (`SessionStore.recentlyClosed`)
- **무엇**: 방금 닫힌 세션을 30초간 "Recently Closed"에 남겨 재개 가능.
- **왜**: 실수로 닫거나 `/clear` 후 되돌리고 싶을 때.

## 1.5 커스텀 이름 · 태그 (`CustomNameStore`, `TagStore`)
- **무엇**: 세션에 사람이 읽는 이름 붙이기, 태그로 필터.
- **왜**: 프로젝트명만으론 구분 안 되는 다중 세션 정리.

---

# 2. 사용량 관제 (Claude Code 한도)

## 2.1 사용량 게이지 (`UsageAPIClient`, `UsageStore`)
- **무엇**: 헤더에 5시간 롤링 창 / 주간 창의 실제 사용률 % + 리셋 카운트다운
  (예: `5h 70% (3h42m)`). 70%/90% 임계로 색 변화.
- **왜**: Claude Code Max/Pro의 5h·주간 한도에 얼마나 근접했는지가 터미널엔 안 보인다.
  한도 초과로 갑자기 막히는 걸 미리 안다.
- **어떻게**: **토큰 합산 근사가 아니라** Anthropic 공식 API를 호출한다 —
  macOS Keychain의 `Claude Code-credentials` OAuth 토큰으로
  `GET api.anthropic.com/api/oauth/usage` → `five_hour`/`seven_day`의 `utilization`·`resets_at`.
  (초기엔 JSONL 토큰 합산으로 근사했으나 cache_read가 소비를 지배해 "초과" 오탐 → 공식 API로 교체.)
- **견고성**: 만료 시 lazy 토큰 리프레시(Keychain 재기록, 동시 갱신 레이스 3중 방어),
  429 지수 백오프, 일시 오류엔 직전 값 15분까지 `*` 배지로 stale 유지.

## 2.2 임계 알림 (`NotificationManager`)
- **무엇**: 사용량 90% 초과 시 알림, 80% 밑으로 회복(리셋) 시 "여유 회복" 알림.
- **왜**: 한도 벽에 부딪히기 전 경고. (OMC의 자동 세션 재개는 read-only 철학과 충돌해 제외 —
  알림만.)

---

# 3. Harness Engineering (진단·보완·심화 레이어) — 제품의 차별점

세션 행의 Harness 배지 → 팝오버(`HarnessPopoverView`)가 진입점.

## 3.1 Harness Score (`HarnessScanner`, `HarnessScoring`) — 진단
- **무엇**: 프로젝트의 하네스 성숙도를 5축(준비/맥락/실행/검증/개선)으로 A~F 채점.
- **왜**: "내 CLAUDE.md·rules·hooks·permissions가 얼마나 잘 갖춰졌나"를 눈에 보이는 점수로.
  harness-checklist 방법론(이론)을 GUI로 실체화.
- **어떻게**: `<cwd>/.claude` + CLAUDE.md의 **정적 신호만** 채점(프로젝트-로컬):
  CLAUDE.md 단어수/@import, 프로젝트 rule 수, deny 권한, 활성 Pre/PostToolUse 훅,
  프로젝트 스킬 수, 비활성 훅 수(≤2). LLM·세션은 점수에 미반영.

## 3.2 자동 세팅 (`HarnessManager`, `HarnessSetup`) — 보완
- **무엇**: ✗ 항목을 인라인 버튼으로 즉시 보완: CLAUDE.md 생성, 시작 rule 생성,
  민감파일 deny 추가, 훅 비활성 템플릿 추가.
- **왜**: 진단만 하고 끝내지 않고 원클릭으로 고칠 수 있게. 단 **비파괴·비실행**:
  파일은 부재 시에만 생성, 훅은 비활성으로만 추가(임의 명령 자동 실행 금지).
- **신뢰 원칙**: 진단→제안→**사용자 확인**→적용. 외부 변경 방지용 mtime 가드.

## 3.3 세팅 마법사 (`HarnessWizardView`) — 보완(가이드 경로)
- **무엇**: C 이하 프로젝트를 4단계(CLAUDE.md→rules→deny→훅 레시피)로 한 흐름에 끌어올림.
  각 단계 미리보기 후 적용/건너뛰기, 마지막에 실재채점 등급 변화 표시(F→B).
- **왜**: 파편적 인라인 버튼을 순서 있는 온보딩으로. 낮은 등급 프로젝트의 진입장벽 제거.
- **어떻게**: 전부 3.2의 기존 함수 재사용(신규 쓰기 로직 없음). 훅은 "명령 전문을 본
  단계에서 [추가+켜기] 명시 선택"했을 때만 활성(그래야 검증축 충족 → B 도달).

## 3.4 프로젝트 훅 레시피 (`ProjectHookRecipe`) — 심화
- **무엇**: 팝오버 rules/hooks 섹션 "+ 레시피" → 프로젝트 타입(swift/node/python/rust/go)에
  맞는 큐레이팅 훅 5종: build/format/lint + guard 2종(민감파일·위험 bash 차단).
- **왜**: "훅도 세팅해줘"의 안전한 구현 — AI가 명령을 추측하는 게 아니라 **검증된 명령을
  타입에 맞춰 채워 보여주고 사용자가 켠다**. Phase 14의 빈 템플릿이 "검증된 원클릭 훅"으로 진화.
- **어떻게**: guard는 공식 프로토콜(`permissionDecision: deny` JSON)로 차단.
  훅 입력은 stdin JSON(`INPUT=$(cat)`+python3 파싱). guard는 이스케이프 안전한 python
  기반(json.dumps)이며 **베스트에포트 트립와이어**(완전한 보안 경계 아님).

## 3.5 rule 템플릿 라이브러리 (`RuleTemplate`) — 심화
- **무엇**: rules 섹션 "+ 템플릿" → 큐레이팅 rule 6종(no-secrets, no-destructive-git,
  no-new-dependencies, build-must-pass, test-with-changes, swift-clt-only).
- **왜**: rule 생성을 빈 껍데기("여기에 제약을 기술한다")에서 실전 템플릿 선택으로.
- **원칙**: "위반이 판별 가능한 구체 제약만" — 일반론("코드를 잘 짜라") 금지.

## 3.6 LLM 내용 품질 진단 (`QualityScanner`) — 심화
- **무엇**: 팝오버 "LLM 진단" 버튼 → CLAUDE.md/rules의 플레이스홀더·모순·모호함을 점수로.
- **왜**: 정적 Score가 못 보는 **내용 품질**(TODO 방치, 서로 모순되는 지시)을 LLM이 본다.
- **비용 헌법**: 수동 트리거만(자동 실행 0), 입력 4KB 합산 캡, 입력 해시 캐시, `claude -p
  --bare --model haiku`(소형). Score엔 미반영(참고 정보).

## 3.7 Global 탭 (`GlobalRecipesView`, `HookRecipeManager`, `StatuslineManager`)
- **무엇**: 6번째 탭. airuncat 저작 **글로벌 레시피** 4종을 설치/제거 토글 —
  세션 텔레메트리·서브에이전트 트래커·rules 주입기(훅) + statusline.
- **왜**: 프로젝트 스코프인 Harness 팝오버와 분리(전역 설정은 별도 표면). 자체 검증
  스크립트라 직접 토글 허용, 스크립트 전문 인앱 미리보기로 "켜기 전에 뭘 켜는지" 투명.
- **statusline**: 설치 시 Claude Code가 상태줄에 주는 JSON(네이티브 컨텍스트 %·rate limits·
  모델)을 캐시 → 세션 행 게이지를 "82k/200k" 근사 대신 **"ctx 49% · 1M 창"** 실측으로 업그레이드.
- **hook-state 열람(`HookStateReader`)**: 텔레메트리가 쌓은 메트릭 → Recently Closed 캡션
  ("34m · 도구 12회"), 서브에이전트 기록 → 세션 행 "서브에이전트 N회".

---

# 4. 하네스 리소스 관리 (탭)

| 탭/기능 | 무엇 | 왜 | 파일 |
|---------|------|-----|------|
| **Skills** | ~/.airuncat/skills(글로벌)·프로젝트 `.claude/{commands,skills}`·네이티브 `~/.claude/skills`를 스코프별 접이식 폴더로. C/G 링크 토글로 활성화 | 흩어진 스킬(슬래시 커맨드)을 한곳에서 관리·활성화 | `SkillScanner`,`SkillToggler`,`SkillsView` |
| **Prompts** | ~/.airuncat/prompts 프롬프트를 핀/카테고리/검색, 세션에 삽입 | 반복 프롬프트 재사용 | `PromptScanner`,`PromptManager`,`PromptLibraryView` |
| **MCP** | ~/.mcp.json 서버 등록/삭제 + settings.local.json 활성 토글 | MCP 서버를 GUI로 켜고 끔 | `MCPScanner`,`MCPManager`,`MCPView` |
| **CLAUDE.md 배지** | 글로벌/프로젝트 CLAUDE.md 존재·미리보기·생성 | 하네스 핵심 파일 빠른 접근 | `ClaudeMdScanner`,`ClaudeMdPopoverView` |
| **Memory 배지** | ~/.claude/projects/*/memory 타입별 그룹·미리보기·삭제 | Claude 자동 메모리 관리 | `MemoryScanner`,`MemoryManager`,`MemoryPopoverView` |

---

# 5. 보조 기능

## 5.1 Stats 탭 (`StatsScanner`, `StatsStore`, `StatsView`)
- **무엇**: 세션 활동 히트맵(7×24), 자주 쓴 스킬 바 차트, 기간 필터.
- **왜**: "언제 얼마나 일하는지" 습관을 보이게. 데이터 viz는 Claude 데이터라 Claude 보라색.

## 5.2 퀵 팔레트 (`QuickPalette`, `PaletteViewModel`, `GlobalShortcut`)
- **무엇**: ⌥Space 글로벌 단축키 → 스킬+프롬프트 통합 검색·삽입 플로팅 창.
- **왜**: 드롭다운을 안 열고도 어디서든 스킬/프롬프트를 세션에 꽂는다. 최근 이력 우선.

## 5.3 알림 (`NotificationManager`)
- 응답 대기 세션 알림(클릭 시 iTerm 복귀), 사용량 임계 알림.

---

# 6. 아키텍처 · 데이터 흐름

## 읽는 것(전부 읽기 전용, `read-only-sessions` 규칙)
| 소스 | 용도 |
|------|------|
| `~/.claude/projects/*/*.jsonl` | 세션 상태·토큰·duration·payload·usage |
| `~/.gemini/tmp/*/chats/*.jsonl` | Gemini 세션 |
| macOS Keychain `Claude Code-credentials` | 사용량 API OAuth 토큰(+리프레시 재기록) |
| `api.anthropic.com/api/oauth/usage` | 실제 5h/주간 사용률 |
| `~/.claude/settings.json` | rules·hooks·permissions·statusLine (읽고 원자 쓰기) |
| `~/.airuncat/hook-state/` | 레시피가 쌓는 메트릭·서브에이전트·statusline 캐시 |

## 쓰는 것 (사용자 확인 후, 원자적)
- `~/.airuncat/**` (스킬·프롬프트·설정·캐시), `~/.claude/commands`·`~/.gemini/commands`(심볼릭),
  `~/.claude/settings.json`(훅/statusline/권한 병합 — `SettingsFileIO` 공용), `.claude/rules/*.md`.

## 상태 관리
- `@MainActor ObservableObject` 스토어(SessionStore/UsageStore/StatsStore/QualityScanner).
- 무거운 파일 I/O는 `Task.detached` 백그라운드 → 메인에서 게시. mtime 증분 캐시로 재파싱 회피.

---

# 7. 설계 원칙 (어기면 망가지는 지점)

1. **한 가지 일에 복무** — 모든 기능은 "네 하네스를 관찰→개선"에 기여. 탭마다 미니 앱이
   되는 스코프 크리프 경계.
2. **고양이를 묻지 마라** — 관리 UI가 늘어도 성격(ambient delight)이 중심.
3. **신뢰가 생명** — 진단→제안→**사용자 확인**→적용. 파괴적·실행형(훅 명령)은 절대 자동으로
   켜지 않는다. LLM 진단도 수동 1회.
4. **세션은 읽기 전용** — `~/.claude/projects/**`는 관찰만.
5. **CLT 빌드만** — swift build / build.sh, Xcode 의존 금지.
6. **작성·리뷰 분리** — 모든 Phase는 스펙→별도 Claude 리뷰어→검증→PR(`docs/workflow.md`).
   이 분리가 실제 버그(파이프 데드락·가드 JSON 무력화·settings 쓰기 버그·훅 placebo)를 잡아냄.

---

# 8. 진화 요약 (Phase)

| Phase | 내용 |
|-------|------|
| 1~4 | 세션 관제 기반: 고양이·목록·복귀·work state·Gemini |
| 2~3 | Skills·Prompts 관리자 + 로컬 저장소 |
| 6~10 | MCP·Rules·Memory·CLAUDE.md 관리 |
| 11~12 | 퀵 팔레트·세션 Stats |
| **13** | Harness Score (5축 A~F) |
| **14** | Harness 자동 세팅 |
| **15 / 15.1 / 15.2** | 훅 레시피 카탈로그 / Global 탭 / hook-state 열람 |
| **16** | 세팅 마법사 (F→B) |
| **17a / 17b** | rule 템플릿 라이브러리 / LLM 품질 진단 |
| (하드닝) | 파이프 데드락·가드 JSON·settings IO 수리 |

세부 스펙은 `docs/specs/phase-*.md`. UI 개편 이력은 `docs/ui-redesign.md`.
