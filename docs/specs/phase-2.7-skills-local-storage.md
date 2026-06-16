---
title: "Phase 2.7 — Skills 로컬 독립 저장"
date: 2026-06-16
status: draft
---

# 목표

스킬 원본 파일 저장소를 Obsidian(`06_AI_Config/SKILL_*.md`)에서
`~/.airuncat/skills/SKILL_*.md`(앱 전용 로컬)로 이전한다.
Phase 3.1(프롬프트 로컬화)과 동일한 패턴. Obsidian 설치 여부와 무관하게
스킬 CRUD가 앱 안에서 완결되고, OMC 제거 이후에도 스킬이 유지된다.

또한 자주 쓰는 OMC 스킬들을 개인 스킬로 추가해
airuncat Skills 탭에서 직접 관리·주입할 수 있게 한다.

# 범위

**In:**
- 저장 경로 변경: `~/Obsidian/document/06_AI_Config/SKILL_*.md` → `~/.airuncat/skills/SKILL_*.md`
- 1회성 마이그레이션: 기존 Obsidian SKILL_*.md → 로컬 디렉토리로 복사 (원본 유지)
- `SkillScanner.obsidianBase` → `SkillManager.skillsDir` 교체
- `SkillManager.swift` 신규: migrate / skillsDir 상수 (create/delete는 이미 `SkillToggler`에 있음)
- `SkillToggler.swift`: 파일 생성 경로를 `SkillManager.skillsDir`로 교체
- Obsidian 의존 완전 제거 (`obsidianBase`, `obsidianPath` 필드)
- OMC 유용 스킬 추가 (아래 목록)

**Out:**
- `SkillToggler`의 create/delete 로직 재작성 (경로 교체만)
- 심볼릭링크 방식 변경 (기존 그대로)
- Obsidian 원본 파일 삭제 (복사만, 원본 유지)

# 데이터

## 새 저장 위치
```
~/.airuncat/skills/
  SKILL_ARCHITECT.md
  SKILL_CONVERT_TSV.md
  SKILL_DAILY_VOCAB.md
  SKILL_EPUB_REWRITE.md
  SKILL_EXPERIENCE_EXTRACTOR.md
  SKILL_ULTRAWORK.md          ← OMC 스킬 추가
  SKILL_AUTOPILOT.md
  SKILL_CODE_REVIEW.md
  ...
```

## 마이그레이션 규칙
- 트리거: `~/.airuncat/skills/` 디렉토리가 존재하지 않을 때 1회 자동 실행
- 소스: `~/Obsidian/document/06_AI_Config/SKILL_*.md`
- 변환: 파일명 그대로 복사 (`SKILL_FOO.md` → `SKILL_FOO.md`)
- 충돌: 동일 파일이 이미 있으면 skip
- Obsidian 원본은 건드리지 않음 (복사, 이동 아님)
- Obsidian 디렉토리 없으면 마이그레이션 skip (빈 디렉토리 생성 후 종료)

# SkillRecord 변경

```swift
// 변경 전
struct SkillRecord {
    let obsidianPath: String   // ~/Obsidian/document/06_AI_Config/SKILL_*.md
    ...
}

// 변경 후
struct SkillRecord {
    let sourcePath: String     // ~/.airuncat/skills/SKILL_*.md
    ...
}
```

# 신규 파일: SkillManager.swift

Phase 3.1의 `PromptManager` 패턴과 동일.

```swift
enum SkillManager {
    static let skillsDir: String  // ~/.airuncat/skills

    // 1회성 마이그레이션
    static func migrateFromObsidianIfNeeded()
}
```

create/delete 는 기존 `SkillToggler`에 이미 구현됨 — 경로만 `skillsDir`로 교체.

# SkillScanner 변경

```swift
// 변경 전
static let obsidianBase = "~/Obsidian/document/06_AI_Config"
// scan(): contentsOfDirectory(obsidianBase) 후 SKILL_*.md 필터

// 변경 후
static let skillsDir = SkillManager.skillsDir  // ~/.airuncat/skills
// scan(): contentsOfDirectory(skillsDir) 후 SKILL_*.md 필터
// scan() 첫 줄에 SkillManager.migrateFromObsidianIfNeeded() 호출
```

# SkillToggler 변경

