# airuncat

메뉴바 고양이가 병렬 AI 세션(Claude + Gemini)을 관제하고 클릭으로 복귀. AI가 바쁠수록 빨리 뛴다.

**Stack:** Swift 6.3 | SwiftUI MenuBarExtra | AppKit | SwiftPM | CLT 빌드 (Xcode 불필요)

## Directory Map

```
Sources/airuncat/
  AiruncatApp.swift        앱 진입점, MenuBarExtra scene
  SessionStore.swift       @MainActor ObservableObject, 스캔/애니/idle·closed 감지
  SessionScanner.swift     ~/.claude/projects/*/*.jsonl 파싱 (mtime 캐시, WorkState)
  GeminiScanner.swift      ~/.gemini/tmp/*/chats/*.jsonl 파싱 (maxAge 48h)
  CatRenderer.swift        벡터 고양이 프레임 (질주/수면, 좌향, 대기 버블)
  ITermController.swift    iTerm2 탭 포커스 / 새 탭 세션 이동 (AppleScript)
  MenuContentView.swift    드롭다운 UI (Sessions/Skills/Prompts/MCP 탭, 필터 바)
  ProcessDetector.swift    live claude/gemini 프로세스 cwd 탐지 (ps + lsof)
  MemoryScanner.swift      ~/.claude/projects/*/memory/ 파싱 (MemoryRecord: type/mtime)
  MemoryManager.swift      delete (파일 + MEMORY.md 인덱스 줄 제거)
  MemoryPopoverView.swift  Memory 배지 팝오버 UI (타입별 그룹, 미리보기, 삭제)
  MCPScanner.swift         ~/.mcp.json 파싱, enabledMcpjsonServers 활성 상태
  MCPManager.swift         toggle/create/delete (atomic JSON write, settings.local.json)
  MCPView.swift            MCP 탭 UI (토글/생성/삭제, UUID 에러 배너)
  SkillManager.swift       skillsDir 상수 + Obsidian 마이그레이션
  SkillScanner.swift       ~/.airuncat/skills/SKILL_*.md + commands 링크 상태 스캔
  SkillToggler.swift       symlink create/remove, createSkill, deleteSkill
  SkillsView.swift         Skills 탭 UI (토글/수리/추가/삭제)
  PromptScanner.swift      ~/.airuncat/prompts/*.md 파싱
  PromptManager.swift      migrate/create/delete/togglePin
  PromptLibraryView.swift  Prompts 탭 UI (핀/카테고리/검색/추가/삭제)
  HarnessScanner.swift     .claude/rules + ~/.claude/rules 파싱 (RuleFile: scope/summary/mtime)
  RuleManager.swift        rule 파일 create/delete (원자 쓰기)
  TagStore.swift / CustomNameStore.swift / NotificationManager.swift
build.sh                   release 빌드 + .app 번들 조립 + 자체 서명
```

## 데이터 저장 경로

| 종류 | 경로 |
|------|------|
| 스킬 원본 | `~/.airuncat/skills/SKILL_*.md` |
| Claude 링크 | `~/.claude/commands/<name>.md` (symlink) |
| Gemini 링크 | `~/.gemini/commands/<name>.toml` (symlink) |
| 프롬프트 | `~/.airuncat/prompts/<name>.md` |
| 커스텀 이름 | `~/.airuncat/custom-names.json` |
| MCP 서버 목록 | `~/.mcp.json` (등록/삭제) |
| MCP 활성 상태 | `~/.claude/settings.local.json` (`enabledMcpjsonServers` 배열) |

**스킬 수동 추가:** `~/.airuncat/skills/SKILL_[NAME].md` 생성 → 앱 C/G 배지 토글로 링크
**프롬프트 수동 추가:** `~/.airuncat/prompts/<name>.md` 생성 → 새로고침

## Active Rules

- CLT 빌드만, xcodebuild/.xcodeproj 금지 → `.claude/rules/clt-build-only.md`
- 메뉴바 아이콘 = template image; 대기 버블 시만 non-template → `.claude/rules/template-image-only.md`
- 고양이 = 벡터 드로잉, 외부 에셋 금지 → `.claude/rules/vector-cat-no-assets.md`
- 세션 JSONL 읽기 전용, 수정 절대 금지 → `.claude/rules/read-only-sessions.md`

## Project Skills

| Command | What it does |
|---------|-------------|
| `/run-clawde` | build.sh 후 앱 재시작 |
| `/render-cat` | 고양이 프레임 PNG 추출 |
| `/gemini-review` | Gemini 교차검토 (워크플로우 2·6단계) |

## Hooks

- `swift build` on .swift edit / `.build/`, `airuncat.app/` 편집 차단 / `~/.claude/projects/**/*.jsonl` 편집 차단

## Workflow

상세 기획 → Gemini 검토 → **사용자 승인** → 개발 → 리뷰 → Gemini 리뷰 → 문서 → PR
승인 없이 개발 금지. 작성·리뷰 분리. (상세: `docs/workflow.md`)

## Context (load on demand)

@docs/workflow.md @docs/data-sources.md @docs/cat-design.md
