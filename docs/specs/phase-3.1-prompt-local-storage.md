---
title: "Phase 3.1 — Prompt Library 로컬 독립 저장"
date: 2026-06-14
status: draft
---

# 목표

Prompt Library의 데이터 소스를 Obsidian(`07_Prompts/PROMPT_*.md`)에서
`~/.airuncat/prompts/*.md`(앱 전용 로컬 디렉토리)로 완전히 이전한다.
Obsidian 설치 여부와 무관하게 프롬프트 CRUD가 앱 안에서 완결된다.

# 범위

**In:**
- 저장 경로 변경: `~/Obsidian/document/07_Prompts/` → `~/.airuncat/prompts/`
- 파일명 규칙 변경: `PROMPT_*.md` prefix 제거 → `*.md` (stem = ID)
- 1회성 마이그레이션: 기존 Obsidian PROMPT_*.md → 로컬 디렉토리로 복사
- 프롬프트 생성 UI (인라인 폼)
- 프롬프트 삭제 UI (2단계 확인, Skills 패턴 재사용)
- Finder 열기 버튼 (폴더 통째로, 편집은 외부 에디터에서)
- 핀 토글 (frontmatter `pinned` 필드 갱신)
- Obsidian 연동 코드 완전 제거

**Out:**
- 인앱 body 텍스트 편집기 (TextEditor 위젯) — Finder 열기로 대체
- 카테고리/태그 UI 편집 — 외부 에디터에서 frontmatter 직접 수정
- Obsidian-로컬 양쪽 소스 병합 모드

# 데이터

## 저장 위치
```
~/.airuncat/prompts/
  code-review.md
  git-commit.md
  ultrawork.md
  ...
```

## 파일 형식 (기존 frontmatter 스키마 유지)
```markdown
---
title: "코드 리뷰 체크리스트"
category: development
tags: [review, development]
pinned: true
---

다음 코드를 리뷰해줘...
```

## 마이그레이션 규칙
- 트리거: `~/.airuncat/prompts/` 디렉토리가 존재하지 않을 때 1회 자동 실행
- 소스: `~/Obsidian/document/07_Prompts/PROMPT_*.md`
- 변환: `PROMPT_code-review.md` → `code-review.md` (prefix strip, lowercase 유지)
- 충돌: 동일 stem 파일이 이미 있으면 skip
- Obsidian 원본은 건드리지 않음 (복사, 이동 아님)
- Obsidian 디렉토리가 없으면 마이그레이션 skip (빈 디렉토리 생성 후 종료)

# PromptRecord 변경

```swift
struct PromptRecord: Identifiable {
    let id: String        // file stem (e.g. "code-review")
    let title: String
    let tags: [String]
    let category: String
    var pinned: Bool
    let body: String
    let filePath: String  // 신규: ~/.airuncat/prompts/<id>.md (쓰기 연산용)
}
```

# 신규 파일: PromptManager.swift

SkillToggler 패턴으로 CRUD 담당.

```swift
enum PromptManager {
    static let promptsDir: String  // ~/.airuncat/prompts

    // 마이그레이션 (앱 첫 실행 시 PromptScanner.scan() 호출 전에 실행)
    static func migrateFromObsidianIfNeeded()

    // 생성: ~/.airuncat/prompts/<id>.md 원자적 쓰기
    static func createPrompt(id: String, title: String, category: String, body: String) -> String? // error

    // 삭제: removeItem
    static func deletePrompt(_ record: PromptRecord) -> String? // error

    // 핀 토글: frontmatter pinned 필드만 갱신 (파일 전체 재기록)
    static func togglePin(_ record: PromptRecord) -> String? // error
}
```

### createPrompt 동작
1. `id` 유효성: `[a-z0-9-]`, 1~40자, `^[a-z0-9]`, `[a-z0-9]$`, `--` 없음
2. `~/.airuncat/prompts/<id>.md` 존재 여부 확인 → 중복이면 error 반환
3. frontmatter 생성 (date: 오늘, tags: [], status 없음) → 원자적 쓰기
4. fileExists 재확인

