---
title: "Phase 9 — 설정 패널 (Permissions + Hook 삭제)"
date: 2026-06-22
status: draft
---

# 목표

Harness 팝오버에 **Permissions** 섹션을 추가하고, Hook 실제 삭제(현재는 `_disabledHooks` 이동만)를 지원한다.
`settings.json`의 `permissions.allow` / `permissions.deny` 배열을 GUI에서 CRUD할 수 있게 한다.

# 현재 상태

- `HarnessScanner`: `settings.json`에서 `hooks` / `_disabledHooks` 파싱 → `HookEntry[]`
- `HarnessManager.toggle`: hook을 `hooks` ↔ `_disabledHooks` 간 이동 (실제 삭제 없음)
- `HarnessPopoverView`: hook 토글 UI + `settings.json` 열기 링크
- `permissions` 키 미파싱

# 범위

**In:**
- `PermissionEntry` 모델: pattern(String), kind(allow/deny), scope(global/project)
- `HarnessScanner`: `permissions.allow` / `permissions.deny` 파싱 추가
- `HarnessInfo`: `permissions: [PermissionEntry]` 추가
- `HarnessManager`:
  - `addPermission(pattern:kind:to:)` — 배열 추가 + atomic write
  - `removePermission(_:from:)` — 배열 제거 + atomic write
  - `deleteHook(hook:from:)` — `_disabledHooks`에서 완전 제거 (disabled 상태에서만 삭제)
- `HarnessPopoverView`: Permissions 섹션 추가 (hook 섹션 하단), `maxHeight: 480`으로 증가

**Out:**
- Hook 직접 생성 (command/matcher 폼) — 너무 복잡, 다음 phase
- `hooks` 키의 enabled hook 즉시 삭제 (toggle → disabled → delete 2단계 권장)
- 글로벌 vs 프로젝트 permissions 비교 뷰
- `autoUpdates`/`theme` 등 기타 설정 키 편집

# 모델

```swift
enum PermissionKind: String { case allow, deny }

struct PermissionEntry: Identifiable, Sendable {
    let id: String    // "\(kind.rawValue):\(pattern)" — allow/deny 양쪽에 동일 pattern 허용
    let pattern: String
    let kind: PermissionKind
}
```

# HarnessScanner 변경

```swift
// HarnessInfo에 추가:
var permissions: [PermissionEntry]

// scanPermissions 추가:
private static func scanPermissions(settingsPath: String) -> [PermissionEntry] {
    // json["permissions"]["allow"] → PermissionEntry(kind: .allow)
    // json["permissions"]["deny"]  → PermissionEntry(kind: .deny)
    // allow 먼저, 각 그룹 내 알파벳순
}
```

# HarnessManager 변경

```swift
// Permission 추가 (중복 불허: 같은 kind에 동일 pattern이면 에러)
static func addPermission(pattern: String, kind: PermissionKind, in info: HarnessInfo) -> HarnessInfo

// Permission 제거
static func removePermission(_ entry: PermissionEntry, in info: HarnessInfo) -> HarnessInfo

// Hook 완전 삭제 (disabled 상태인 hook만 허용)
// extractGroup(_:from:key:"_disabledHooks":event:) 호출 후 insertGroup 없이 writeJSON
// toggle과 달리 insert 단계 없음 — extract-only 경로
static func deleteHook(hook: HookEntry, in info: HarnessInfo) -> HarnessInfo
```

**패턴:** 기존 `toggle`과 동일 — 성공/실패 모두 `HarnessInfo` 반환, `writeError` 필드로 에러 전달.
mtime race condition guard 유지.

**`addPermission` 신규 중첩 키 생성:**
```swift
// json["permissions"] 없을 때:
var permissions = json["permissions"] as? [String: Any] ?? [:]
var list = permissions[kind.rawValue] as? [String] ?? []
list.append(pattern)
permissions[kind.rawValue] = list
json["permissions"] = permissions
// writeJSON으로 atomic write
```
`permissions` 키가 없으면 신규 생성, 있으면 업데이트.

# HarnessPopoverView 변경

```
[rules] (4)  ...
──────────────────
[hooks] (3)  2 활성
  ● PostToolUse · Edit|Write  swift build ...
  ● PreToolUse  · Edit|Write  BLOCKED: ...
  ○ PostToolUse · **/* ...    [비활성 → 활성] [삭제]
──────────────────
[permissions] (6)  allow(6) deny(0)
  ✓ Bash(swift *)            [삭제]
  ✓ Bash(./build.sh)         [삭제]
  ...
  ⊘ (deny 없음)
──────────────────
[+ permission]
이름:  [Bash(npm *)  ]  [allow ●] [deny ○]
[취소]                             [추가]
──────────────────
[+ 새 Rule]  [settings.json]  [OMC 비활성]
```

**Hooks 섹션 변경:**
- disabled hook(`enabled: false`) hover 시 `[삭제]` 버튼 추가
- `[삭제]` 클릭 → 즉시 삭제 (2단계 확인 없음 — disabled 이미 비활성이므로)

**Permissions 섹션 (신규):**
- allow 항목: `✓` 녹색 아이콘 + pattern + hover → `[삭제]`
- deny 항목: `⊘` 빨간 아이콘 + pattern + hover → `[삭제]`
- 비어 있으면 "(없음)" 표시
- 하단 인라인 생성 폼 (토글 버튼으로 show/hide)

# 수정/신규 파일

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/HarnessScanner.swift` | `PermissionEntry` 모델, `HarnessInfo.permissions`, `scanPermissions` |
| `Sources/airuncat/HarnessManager.swift` | `addPermission`, `removePermission`, `deleteHook` |
| `Sources/airuncat/HarnessPopoverView.swift` | Permissions 섹션 + 생성 폼, disabled hook 삭제 버튼 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| `permissions` 키 없음 | 빈 배열, 섹션 표시 (추가는 가능) |
| 중복 pattern 추가 (같은 kind) | "이미 존재: \(pattern)" 에러 배너 |
| enabled hook 삭제 시도 | 버튼 미노출 (disabled hook만 삭제 허용) |
| `settings.json` 없음 | addPermission 시 신규 생성 |
| mtime race | 기존 toggle 패턴과 동일 — "외부에서 변경됨" 에러 |

# 검증 방법

1. `swift build` 통과
2. Harness 팝오버 → Permissions 섹션에 현재 `allow` 목록 표시 확인
3. `+ permission` → `Bash(echo *)`, allow → 추가 → `settings.json` 확인
4. 추가된 항목 `[삭제]` → 제거 확인
5. disabled hook hover → `[삭제]` 표시 → 클릭 → 목록에서 제거 + `settings.json` 확인
6. enabled hook에는 `[삭제]` 미노출 확인
7. 중복 pattern 추가 → 에러 배너 확인
