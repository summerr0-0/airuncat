---
title: "Phase 1.5 — 세션 행 표시 개선"
date: 2026-06-11
status: draft   # Gemini 교차검토 완료 2026-06-11
---

# 목표

세션 행의 세 번째 줄(activity line)을 세션 상태에 맞게 더 유용한 정보로 교체한다.
현재는 `toolName: toolDetail` (마지막 도구 호출)만 표시하는데,
Claude가 응답을 완료한 상태(`responded`)에서는 "마지막 사용자 질문"을 보여주면
어떤 세션이 무엇을 하던 중인지 한눈에 파악할 수 있다.

# 범위

- **In**:
  - `SessionInfo`에 `lastUserMessage: String` 필드 추가
  - `SessionScanner` backward pass에서 마지막 실제 user 텍스트 추출
  - `SessionRow.activity` 로직 변경: 상태별 분기
    - `working` + toolName 있음 → 현행 유지 (`ToolName: detail`)
    - `working` + toolName 없음 → `lastUserMessage` (폴백)
    - `responded` → `lastUserMessage` (현재 "무엇을 물었나" 맥락)
  - `GeminiScanner`도 동일 필드 추출 (가능하면)

- **Out**:
  - pty/tty stdout 읽기 (부하·복잡도 과대)
  - 커스텀 이름 표시 방식 변경 (현행 `customName ?? title` 유지)
  - 행에 새 줄 추가 (3줄 구조 유지). 세 번째 줄이 빈 경우 숨겨져 행 높이가 줄어드는 것은 기존 동작과 동일

# 동작 / UI

세션 행은 현재 최대 3줄:
```
[status bar] [C/G] displayName                       [time]
                   projectName  [tags]  branch       [tag btn]
                   ToolName: detail                  [resume]  ← 변경 대상
```

변경 후 세 번째 줄 규칙:

| workState | toolName | 표시 내용 |
|-----------|----------|-----------|
| working   | 있음     | `ToolName: detail` (변화 없음) |
| working   | 없음     | `lastUserMessage` (축약, 1줄) |
| responded | -        | `lastUserMessage` (축약, 1줄) |
| 둘 다 없음 | -       | 줄 자체 숨김 (현행 동일) |

`lastUserMessage`가 비어 있으면 세 번째 줄을 표시하지 않는다.

# 데이터 소스 / 의존

- `SessionScanner.parse()` backward pass:
  - 현재 마지막 `assistant` 이벤트의 tool_use를 찾는 루프를 이미 실행 중
  - 같은 루프에서 마지막 `user` 이벤트의 텍스트도 추출 (`userText()` 재사용)
  - `isRealInstruction()` 필터 적용 + `` ``` `` 시작 줄 추가 필터 (코드블럭 마커 노출 방지)
  - `firstLine()` 헬퍼로 첫 줄 추출 후 `trim(_, 100)` — 스캐너 저장 한도
  - UI 렌더링 절단은 SwiftUI `.lineLimit(1)` + `.truncationMode(.tail)` 에 위임

- `GeminiScanner`:
  - Gemini JSONL 구조 확인 후 동일 패턴으로 추출, 어려우면 빈 문자열로 초기화

- `SessionInfo`: 필드 1개 추가, 기존 필드 변경 없음

# 엣지케이스

- `lastUserMessage`가 `firstInstruction`과 동일한 경우(단일 교환 세션): 그대로 표시
- 대용량 파일(tail-only 파싱): backward pass는 이미 tailData를 사용하므로 동일하게 처리됨
- 멀티라인 사용자 입력: 첫 번째 줄만 표시 (`firstLine()` 헬퍼 재사용)
- Gemini 세션: JSONL 구조가 다르면 `lastUserMessage = ""` 폴백, 표시 생략

# 검증 방법

1. `swift build` 통과
2. `/run-clawde` 로 앱 재시작
3. 시나리오 A — **working**: Claude가 도구 실행 중인 세션 → 세 번째 줄에 `ToolName: detail` 표시
4. 시나리오 B — **responded**: Claude가 답변 완료한 세션 → 세 번째 줄에 마지막 질문 텍스트 표시
5. 시나리오 C — 커스텀 이름 있는 세션 → displayName은 커스텀 이름, 세 번째 줄은 `lastUserMessage`
6. 시나리오 D — 오래된(resting) 세션 → `lastUserMessage` 표시 (working/responded 무관)
7. 시나리오 E — 신규 세션 (아무 대화 없음) → `lastUserMessage = ""`, 세 번째 줄 숨김, 행 높이 자연스럽게 줄어듦

# 미해결 질문

- Gemini JSONL에서 user 메시지를 추출하는 방법은 GeminiScanner 구조를 봐야 확정됨.
  어려우면 이번 Phase는 Claude 세션만 적용하고 Gemini는 다음 스프린트로 분리한다.
