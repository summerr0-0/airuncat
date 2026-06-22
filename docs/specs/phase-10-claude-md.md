---
title: "Phase 10 — CLAUDE.md 관리"
date: 2026-06-22
status: draft
---

# 목표

세션 행 옆에 CLAUDE.md 배지를 추가해 글로벌·프로젝트 CLAUDE.md를 빠르게 열람·열기할 수 있게 한다.
OMC가 CLAUDE.md를 컨텍스트 주입에 사용하듯, airuncat에서 현재 컨텍스트를 시각적으로 확인.

# 현재 상태

- 세션 행 우측: `[M N]` (Memory) + `[H N]` (Harness) + 태그 버튼
- CLAUDE.md 존재 여부 미표시, 내용 확인 불가

# 범위

**In:**
- `ClaudeMdInfo` 모델: globalPath, projectPath, globalExists, projectExists, wordCount, mtime
- `ClaudeMdScanner`: cwd 기준 `CLAUDE.md` / `.claude/CLAUDE.md` + 글로벌 `~/.claude/CLAUDE.md` 탐지
- Session 행 `[C]` 배지 — 프로젝트 CLAUDE.md 존재 시 표시, 클릭 → 팝오버
- `ClaudeMdPopoverView`: 파일 선택 탭(글로벌/프로젝트), 첫 20줄 미리보기, "에디터로 열기" + "Finder" 버튼
- `+ CLAUDE.md 생성` — 파일 없을 때 기본 템플릿으로 생성
- footer에 글로벌 CLAUDE.md 단어 수 표시 (컨텍스트 비대 경고: 500+ 단어 시 주황색)

**Out:**
- CLAUDE.md 인라인 편집 (외부 에디터 유도)
- AGENTS.md 탭 (Phase 10.1)
- CLAUDE.md 자동 생성 시 사용자 정의 템플릿

# 데이터 소스

| 파일 | 역할 |
|------|------|
| `~/.claude/CLAUDE.md` | 글로벌 — 모든 프로젝트 공통 컨텍스트 |
| `<cwd>/CLAUDE.md` | 프로젝트 루트 (Claude Code 우선 탐색) |
| `<cwd>/.claude/CLAUDE.md` | 프로젝트 `.claude/` 하위 (대안 위치) |

Claude Code는 `<cwd>/CLAUDE.md` 우선, 없으면 `<cwd>/.claude/CLAUDE.md` 탐색.
두 위치 모두 존재 가능 (팝오버에서 둘 다 표시).

# 모델

```swift
struct ClaudeMdEntry: Identifiable, Sendable {
    let id: String      // path (고유)
    let path: String
    let label: String   // "CLAUDE.md" 또는 ".claude/CLAUDE.md" 또는 "~/.claude/CLAUDE.md"
    let exists: Bool
    let wordCount: Int  // 팝오버 오픈 시 lazy 계산, badge prefetch 시 0
    let mtime: Date?    // exists=false 시 nil
}

struct ClaudeMdInfo: Sendable {
    let globalEntry: ClaudeMdEntry       // ~/.claude/CLAUDE.md
    let projectEntries: [ClaudeMdEntry]  // cwd 기준 발견된 파일들
    var projectExists: Bool { projectEntries.contains { $0.exists } }
}
```

`ClaudeMdInfo.globalWordCount` 제거 — `globalEntry.wordCount`로 대체 (팝오버 오픈 시 계산).

# ClaudeMdScanner

```swift
enum ClaudeMdScanner {
    static let globalPath: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/CLAUDE.md")

    // 빠른 존재 여부 체크 — 배지 prefetch용 (fileExists만, 파일 읽기 없음)
    static func exists(cwd: String) -> Bool

    // 전체 파싱 — 팝오버 오픈 시 호출 (priority: .userInitiated)
    // wordCount 포함한 full ClaudeMdInfo 반환
    static func scan(cwd: String) -> ClaudeMdInfo

    // 단어 수 계산 (공백 기준 분리, 파일 읽기)
    static func wordCount(path: String) -> Int
}
```

