# Phase 1.5 Spec — 활성 스킬 표시

## 목표

세션 행에 현재 실행 중인 스킬 이름을 표시한다.
Claude가 `/daily-vocab` 같은 스킬을 실행 중일 때, 사용자가 메뉴바 드롭다운에서 어느 세션이
어떤 스킬을 돌리고 있는지 즉시 파악할 수 있게 한다.

## 범위 (In / Out)

In:
- JSONL 파싱 시 마지막 `Skill` tool_use를 감지하고, 대응하는 tool_result가 없으면 "실행 중"으로 판정
- `SessionInfo`에 `activeSkill: String?` 필드 추가
- 세션 행 UI에 `[/skill-name]` 배지 표시 (workState == .working 일 때만)

Out:
- Gemini CLI 스킬 감지 (GeminiScanner는 이번에 건드리지 않음)
- 스킬 히스토리 / 완료된 스킬 표시
- 스킬 취소 버튼 등 인터랙션

## JSONL 이벤트 구조

```
// 스킬 호출 (assistant 이벤트)
{
  "type": "assistant",
  "message": {
    "content": [{
      "type": "tool_use",
      "id": "toolu_abc",
      "name": "Skill",
      "input": { "skill": "daily-vocab", "args": "" }
    }]
  }
}

// 스킬 완료 (user 이벤트 — tool_result)
{
  "type": "user",
  "message": {
    "content": [{
      "type": "tool_result",
      "tool_use_id": "toolu_abc",
      "content": "..."
    }]
  }
}
```

## 판정 로직

backward pass에서 (최신 → 과거 순):
1. user 이벤트에서 `tool_result`를 만나면 해당 `tool_use_id`를 "완료 세트"에 추가
2. assistant 이벤트에서 `Skill` tool_use를 만났을 때:
   - `id`가 완료 세트에 없으면 → `activeSkill = input.skill` (실행 중)
   - `id`가 완료 세트에 있으면 → `activeSkill = nil` (완료됨)
3. 최초 Skill tool_use 발견 시 탐색 종료

## 데이터 변경

`SessionInfo`에 필드 추가:
```swift
var activeSkill: String?   // nil이면 스킬 없음 또는 완료
```

## UI 변경 (`MenuContentView`)

세션 행 subtitle 영역에 activeSkill이 있으면 추가 표시:
- 위치: `toolName` 표시 바로 앞 또는 대체
- 형태: `"/daily-vocab"` 텍스트 (회색 작은 폰트, 이미 있는 badge 스타일 활용)
- 조건: `workState == .working && activeSkill != nil`

## 엣지 케이스

- 대용량 파일(tail 512KB 청크): 스킬 호출은 tail에 있을 가능성 높음, 현재 backward pass 범위 내에서 처리 가능
- 같은 세션에서 여러 스킬 순차 실행: 마지막 것만 표시 (가장 최근 호출)
- tool_use와 tool_result가 같은 tailData 청크에 없는 경우: tool_result 미발견 → 실행 중으로 보수적 판정

## 검증

1. `swift build` 그린
2. `/run-clawde`로 앱 재시작
3. 스킬이 실행 중인 세션에서 메뉴바 드롭다운 확인 → `/skill-name` 배지 표시
4. 스킬 완료 후 다음 tick에서 배지 사라짐 확인
