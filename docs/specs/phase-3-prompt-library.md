---
title: "Phase 3 — Prompt Library spec"
date: 2026-06-13
status: complete
---

# 목표

재사용 프롬프트를 파일로 저장하고, 메뉴바 앱에서 한 클릭으로 클립보드에 복사하거나
활성 iTerm 탭에 바로 붙여넣는다. OMC의 스킬 기반 프롬프트 재사용을 독립 라이브러리로
대체하며, Obsidian 파일을 단일 진실 소스로 쓴다.

# 범위

**In:**
- 저장소: `~/Obsidian/document/07_Prompts/PROMPT_*.md` (파일 1개 = 프롬프트 1개)
- frontmatter 스키마: `title`, `tags`, `category`, `shortcut`, `pinned`
- 드롭다운에 **Prompts 탭** 추가 (Sessions / Skills / Prompts 3탭)
- 프롬프트 목록: 핀 고정 섹션 + 카테고리별 그룹
- 검색 필터 (title, tags 대상)
- 클립보드 복사 버튼 (1초 체크 피드백)
- 삽입 버튼: 클립보드 write 후 Cmd+V (AppleScript) — `write text`의 자동 실행 방지

**Out:**
- 새 프롬프트 파일 생성 (Obsidian에서 직접)
- 프롬프트 내용 편집 (앱 안에서)
- 카테고리 계층 구조 (1레벨만)
- `~/.claude/commands/` 링크 생성 — 프롬프트는 스킬이 아님
- 삽입 시 커서 위치 제어 (단순히 텍스트를 iTerm에 keystroke)

# 동작 / UI

## 탭 구조

```
[Sessions] [Skills] [Prompts]
```

기존 TabButton 컴포넌트 재사용. 탭 추가 시 `selectedTab` enum에 `.prompts` 케이스 추가.

## Prompts 탭 레이아웃

```
[ Search prompts...                    ]  ← 검색창

[pin] Ultrawork 시작                   [▷] [⎘]
[pin] Code review 체크리스트            [▷] [⎘]

── development (3) ──────────────────
      Git 커밋 메시지 작성               [⎘]
      PR 설명 템플릿                     [⎘]
      N+1 쿼리 분석 요청                 [⎘]

── workflow (2) ──────────────────────
      Daily standup 정리                [⎘]
      스펙 작성 가이드                   [⎘]
```

- `[▷]` : 가장 최근 활성(working) 세션의 iTerm 탭에 삽입. 탭 헤더에 "Insert to: <세션명>" 표시.
  활성 세션 없으면 버튼 숨김.
- `[⎘]` : 클립보드 복사 (클릭 후 1초간 체크 아이콘으로 전환, Task 저장 + cancel로 중복 방지)
- 핀 고정 항목은 카테고리와 무관하게 최상단 고정 (검색 중에도 matching 핀 항목은 최상단 유지)
- 카테고리 없는 항목은 "기타" 그룹에 묶음
- `maxHeight: 360`, ScrollView
- `shortcut` 필드: 첫 구현에서 표시 생략 (Out으로 이동)

## 프롬프트 파일 형식

```markdown
---
title: "Ultrawork 시작"
tags: [workflow, OMC]
category: workflow
shortcut: "ulw"
pinned: true
---

/oh-my-claudecode:ultrawork
```

- frontmatter 없는 파일 → title = 파일명 stem, category = "기타", pinned = false
- body = frontmatter 아래 전체 텍스트 (모든 공백/줄바꿈 유지)

## 삽입 동작

삽입 대상: `SessionStore.sessions.first { $0.workState != .resting }` — 가장 최근 활성 세션.
탭 상단에 "Insert to: <cwd 마지막 컴포넌트>" 로 대상을 명시.

구현:
1. 활성 세션 없으면 `[▷]` 숨김
2. 클릭 → `ITermController.insertText(_:cwd:)` 호출
3. AppleScript 흐름:
   a. `NSPasteboard`에 텍스트 write (기존 클립보드 내용은 복원 안 함 — 단순화)
   b. 해당 세션 탭 activate (기존 `focusSession` 로직 재사용)
   c. `keystroke "v" using command down` — Cmd+V로 붙여넣기 (자동 실행 없음)
4. 삽입 성공 → 드롭다운 닫기, 실패 → 인라인 에러 텍스트