**배지 prefetch vs 팝오버 스캔 분리:**
- `.task` prefetch: `ClaudeMdScanner.exists(cwd:)` — `fileExists` 2회 호출만, wordCount 없음
- 팝오버 오픈: `ClaudeMdScanner.scan(cwd:)` — 전체 파싱 + wordCount 계산 (`priority: .userInitiated`)

# ClaudeMdPopoverView

```
[CLAUDE.md]  airuncat          [Finder 열기]
──────────────────────────────────
 탭: [글로벌] [프로젝트]
──────────────────────────────────
 ~/.claude/CLAUDE.md  (113줄 · 280단어)
 마지막 수정: 오늘
 ──────────
 # oh-my-claudecode - Intelligent...
 You are running with oh-my-claudecode...
 ...
 (첫 20줄)
──────────────────────────────────
 [에디터에서 열기]      [Finder에서 열기]
```

- 글로벌 CLAUDE.md: wordCount >= 500 → "컨텍스트가 큽니다 (\(N)단어)" 주황색 경고
- 프로젝트 CLAUDE.md 없을 때: "+ CLAUDE.md 생성" 버튼 표시
- 생성 기본 템플릿:
  ```markdown
  # 프로젝트 이름

  ## 역할

  ## 규칙
  ```
- 생성 후 탭 전환 + 미리보기 갱신

# Session 행 배지 통합

**배지 조회 패턴 (SessionInfo 비수정, wordCount 없음):**
```swift
@State private var claudeMdExists: Bool = false

.task(id: session.cwd) {
    let cwd = session.cwd
    let exists = await Task.detached(priority: .background) {
        ClaudeMdScanner.exists(cwd: cwd)   // fileExists만, 파일 읽기 없음
    }.value
    claudeMdExists = exists
}
```

**`[C]` 배지 표시 규칙:**
- 프로젝트 CLAUDE.md(root 또는 .claude/) 존재 시 표시
- 없어도 팝오버는 열 수 있음 (글로벌 탭 접근, 파일 생성 목적)
- 배지 없을 때 글로벌 접근: footer에 "G.md" 버튼 (항상 표시)

**배지 레이아웃 (기존 배지들 왼쪽에 추가):**
```
[C]  [M N]  [H N]  [태그]
```
- `[C]` = 너비 16pt 고정 (태그 버튼과 동일 크기로 줄임), opacity hidden when !exists
- 기존 레이아웃 너비 영향 최소화

# 수정/신규 파일

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/ClaudeMdScanner.swift` | 신규 |
| `Sources/airuncat/ClaudeMdPopoverView.swift` | 신규 |
| `Sources/airuncat/MenuContentView.swift` | Session 행 [C] 배지 추가, footer 글로벌 CLAUDE.md 단어 수 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 프로젝트 CLAUDE.md 없음 | `[C]` 배지 숨김, 팝오버 "없음 + 생성 버튼" |
| 글로벌 CLAUDE.md 없음 | 글로벌 탭에 "없음" 표시 |
| CLAUDE.md + .claude/CLAUDE.md 둘 다 존재 | 프로젝트 탭에 두 파일 모두 표시 |
| 파일 읽기 권한 없음 | 미리보기 빈 문자열, wordCount=0 |
| 500단어 이상 글로벌 | 주황색 경고 표시 |

# 검증 방법

1. `swift build` 통과
2. airuncat 재시작 → airuncat 프로젝트 세션 행에 `[C]` 배지 표시 확인
3. `[C]` 클릭 → 팝오버 열림, 글로벌/프로젝트 탭 전환 확인
4. 프로젝트 탭 → 미리보기 첫 20줄 표시 확인
5. "에디터에서 열기" → 기본 에디터에서 파일 열림
6. 글로벌 탭 → 단어 수 표시 확인
7. CLAUDE.md 없는 다른 프로젝트 → `[C]` 배지 미표시
