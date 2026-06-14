---
title: "Phase 4 — Gemini 연동 고도화 spec"
date: 2026-06-13
status: complete
---

# 목표

Gemini CLI 세션의 표시 품질을 Claude 세션 수준으로 끌어올린다.
현재 Gemini 세션은 `toolName`/`toolDetail`/`activeSkill`이 항상 빈 값이라
"지금 무엇을 하는지" 알 수 없다. Gemini JSONL의 `toolCalls` 필드를 파싱해
실시간 도구 사용 현황을 표시하고, 헤더에 Claude/Gemini 구분 통계를 추가한다.

# 범위

**In:**
- `GeminiScanner`: backward pass에서 `toolCalls` 파싱 → `toolName`, `toolDetail` 설정
- `GeminiScanner`: `model` 필드 파싱 → `SessionInfo`에 새 필드 `modelName: String?` 추가
- `SessionStore`: `claudeActiveCount`, `geminiActiveCount` 산출 computed property
- `MenuContentView.summary`: "2C 1G active · 1 idle" 형태로 C/G 구분 표시
- `SessionScanner`/`SessionInfo`: `modelName` 필드 추가 (Claude는 nil)

**Out:**
- Gemini 세션에서 `activeSkill` 표시 (Gemini는 `/skill:name` 개념 없음)
- 통합 세션 타임라인 (별도 Phase로)
- Gemini 토큰 사용량 집계 UI
- 모델별 필터 (탭 분리 없음, 기존 C/G 배지로 충분)

# 동작 / UI

## 헤더 summary

```
airuncat          2C 1G active · 1 idle
```

| 상태 | 출력 |
|------|------|
| active 없음 | `all quiet` |
| Claude만 | `2C active · 1 idle` |
| Gemini만 | `1G active` |
| 혼합 | `2C 1G active · 1 idle` |

## 세션 행 — Gemini toolName

현재 Claude:
```
● clawde                          C ✓   5s  [tag]
  "다음 작업 이어서 해줘"
  Bash: swift build
```

Phase 4 Gemini:
```
● dailybit-actions-menu           G ✓   8s
  "BitActionsMenu 코드리뷰"
  read_file: BitCard.tsx           ← toolName: toolDetail 표시
```

## Gemini toolCalls 파싱 로직

Gemini JSONL `gemini` 타입 메시지 구조:
```json
{
  "type": "gemini",
  "content": "",
  "model": "gemini-3-flash-preview",
  "toolCalls": [
    {
      "id": "read_file__...",
      "name": "read_file",
      "args": {"file_path": "src/components/bits/BitCard.tsx"},
      "result": [...]
    }
  ]
}
```

**추출 전략 (backward pass):**
1. 가장 마지막 `gemini` 타입 메시지 중 `toolCalls`가 비어있지 않은 것을 찾는다
2. `toolCalls.last.name` → `toolName`
3. `toolCalls.last.args` 중 경로/문자열 파라미터 첫 번째 → `toolDetail`
   - `["file_path", "path", "command", "query"]` 순서로 시도 (Dict 순서 비결정적이므로 preferredKeys 배열 사용)
   - 없으면 `args.values.compactMap { $0 as? String }.first`
4. backward pass: `seenIds: Set<String>` 으로 중복 메시지 ID skip
5. `model` 필드 → `modelName`
4. `model` 필드 → `modelName`

**동작 조건:**
- `workState == .responded` (마지막 이벤트가 gemini) → toolCalls가 있으면 표시
- `workState == .working` (마지막 이벤트가 user) → 이전 gemini 메시지의 toolCalls 표시

## SessionInfo 변경

```swift
struct SessionInfo {
    // 기존 필드 유지...
    var modelName: String?  // "gemini-3-flash-preview" | nil (Claude)
}
```

`modelName`은 세션 행에 표시하지 않음 (요약에서만 향후 활용 가능).
현재는 파싱만 해서 필드에 저장; 향후 Phase에서 활용.

# 데이터 소스

| 소스 | 필드 | 비고 |
|------|------|------|
| Gemini JSONL `gemini` 메시지 | `toolCalls[].name` | backward pass |
| Gemini JSONL `gemini` 메시지 | `toolCalls[].args` | 첫 번째 값 |
| Gemini JSONL `gemini` 메시지 | `model` | string |
| SessionStore | `sessions.filter { aiKind == .claude && active }` | computed |

# 신규/수정 파일

| 파일 | 변경 |
|------|------|
| `SessionScanner.swift` | `SessionInfo`에 `modelName: String?` 추가 |
| `GeminiScanner.swift` | backward pass: toolCalls + model 파싱 |
| `SessionStore.swift` | `claudeActiveCount`, `geminiActiveCount` |
| `MenuContentView.swift` | `summary` 로직 C/G 구분 |

# 엣지케이스

- `toolCalls` 배열 비어있음 → toolName/toolDetail 빈 값 유지 (현재와 동일)
- `args` 딕셔너리 비어있음 → toolDetail = ""
- `model` 필드 없는 구버전 Gemini JSONL → modelName = nil (graceful)
- Gemini 세션이 0개 → summary에 G 표기 생략
- 동일한 `gemini` 메시지가 JSONL에 중복 (GeminiScanner 기존 `$set` 처리 참고)
  → backward pass는 마지막 등장 기준 (중복 무시)

# 검증 방법

1. `swift build` 통과
2. Gemini 세션 활성 상태에서 `/run-clawde` → 행에 `read_file: BitCard.tsx` 등 표시
3. Claude + Gemini 세션 동시 활성 → 헤더에 "1C 1G active" 표시
4. Gemini 세션만 있을 때 → "1G active"
5. `toolCalls` 없는 Gemini 메시지 → toolName 빈 값, 앱 크래시 없음

# 미해결 질문

- `toolCalls`의 `args` 키 네이밍이 Gemini 버전에 따라 다를 수 있음
  → 정해진 키 목록(`file_path`, `path`, `command`, `query`) 시도 후 fallback으로 첫 번째 값
- backward pass에서 중복 메시지 ID 처리: 동일 `id`가 두 번 나오는 경우
  → `Set<String>`으로 seen ID 추적, 중복 skip