**주의:** `write text "..."` 는 사용하지 않는다. iTerm2에서 Enter가 자동 입력되어 즉시 실행됨.

## 복사 피드백

```swift
@State private var copied = false
@State private var copyTask: Task<Void, Never>? = nil

// 클릭 시 (중복 타이머 방지):
NSPasteboard.general.setString(prompt.body, forType: .string)
copied = true
copyTask?.cancel()
copyTask = Task {
    try? await Task.sleep(for: .seconds(1))
    copied = false
}
```

아이콘: `doc.on.doc` (평상시) → `checkmark` (1초)

# 데이터 소스 / 의존

| 소스 | 경로 | 접근 |
|------|------|------|
| 프롬프트 파일 | `~/Obsidian/document/07_Prompts/PROMPT_*.md` | FileManager glob |
| frontmatter 파싱 | YAML front matter (`---`) | 직접 파싱 (외부 의존 없음) |
| iTerm 삽입 | AppleScript keystroke | ITermController 확장 |
| 클립보드 | NSPasteboard | 직접 호출 |

## frontmatter 파싱 전략

외부 YAML 라이브러리 도입 없이 직접 파싱:

```swift
// "---\n...\n---\n<body>" 형태 지원
func parseFrontmatter(_ text: String) -> (meta: [String: Any], body: String)
```

- 지원 타입: String, Bool(`"true"/"false"`), [String]
- 배열 두 형식 모두 지원 (Obsidian 기본은 block sequence):
  - Flow: `tags: [workflow, OMC]`
  - Block: `tags:\n  - workflow\n  - OMC`
- 파싱 실패 시 빈 메타 + 전체 텍스트를 body로 사용

# 신규 파일 목록

| 파일 | 역할 |
|------|------|
| `PromptScanner.swift` | 07_Prompts 디렉토리 스캔 + frontmatter 파싱 |
| `PromptLibraryView.swift` | Prompts 탭 SwiftUI 뷰 (목록, 검색, 복사/삽입) |

## ITermController 확장 (기존 파일)

```swift
static func insertText(_ text: String, cwd: String) -> Bool
// 1. NSPasteboard에 text write
// 2. 기존 focusSession(cwd:) 로직으로 탭 activate
// 3. keystroke "v" using {command down}  -- Cmd+V 붙여넣기
// write text 미사용 (자동 Enter 실행 위험)
```

# 엣지케이스

- `07_Prompts/` 디렉토리 없거나 파일 0개 → emptyState "PROMPT_*.md 파일을 추가하세요" 안내
- frontmatter YAML 파싱 실패 → 파일명 stem을 title로, body = 전체 파일 내용
- 삽입 대상 세션 없음 (활성 세션 없음) → `[▷]` 버튼 전체 숨김, [⎘]만 표시
- 긴 텍스트 → 클립보드+Cmd+V 방식이라 길이에 무관하게 빠름 (keystroke 미사용)
- 파일 추가/삭제 감지: 탭 전환 시 매번 재스캔 (HarnessScanner 동일 패턴)
- 클립보드 충돌: 삽입 시 기존 클립보드 내용은 덮어씀 — 사용자에게 고지 (툴팁 또는 별도 안내 없음, 단순화)

# 검증 방법

1. `swift build` 통과
2. `~/Obsidian/document/07_Prompts/PROMPT_test.md` 생성 후 `/run-clawde` → Prompts 탭에 표시 확인
3. 검색어 입력 → 필터 동작 확인
4. [⎘] 클릭 → 클립보드에 body 복사 + 체크 피드백 확인
5. 활성 세션 선택 후 [▷] 클릭 → iTerm 탭에 텍스트 입력 확인
6. `07_Prompts/` 없는 환경 → 안내 메시지 표시 확인

# 미해결 질문

- **[결정됨]** 삽입 방식: 클립보드 write → Cmd+V (keystroke 미사용, 자동 실행 방지)
- **[결정됨]** 삽입 대상: 가장 최근 활성 세션 자동 선택, Prompts 탭 상단에 표시
- **[결정됨]** shortcut 표시: 첫 구현에서 생략, Phase 3.5 이후로 연기
- **[미결]** 3탭 너비: 빌드 후 실측 확인. 좁으면 탭 라벨 단축 ("Prompts" → "Prompt")
