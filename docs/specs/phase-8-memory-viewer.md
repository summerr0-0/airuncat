---
title: "Phase 8 — Memory 뷰어"
date: 2026-06-22
status: draft
---

# 목표

OMC auto-memory(`~/.claude/projects/*/memory/`)를 세션 행에서 바로 열람·삭제할 수 있게 한다.
현재 세션의 프로젝트에 쌓인 기억이 무엇인지 확인하고 오래된 항목을 정리하는 용도.

# 데이터 소스

- **메모리 디렉토리:** `<sessionJsonlPath>/../memory/`
  - jsonl 경로에서 직접 유도 (`deletingLastPathComponent() + "/memory"`)
  - cwd 인코딩 재구현 금지 — 인코딩 규칙이 Claude Code 내부 구현에 의존하므로 취약
- **인덱스:** `memory/MEMORY.md` — `- [Title](filename.md) — description` 형식
- **개별 파일:** `memory/*.md` — YAML frontmatter 포함
  ```yaml
  ---
  name: project-airuncat
  description: airuncat 프로젝트 현황
  metadata:
    type: project   # user | feedback | project | reference
    node_type: memory
    originSessionId: <uuid>
  ---
  ```

# 범위

**In:**
- `MemoryRecord: Sendable` 모델: name, description, type, path, mtime
- `MemoryScanner`: jsonl 디렉토리 → memory/*.md 파싱 (nested `metadata.type` 추출)
- `MemoryManager`: delete (파일 삭제 + MEMORY.md 인덱스 줄 제거, atomic)
- Session 행에 **memory 배지** 추가 (기억 개수, 클릭 시 팝오버)
  - 배지 카운트: Harness prefetch `.task` 패턴으로 비동기 조회 (SessionInfo 비오염)
- `MemoryPopoverView`: type별 그룹, 행 클릭 → 미리보기, Finder 열기, 삭제

**Out:**
- Memory 파일 생성·편집
- All-projects 통합 뷰 (Phase 8.1)
- `originSessionId` 기반 세션 재개 연동

# 모델

```swift
enum MemoryType: String, Sendable {
    case user, feedback, project, reference, unknown
}

struct MemoryRecord: Identifiable, Sendable {
    let id: String          // name (frontmatter) 또는 파일 stem
    let description: String
    let type: MemoryType
    let path: String
    let mtime: Date
}
```

# MemoryScanner

```swift
enum MemoryScanner {
    // jsonlPath: 세션 jsonl 파일 경로
    // 예: ~/.claude/projects/-Users-…/sessionId.jsonl
    // → memoryDir = 같은 디렉토리 + "/memory"
    static func memoryDir(forJsonl jsonlPath: String) -> String {
        let parent = (jsonlPath as NSString).deletingLastPathComponent
        return (parent as NSString).appendingPathComponent("memory")
    }

    // 메모리 디렉토리 파일 수 (MEMORY.md 제외) — 배지 카운트용
    static func count(forJsonl jsonlPath: String) -> Int

    // 전체 파싱 — 팝오버 오픈 시 호출 (priority: .userInitiated)
    static func scan(forJsonl jsonlPath: String) -> [MemoryRecord]

    // 프론트매터 파싱: name, description, metadata.type 추출
    // metadata는 nested 키이므로 YAML 파서 없이 indented line 탐색
    // "  type:" 줄을 metadata 블록 내에서 탐지
    private static func parseRecord(path: String) -> MemoryRecord?
}
```

**YAML 파싱 전략 (외부 파서 없이):**
```
frontmatter 범위: 파일 첫 줄 "---" ~ 다음 "---"
name: 최상위 "name: " 값
description: 최상위 "description: " 값
metadata.type:
  "metadata:" 줄 이후 "  type: " 형태 (2칸 들여쓰기)로 탐색
  없으면 최상위 "type: " fallback
```

# MemoryManager

```swift
enum MemoryManager {
    // 1. 파일 삭제 (FileManager.removeItem)
    // 2. MEMORY.md에서 해당 파일명을 포함하는 줄 제거 (atomic write)
    //    anchored match: "](\(filename))" 형식으로 정확히 링크 타겟만 매칭
    static func delete(_ record: MemoryRecord, memoryDir: String) -> String?
}
```

MEMORY.md 줄 제거 (anchored):
```swift
let filename = (record.path as NSString).lastPathComponent
lines.filter { !$0.contains("](\(filename))") }
// "](" 앵커로 description 텍스트의 우연한 파일명 언급과 구분
```

# Session 행 Memory 배지 통합

**배지 카운트 조회 패턴 (SessionInfo 비오염):**
```swift
// SessionRowView (또는 sessionRow 내부)
@State private var memoryCount: Int = 0

.task(id: session.jsonlPath) {
    let count = await Task.detached(priority: .background) {
        MemoryScanner.count(forJsonl: session.jsonlPath)
    }.value
    memoryCount = count
}
```

**배지 레이아웃 (기존 Harness 배지 옆):**
```
[M N]  — width: 36pt 고정, 0개면 hidden
[H N]  — 기존 Harness 배지
```
메모리 배지가 Harness 배지 왼쪽에 위치. 둘 다 hidden이면 공간 미점유.

**MemoryBadgeButton: `HarnessBadgeButton`과 동일 NSViewRepresentable 구조**
- tap 시 `Task.detached(priority: .userInitiated)` 비동기 전체 스캔
- 팝오버 오픈 전 `scanning` guard (double-tap 방지)

# MemoryPopoverView

```
[Memory]  airuncat (6개)              [Finder 열기]
──────────────────────────────────────
  [user] 1개
    * user-role    5년차 풀스택 개발자   5일 전  [⌘] [🗑]
  [feedback] 3개
    * feedback-testing   통합 테스트 강제   오늘  [⌘] [🗑]
    ...
──────────────────────────────────────
                               [새로고침]
```

- type 순서: user → feedback → project → reference → unknown
- 행 클릭 → 미리보기 토글 (첫 5줄, RuleRow 패턴 동일)
- `[⌘]` Finder 열기, `[🗑]` 2단계 삭제
- 삭제 후 재스캔 + `memoryCount` 갱신 (Binding 전달)
- 팝오버 너비 280pt (RuleRow 팝오버와 동일)

# 수정/신규 파일

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/MemoryScanner.swift` | 신규 |
| `Sources/airuncat/MemoryManager.swift` | 신규 |
| `Sources/airuncat/MemoryPopoverView.swift` | 신규 |
| `Sources/airuncat/MenuContentView.swift` | Session 행에 MemoryBadgeButton 추가 (memory 배지) |

**SessionInfo 미수정** — `memoryCount`는 행 로컬 `@State`로 관리.

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| memory 디렉토리 없음 | 배지 숨김, 팝오버 "메모리 없음" 표시 |
| MEMORY.md 없거나 파싱 실패 | 개별 파일만 나열, 삭제 시 인덱스 제거 스킵 |
| frontmatter 없는 파일 | `id=stem`, `description=""`, `type=.unknown` |
| metadata.type 없음 | 최상위 `type:` fallback, 없으면 `.unknown` |
| 같은 cwd 여러 세션 | jsonl → 같은 memoryDir → 동일 팝오버 (정상) |
| MEMORY.md에 해당 파일 링크 없음 | 파일만 삭제, 인덱스 제거 no-op |

# 검증 방법

1. `swift build` 통과
2. airuncat 재시작 → 현재 세션 행에 `[M N]` 배지 표시 확인
3. 배지 클릭 → 팝오버에 type별 그룹 확인 (user / feedback / project)
4. 행 클릭 → 미리보기 토글 확인 (frontmatter 아닌 본문 5줄)
5. `[⌘]` 클릭 → Finder에서 파일 열림
6. `[🗑]` → 2단계 확인 → 삭제 → 팝오버 목록 갱신, 배지 카운트 감소
7. 메모리 없는 프로젝트 → 배지 미표시
8. `~/.claude/projects/-Users-jeong-ilin/memory/` 같은 다른 프로젝트의 배지도 표시 확인
