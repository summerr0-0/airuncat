---
title: "Phase 15.2 — hook-state 데이터 열람"
date: 2026-07-10
status: active
---

# 목표

Global 탭 레시피가 쌓는 `~/.airuncat/hook-state/` 데이터를 **이미 있는 UI 표면에 얹어** 보여준다.
데이터를 만들었으면(15/15.1) 보여줘야 루프가 닫힌다. 새 탭·새 팝오버는 만들지 않는다.

| 데이터 | 생산자(레시피) | 경로 | 소비 위치(이 스펙) |
|--------|---------------|------|--------------------|
| 세션 메트릭 | session-telemetry (SessionEnd) | `hook-state/sessions/<id>/metrics.json` | **Recently Closed 행** 캡션 |
| 서브에이전트 기록 | subagent-tracker (SubagentStop) | `hook-state/sessions/<id>/subagents.jsonl` | **세션 행 확장** 한 줄 |

# 설계 원칙

1. **표면 재사용** — Recently Closed(종료 세션 데이터가 자연스러운 곳) + 행 확장(라이브 상세가 이미 있는 곳).
2. **없으면 침묵** — 레시피 미설치/데이터 없음이면 아무것도 표시하지 않음(존재 조건 자연 충족).
3. **읽기 전용·경량** — 파일 존재 시에만 파싱. subagents.jsonl은 라인 수만(내용 파싱 불필요).

# 범위

**In:**
- `HookStateReader.swift`(신규, enum·정적): `metrics(sessionId:) -> SessionMetrics?`
  (duration_seconds/tool_uses/user_messages 파싱), `subagentCount(sessionId:) -> Int?`
  (jsonl 라인 수, 0이면 nil).
- `RecentlyClosedRow`: metrics 있으면 캡션 한 줄 — 예: `"34m · 도구 12회 · 메시지 6"`.
- 세션 행 확장(`expandedDetail`): subagentCount 있으면 `"서브에이전트 N회"` 텍스트 추가.
- 검증 목적 포함: session-telemetry + subagent-tracker 레시피 **실설치**(Global 탭 기능의
  실사용 개시 — 루프 사전 승인 범위).

**Out:**
- 상세 열람 뷰(서브에이전트 목록/타임라인) — 데이터가 쌓인 뒤 필요해지면 15.3.
- rules-injector 상태 표시(injected-rules는 세션 내부용).
- statusline 캐시 표시(이미 R4가 소비 중).

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| metrics.json 파싱 실패/필드 없음 | nil → 캡션 생략 |
| subagents.jsonl 빈 파일 | count 0 → nil → 생략 |
| 레시피 미설치 | 파일 없음 → 전부 침묵 |
| duration 0/음수 | 0이면 duration 부분 생략, 나머지 표시 |

# 변경 파일

| 파일 | 변경 |
|------|------|
| `HookStateReader.swift`(신규) | metrics/subagentCount 리더 |
| `MenuContentView.swift` | RecentlyClosedRow 캡션 + expandedDetail 한 줄 |

# 검증

1. `swift build` 그린 + 재실행.
2. 레시피 2종 설치(CLI) → 짧은 세션 열고 닫아 metrics 생성 → Recently Closed 캡션 확인.
   (세션 열고닫기가 즉시 안 되면: 합성 metrics.json으로 표시 검증 + 실데이터는 자연 발생 관찰)
3. 서브에이전트를 쓴 세션(이 세션)에서 subagents.jsonl 누적 → 행 확장에 "서브에이전트 N회".
4. 미설치 프로젝트/세션에서 아무 표시 없음(침묵) 확인.

# Next Action
- [x] Claude 리뷰어 패스 — PASS(구현 노트 3건 반영: @State 캐시 로드, user_messages 캡션 제외, 합성 검증)
- [x] 사용자 승인 — 루프 사전 전체 승인(2026-07-10)
