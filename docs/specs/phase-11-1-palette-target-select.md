---
title: "Phase 11.1 — 팔레트 삽입 대상 수동 선택"
date: 2026-06-22
status: active
---

# 목표

퀵 팔레트(⌥Space)에서 주입 대상 세션을 자동 감지 외에 수동으로도 변경할 수 있게 한다.
현재는 가장 최근 활성 Claude 세션이 자동 선택되는데, 여러 세션을 동시에 돌릴 때
원하는 세션을 직접 고르지 못해 불편하다.

# 현재 상태

- `PaletteViewModel.detectTarget(sessions)` — active > idle, Claude, lastActivity 최신 순으로 자동 선택
- 팔레트 footer: `[terminal] sessionName | [↩] 삽입 [⌘↩] 복사 [Esc] 닫기`
- 한번 열리면 대상을 바꿀 방법 없음

# 범위

**In:**
- Footer의 세션 표시를 클릭하면 세션 드롭다운 표시
- 드롭다운: Claude 세션 목록 (모든 상태 — active / idle / resting 모두 표시)
  - 각 행: 상태 컬러 점 + displayName + cwd (truncated)
  - 자동 선택된 항목에 체크마크
- 선택 후 footer에 새 대상 반영, 이후 ↩ 주입 시 선택한 세션에 삽입
- 팔레트를 닫고 다시 열면 자동 감지 초기화 (수동 선택 persist 안 함)

**Out:**
- 선택 persist (매번 열 때 자동 감지로 리셋)
- Gemini 세션 대상 선택 (Gemini iTerm 주입 미구현)
- 대상 없을 때 직접 iTerm 창 선택 UI

# UI / 동작

```
┌─────────────────────────────────────────────────────┐
│ 🔍 스킬·프롬프트 검색                                  │
├─────────────────────────────────────────────────────┤
│  /ultrawork        [Skills]            최근          │
│ ▶ /autopilot       [Skills]                          │
│  /code-review      [Skills]                          │
├─────────────────────────────────────────────────────┤
│ [⌥] airuncat ▼    [↩] 삽입  [⌘↩] 복사  [Esc] 닫기   │
└─────────────────────────────────────────────────────┘
              클릭 시 드롭다운:
              ┌────────────────────────────┐
              │ ● airuncat          active │
              │ ● clawde             idle  │
              │ ○ study-english    resting │
              └────────────────────────────┘
```

- `[⌥] airuncat ▼` — `[terminal] displayName [▼ chevron]` 형태 버튼
- 버튼 클릭 → `Menu { ForEach(sessions) }` (SwiftUI Menu or custom popover)
- 세션 없음 → `삽입 대상 없음` (기존과 동일, 드롭다운 없음)

# 데이터 흐름

## PaletteViewModel 변경

```swift
// 기존
@Published var targetSession: SessionInfo?
func detectTarget(_ sessions: [SessionInfo]) → SessionInfo?  // private

// 추가
@Published var availableSessions: [SessionInfo] = []  // Claude만, 모든 상태
var isTargetManual = false  // 수동 선택 여부 (UI hint용)

func selectTarget(_ session: SessionInfo)  // 수동 선택
```

`load(sessions:)` 에서:
1. `availableSessions = sessions.filter { $0.aiKind == .claude }` (정렬: lastActivity desc)
2. 기존 autoDetect 로직 유지

`selectTarget(_:)`:
- `targetSession = session`
- `isTargetManual = true`

## PaletteView 변경

footer의 세션 표시 버튼:
```swift
// 현재
if let session = vm.targetSession {
    Image(systemName: "terminal") + Text(session.displayName)
}

// 변경: SwiftUI Menu
Menu {
    ForEach(vm.availableSessions) { session in
        Button {
            vm.selectTarget(session)
        } label: {
            HStack {
                Circle().fill(statusColor(session)).frame(width:6)
                Text(session.displayName)
                Spacer()
                Text((session.cwd as NSString).lastPathComponent)
                    .foregroundColor(.secondary)
            }
        }
    }
} label: {
    HStack(spacing: 4) {
        Image(systemName: "terminal").font(.system(size: 10))
        Text(vm.targetSession?.displayName ?? "대상 없음")
            .font(.system(size: 10))
        if !vm.availableSessions.isEmpty {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
        }
    }
    .foregroundColor(.secondary)
}
.menuStyle(.borderlessButton)
.fixedSize()
```

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 세션 0개 | 드롭다운 숨김, "삽입 대상 없음" (기존) |
| 세션 1개 | 드롭다운 표시하되 선택지 1개 (체크마크 포함) |
| 수동 선택 세션이 다음 팔레트 open 시 사라진 경우 | 자동 감지 재실행 (isTargetManual 리셋) |
| resting 세션 선택 후 주입 | iTerm 탭 포커스 시도 → 실패 시 새 창에서 `claude -r` (ITermController 기존 동작) |

# 변경 파일

| 파일 | 변경 내용 |
|------|---------|
| `PaletteViewModel.swift` | `availableSessions`, `isTargetManual`, `selectTarget()` 추가 |
| `QuickPalette.swift` | footer에 SwiftUI Menu 추가, statusColor 헬퍼 |

# 검증

1. 세션 2개 이상 활성 → ⌥Space → footer 드롭다운 클릭 → 세션 변경 확인
2. 변경 후 ↩ → 선택한 세션 iTerm에 텍스트 삽입 확인
3. 팔레트 닫고 다시 열면 자동 감지로 리셋 확인
4. 세션 0개 → 드롭다운 없고 "삽입 대상 없음" 텍스트 유지 확인

# Next Action
- [x] Gemini 리뷰 (Step 2) — Gemini CLI auth 오류로 Claude 자체 리뷰로 대체
- [x] 사용자 승인 (Step 3)
- [x] 개발 (Step 4) — PaletteViewModel + QuickPalette 수정, 빌드 그린
- [x] 코드리뷰 (Step 5)
