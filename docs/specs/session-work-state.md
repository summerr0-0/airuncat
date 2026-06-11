---
title: "세션 작업 상태 표시 (Session Work State)"
date: 2026-06-09
status: draft
---

# Session Work State

## 목표

세션 상세 행에서 현재 작업 상태를 텍스트로 표시하고,
입력 대기 세션이 있을 때 메뉴바 고양이 옆에 시각적 신호를 추가한다.

---

## 범위 (In / Out)

### In
- `WorkState` enum: `.working` / `.waitingInput` / `.completed`
- `SessionScanner` 백워드 패스 확장 — 마지막 이벤트 패턴으로 WorkState 판별
- `SessionInfo`에 `workState: WorkState` 필드 추가
- `SessionRow`에 상태 텍스트 레이블 표시 (작업중 / 입력 대기 / 완료)
- `SessionStore`에 `hasWaitingSession: Bool` 프로퍼티 추가
- 메뉴바 레이블: 입력 대기 세션 존재 시 고양이 옆 작은 점(·) 추가

### Out
- `SessionStatus` (active/idle/resting) 변경 없음 — 기존 색상 도트와 시간 기반 로직 유지
- 알림(`NotificationManager`) 로직 변경 없음
- Gemini 세션 연동 없음

---

## WorkState 판별 로직

`SessionScanner` 백워드 패스를 다음 두 가지를 추가로 캡처하도록 확장한다.

| 변수 | 의미 |
|------|------|
| `lastAssistantHasTool` | 마지막 `assistant` 이벤트에 `tool_use` 블록이 있는가 |
| `lastEventRole` | JSONL의 맨 마지막 유효 이벤트 타입 (`"user"` / `"assistant"`) |

**판별 규칙 (우선순위 순):**

```
1. session.status == .resting          → .completed
2. lastAssistantHasTool == true        → .working
   (Claude가 도구를 호출하고 결과 대기 중)
3. lastEventRole == "user"             → .working
   (tool_result를 포함한 user 이벤트가 마지막 = Claude 처리 중)
4. lastAssistantHasTool == false
   && lastEventRole == "assistant"     → .waitingInput
   (Claude가 텍스트만 응답하고 사용자 입력 대기)
5. 그 외 (파싱 실패, 빈 파일 등)      → .completed
```

---

## UI 변경

### SessionRow — 상태 레이블

기존 색상 도트(8pt circle) 오른쪽에 텍스트 레이블을 추가한다.
레이블은 제목 줄 끝(trailing) 또는 activity 라인 대신 표시한다.

| WorkState | 텍스트 | 색상 |
|-----------|--------|------|
| `.working` | `작업중` | `.green` |
| `.waitingInput` | `입력 대기` | `.orange` |
| `.completed` | `완료` | `.secondary` |

레이블 위치: `subtitleRow` 오른쪽 끝 (작은 chip 형태, font size 10).

### 메뉴바 레이블

```swift
// AiruncatApp label:
HStack(spacing: 3) {
    Image(nsImage: store.catImage)
    if store.hasWaitingSession {
        Circle()
            .frame(width: 5, height: 5)
            .foregroundColor(.primary)   // template 방식: 단색
    }
}
```

- `hasWaitingSession`: `visibleSessions` 중 `.waitingInput`인 세션이 1개 이상
- 점 크기 5pt, 단색(template-style)으로 다크/라이트 자동 대응

---

## 데이터 흐름

```
SessionScanner.parse()
  └─ backward pass 확장
       ├─ lastAssistantHasTool: Bool
       └─ lastEventRole: String
  └─ workState: WorkState 계산
  └─ SessionInfo.workState 저장

SessionStore.visibleSessions
  └─ hasWaitingSession: Bool (derived)

SessionRow
  └─ workState → 레이블 텍스트/색상

AiruncatApp label
  └─ store.hasWaitingSession → 점 표시
```

---

## 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 빈 JSONL (새 세션) | `lastEventRole` 미설정 → rule 5 → `.completed` |
| 파일 크기 > 4MB (tail만 읽는 경우) | tail 512KB 안에서 판별 — 최신 이벤트를 포함하므로 충분 |
| `assistant` 메시지가 tool_use + text 혼합 | `tool_use` 블록이 하나라도 있으면 `lastAssistantHasTool = true` |
| 캐시 히트 (mtime 불변) | `workState`도 캐시에 포함 — 재파싱 불필요 |
| resting 세션이 갑자기 active로 전환 | 다음 스캔 틱에서 재계산됨 |

---

## 검증 방법

1. `swift build` 통과
2. `/run-clawde` 로 앱 재시작 후 메뉴바 확인
3. 현재 활성 Claude 세션 목록에서:
   - 작업 중인 세션: "작업중" 레이블 확인
   - 응답 대기 세션: "입력 대기" 레이블 + 메뉴바 점 확인
   - 오래된 세션: "완료" 레이블 확인
