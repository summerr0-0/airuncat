---
title: "Phase 2 — Skills Manager spec"
date: 2026-06-11
status: pending-approval
---

# 목표

`~/Obsidian/document/06_AI_Config/SKILL_*.md` 를 단일 소스로, `~/.claude/commands/` 와
`~/.gemini/commands/` 의 심볼릭 링크 상태를 한눈에 관제하고 on/off 토글로 관리하는
Skills Manager 패널을 메뉴바 앱에 추가한다.

현재 링크 생성·수리는 터미널에서 수동(`ln -sf`)으로 해야 한다. 깨진 링크와
Gemini 누락(현재 8개)을 시각적으로 파악하고 클릭 한 번으로 고칠 수 있게 한다.

# 범위

**In:**
- Obsidian `06_AI_Config/SKILL_*.md` 스캔 + frontmatter(`name`, `description`) 파싱
- `~/.claude/commands/` 링크 상태 조회 (linked / broken / unlinked)
- `~/.gemini/commands/` 링크 상태 조회 (linked / broken / unlinked)
- 스킬 on/off 토글: off = symlink 제거, on = `ln -sf` 재생성
- 깨진 링크 / 고아(어느 쪽도 없는 스킬) 배지 표시
- 원클릭 수리: 깨진 링크를 재생성, 고아를 양쪽에 링크
- 메뉴바 드롭다운에서 "Skills" 탭/섹션으로 접근 (Sessions 목록과 같은 창)
- 검색 필터 (이름/설명 텍스트 매칭)

**Out:**
- 스킬 파일 편집 (내용 수정은 Obsidian에서)
- 새 스킬 파일 생성 (Phase 2.5로 이동)
- Gemini `.toml` vs `.md` 확장자 강제 변환 (현재 `.toml` 링크도 유효로 처리)
- OMC 스킬(`~/.claude/commands/oh-my-claudecode/`) 등 하위 디렉토리 스킬 관리

# 동작 / UI

## 메뉴바 창 구조

현재 `MenuContentView`에 탭 바를 추가한다.

```
[Sessions]  [Skills]          ← 탭 바 (상단 고정)
─────────────────────────────
[검색 필터 텍스트필드]
─────────────────────────────
● interview            C ✓  G ✓
● daily-vocab          C ✓  G –
● consensus-developer  C ✓  G –
  (broken)
● skill-architect      C ✓  G –
  ...
─────────────────────────────
  경고 배지: Gemini 누락 8개  [전체 수리]
```

- **C / G 배지**: Claude / Gemini 링크 상태
  - `✓` 초록: linked
  - `–` 회색: unlinked (off)
  - `⚠` 빨강: broken symlink
- **토글 클릭**: 배지를 클릭하면 해당 AI용 링크를 on/off
- **[전체 수리]**: 깨진 링크를 모두 재생성 (링크 타겟이 존재하는 것만)
- **행 클릭**: Obsidian에서 해당 스킬 파일 열기 (`open <path>`)

## 링크 상태 모델

```swift
enum LinkState {
    case linked    // symlink exists, target reachable
    case broken    // symlink exists, target missing
    case unlinked  // no symlink
}

struct SkillRecord: Identifiable {
    let id: String          // skill name (kebab-case)
    let name: String
    let description: String
    let obsidianPath: String
    var claudeState: LinkState
    var geminiState: LinkState
    var claudeLinkPath: String?   // ~/.claude/commands/<name>.md
    var geminiLinkPath: String?   // ~/.gemini/commands/<name>.toml (or .md)
}
```

## 스캐너: SkillScanner

- `scan()` → `[SkillRecord]`
- `06_AI_Config/SKILL_*.md` glob → frontmatter 파싱 (name, description)
- 이름 정규화: `SKILL_DAILY_VOCAB.md` → `daily-vocab`
- claude 링크: `~/.claude/commands/<name>.md` 존재·심볼릭 여부 체크
- gemini 링크: `~/.gemini/commands/<name>.toml` 또는 `<name>.md` (둘 중 하나라도 있으면 linked)
- 고아 감지: `~/.claude/commands/` 안의 `.md` 심볼릭 링크 중 Obsidian 스킬에 없는 것

## 토글 동작 (SkillToggler)