`createSkill` 에서 파일 생성 경로:
```swift
// 변경 전
let path = (SkillScanner.obsidianBase as NSString).appendingPathComponent("SKILL_\(name).md")

// 변경 후
let path = (SkillManager.skillsDir as NSString).appendingPathComponent("SKILL_\(name).md")
```

# 추가할 OMC 스킬 목록

기존 SKILL_*.md 스타일로 `~/.airuncat/skills/`에 직접 생성.
Claude/Gemini 링크는 앱 Skills 탭에서 수동 토글.

| 파일명 | 슬래시커맨드 | 용도 |
|--------|------------|------|
| `SKILL_ULTRAWORK.md` | `/ultrawork` | 고강도 집중 작업 모드 |
| `SKILL_AUTOPILOT.md` | `/autopilot` | 자율 실행 모드 |
| `SKILL_RALPH.md` | `/ralph` | 반복 자율 루프 |
| `SKILL_RALPLAN.md` | `/ralplan` | 계획 수립 + ralph 실행 |
| `SKILL_DEEP_INTERVIEW.md` | `/deep-interview` | 요구사항 인터뷰 |
| `SKILL_CODE_REVIEW.md` | `/code-review` | 코드 리뷰 |
| `SKILL_COMMIT.md` | `/commit` | 커밋 생성 |
| `SKILL_ASK.md` | `/ask` | Gemini 교차검토 |
| `SKILL_REMEMBER.md` | `/remember` | 메모리 저장 |
| `SKILL_AI_SLOP_CLEANER.md` | `/ai-slop-cleaner` | AI 슬롭 정리 |

각 스킬 파일 형식:
```markdown
---
description: "한 줄 설명"
---

# /skill-name

(기존 OMC 스킬 본문 또는 짧은 지시문)
```

> OMC 플러그인에 이미 설치된 스킬들(`~/.claude/plugins/cache/omc/.../commands/`)은
> 본문을 그대로 복사하거나 해당 스킬로 위임하는 wrapper를 써도 됨.

# 수정 파일 목록

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/SkillManager.swift` | 신규: skillsDir 상수 + migrateFromObsidianIfNeeded |
| `Sources/airuncat/SkillScanner.swift` | obsidianBase → skillsDir, migrate 호출, obsidianPath → sourcePath |
| `Sources/airuncat/SkillToggler.swift` | createSkill 경로 교체 |
| `Sources/airuncat/SkillsView.swift` | obsidianPath 참조 제거 (있다면) |
| `CLAUDE.md` | 스킬 원본 경로 업데이트 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| `~/.airuncat/skills/` 없음 (첫 실행) | migrate가 자동 생성 |
| Obsidian 경로 없음 | migrate skip, 빈 디렉토리 생성 |
| 동일 stem 충돌 | skip (기존 로컬 파일 우선) |
| 기존 심볼릭링크 (Obsidian 원본 가리킴) | 링크 대상이 바뀌므로 broken으로 표시됨 → [수리] 버튼으로 일괄 재생성 |
| createSkill 후 경로 | `~/.airuncat/skills/SKILL_*.md`에 정상 생성 |

> 중요: 마이그레이션 후 기존 Claude/Gemini 심볼릭링크는 여전히 Obsidian 경로를 가리킴.
> 링크 대상 파일은 Obsidian에 그대로 있으므로 **linked 상태 유지**, broken 없음.
> 이후 스킬 편집/재생성 시 새 경로(`~/.airuncat/skills/`)로 링크가 교체됨.

# 검증 방법

1. `swift build` 통과
2. 앱 재시작 → Skills 탭에 기존 5개 스킬 표시
3. `~/.airuncat/skills/` 디렉토리 + `SKILL_*.md` 5개 파일 확인
4. Claude 링크 3개 상태 `linked` 유지 확인
5. `+ 추가` → 새 스킬 생성 → `~/.airuncat/skills/SKILL_NEW.md` 생성 확인
6. 생성한 스킬 C 배지 토글 → `~/.claude/commands/new.md` 심볼릭링크 생성 확인
7. 삭제 → `~/.airuncat/skills/SKILL_NEW.md` 삭제 확인
8. Obsidian `06_AI_Config/` 원본 파일 무결성 확인