### togglePin 동작
1. 파일 전체 읽기
2. frontmatter의 `pinned: true/false` 줄만 교체 (없으면 삽입)
3. 원자적 쓰기

# PromptScanner 변경

```swift
// 변경 전
static let promptsDir = "~/Obsidian/document/07_Prompts"
.filter { $0.hasPrefix("PROMPT_") && $0.hasSuffix(".md") }
id: stem  // "PROMPT_code-review"

// 변경 후
static let promptsDir = "~/.airuncat/prompts"  // PromptManager.promptsDir 공유
.filter { $0.hasSuffix(".md") }
id: stem  // "code-review"
filePath: ...  // 경로 추가
```

`scan()` 호출 전 `PromptManager.migrateFromObsidianIfNeeded()` 실행.

# PromptLibraryView 변경

## bottomBar 추가 버튼
```
[Finder 열기]  [+ 추가]  [새로고침]
```

- **Finder 열기**: `NSWorkspace.shared.open(URL(fileURLWithPath: PromptManager.promptsDir))`
- **+ 추가**: `showCreateForm` 토글 (Skills bottomBar 패턴 재사용)

## 생성 폼 (인라인, 스크롤뷰 하단)
```
──────────────────────────────────────
[ID:    ________________________]   ← kebab-case (실시간 sanitize)
[제목:  ________________________]
[카테고리: ____________________]
[내용:  ________________________]   ← TextField (한 줄, 짧은 프롬프트 기준)
연결:  [핀 ☐]
[취소]                 [생성]
──────────────────────────────────────
```

> body는 한 줄 TextField. 긴 body는 Finder 열어서 에디터로 편집 유도.

## 삭제 UI (SkillRow 패턴 재사용)
- 호버 시 우측 trash 버튼 노출
- 클릭 → 행 내부 빨간 확인 배너
- 2단계 확인 후 `PromptManager.deletePrompt()` 호출 → 목록에서 즉시 제거

## 핀 토글
- PromptRow의 핀 인디케이터(📌 → 핀 텍스트/아이콘) 클릭
- `PromptManager.togglePin()` 호출 → 로컬 `prompts` 배열 즉시 갱신 (reload 없이)

# 수정 파일 목록

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/PromptScanner.swift` | promptsDir 교체, PROMPT_ prefix 제거, filePath 필드 추가 |
| `Sources/airuncat/PromptLibraryView.swift` | Finder 버튼, 생성 폼, 삭제 UI, 핀 토글 |
| `Sources/airuncat/PromptManager.swift` | 신규: migrate / create / delete / togglePin |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| `~/.airuncat/prompts/` 없음 (첫 실행) | migrate가 자동 생성 |
| Obsidian 경로 없음 | migrate skip, 빈 디렉토리 생성 |
| 마이그레이션 중 동일 stem 충돌 | skip (기존 로컬 파일 우선) |
| ID 중복 | 생성 버튼 비활성화 + "이미 존재하는 프롬프트" |
| 빈 body | 허용 (Finder에서 나중에 편집) |
| togglePin 파일 없음 | error 표시, 목록 reload |
| deletePrompt 파일 없음 | error 표시 (이미 없으므로 목록에서 제거는 진행) |

# 검증 방법

1. `swift build` 통과
2. 앱 재시작 → Prompts 탭에 기존 Obsidian 3개 프롬프트 자동 표시
3. `~/.airuncat/prompts/` 디렉토리 + 3개 파일 확인 (PROMPT_ prefix 없음)
4. `+ 추가` → ID `test-prompt`, 제목 `테스트`, 카테고리 `dev`, body `hello` → 생성
   - `~/.airuncat/prompts/test-prompt.md` 생성 확인
   - 목록에 즉시 표시
5. Finder 열기 → `~/.airuncat/prompts/` 폴더 열림 확인
6. 핀 아이콘 클릭 → pinned 반전, 파일 frontmatter 갱신 확인
7. 생성한 프롬프트 호버 → 삭제 → 2단계 확인 → 목록에서 제거 + 파일 삭제 확인
8. Obsidian `07_Prompts/` 원본 파일 무결성 확인 (건드리지 않았어야 함)