```
on:  ln -sf <obsidianPath> <commandsDir>/<name>.<ext>
off: rm <linkPath>
```
- claude 확장자: `.md`
- gemini 확장자: `.toml`
- 토글 후 즉시 `scan()` 재실행

# 데이터 소스 / 의존

| 소스 | 경로 | 접근 방식 |
|------|------|-----------|
| 스킬 소스 | `~/Obsidian/document/06_AI_Config/SKILL_*.md` | FileManager glob + 파일 읽기 |
| Claude 링크 dir | `~/.claude/commands/` | FileManager + lstat (symlink 확인) |
| Gemini 링크 dir | `~/.gemini/commands/` | FileManager + lstat |
| Obsidian 열기 | `open <path>` | NSWorkspace.open |

새 파일 시스템 권한 불필요 (Sandbox 없음, CLT 빌드).

**기본 경로**: `~/Obsidian/document/06_AI_Config/`를 하드코딩 기본값으로 사용.
경로 변경 설정 UI는 이번 범위 밖 (Phase 2.5 이후 고려).

**스캔 시점**: 드롭다운 열릴 때(on-open) 비동기(`Task { }`) 스캔. 실시간 FS watcher는 범위 밖.

**이름 결정 규칙**: 링크 파일명은 SKILL_*.md 파일명 기반 정규화 우선. frontmatter `name`이 달라도 파일명으로 링크 생성.

**Gemini 확장자**: 기존 링크가 있으면 그 확장자 유지. 새로 생성할 때만 `.toml` 기본.

# 엣지케이스

- `06_AI_Config/` 경로 없음 → 빈 목록 + "Obsidian 경로를 확인하세요" 안내
- frontmatter 없는 스킬 파일 → name=파일명 정규화, description="" 로 처리
- `~/.claude/commands/` 에 일반 파일(심볼릭 아닌)이 있는 경우 → `linked`로 취급, **Toggle Off 시 건드리지 않고 경고 표시** (파일 유실 방지)
- Toggle Off: `lstat`으로 symlink 여부 먼저 확인 → symlink가 아니면 skip + 인라인 경고
- `ln -sf` / `rm` 실패 시 → 해당 행에 인라인 에러 텍스트("링크 생성 실패: <reason>") 표시
- Gemini 링크가 `.md`로 생성된 경우 → `.toml`과 동일하게 `linked` 처리
- Gemini 링크가 `.md`와 `.toml` 둘 다 있는 경우 → 둘 다 `linked`, Toggle Off 시 둘 다 제거
- 스킬 이름 충돌 (kebab-case 정규화 결과 동일) → 파일명 알파벳 순으로 첫 번째 우선, 나머지는 "이름 충돌" 경고 배지
- `~/.gemini/commands/` 디렉토리 없음 → 토글 ON 시 자동 생성 (`mkdir -p`)
- 고아 링크 (`~/.claude/commands/` 에 있지만 Obsidian 에 없음) → 별도 "Orphan" 섹션 표시 + 삭제 버튼
- '전체 수리' 도중 실패 → 실패한 링크만 에러 표시, 성공한 것은 유지 (idempotent이므로 재시도 가능)

# 검증 방법

1. `swift build` 통과
2. `/run-clawde` 로 앱 재시작 → 메뉴바 클릭 → [Skills] 탭 표시
3. 스킬 목록 9개 표시, C/G 배지 현황 반영 (Claude 9개 linked, Gemini 1개 linked)
4. Gemini `daily-vocab` 행의 G 배지 클릭 → `~/.gemini/commands/daily-vocab.toml` 심볼릭 생성 확인
5. 다시 클릭 → 심볼릭 제거 확인
6. [전체 수리] → Gemini 8개 일괄 링크 생성 확인

# 미해결 질문

- Skills 탭을 별도 NSPopover로 띄울지, 현재 창 내 탭 전환으로 처리할지?
  → 현재 MenuBarExtra `.window` 스타일이므로 탭 전환이 자연스럽다. Popover는 2단 클릭이 필요해 UX 열위.
- 스킬 수가 많아질 때 스크롤 처리: SwiftUI `ScrollView` + `LazyVStack`으로 충분.
- Gemini 확장자 표준이 `.toml`인지 `.md`인지 불명확: 실제 파일 확인 결과 `.toml` 사용.
  링크 생성 시 `.toml`을 기본으로, 이미 `.md`가 있으면 그것을 인정.
