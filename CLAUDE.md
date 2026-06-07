# Clawde

메뉴바에 사는 고양이가 병렬로 도는 AI 세션(Claude Code)을 한눈에 관제하고, 클릭하면 해당 세션으로 복귀시키는 macOS 메뉴바 앱. AI가 바쁠수록 고양이가 빨리 뛴다.

## Stack

Swift 6.3 | SwiftUI MenuBarExtra | AppKit (벡터 고양이 드로잉) | SwiftPM | Command Line Tools 빌드 (풀 Xcode 불필요)

## Directory Map

```
Sources/Clawde/
  ClawdeApp.swift       앱 진입점, MenuBarExtra scene, 디버그 렌더(--render-frames)
  SessionStore.swift    @MainActor ObservableObject, 스캔/애니메이션 타이머
  SessionScanner.swift  ~/.claude/projects/*/*.jsonl 파싱 (mtime 캐시)
  CatRenderer.swift     벡터 고양이 프레임 (질주/수면, 템플릿 이미지)
  ITermController.swift iTerm2 탭 포커스 / 새 탭으로 세션 이동 (AppleScript)
  MenuContentView.swift 드롭다운 세션 목록 UI
build.sh                swift build -c release + .app 번들 조립 + ad-hoc sign
Info.plist              LSUIElement 메뉴바 상주 앱 정의
.claude/rules/          강제 제약
docs/                   데이터 소스 / 설계 상세
```

## Active Rules

- CLT로만 빌드, xcodebuild/.xcodeproj 금지 → `.claude/rules/clt-build-only.md`
- 메뉴바 아이콘은 항상 template image → `.claude/rules/template-image-only.md`
- 고양이는 벡터 드로잉, 외부 이미지 에셋 금지 → `.claude/rules/vector-cat-no-assets.md`
- 세션 JSONL은 읽기 전용, 절대 수정 금지 → `.claude/rules/read-only-sessions.md`

## Project Skills

| Command | What it does |
|---------|-------------|
| `/run-clawde` | build.sh 후 앱 재시작 (메뉴바에서 확인) |
| `/render-cat` | 고양이 프레임을 PNG로 뽑아 시각 확인 |
| `/gemini-review` | Gemini로 스펙/diff 교차검토 (워크플로우 2·6단계) |

## Active Hooks

- `swift build` on .swift edit (컴파일 체크)
- `.build/`, `Clawde.app/` 편집 차단 (빌드 산출물)
- `~/.claude/projects/**/*.jsonl` 편집 차단 (세션 읽기 전용)

## Workflow

기능/Phase는 8단계 파이프라인을 따른다 (상세: `docs/workflow.md`):
상세 기획 -> Gemini 검토 -> 사용자 승인 -> 개발 -> 리뷰 -> Gemini 리뷰 -> 문서 완료 -> PR
승인(3단계) 없이 개발(4단계)로 넘어가지 않는다. 작성과 리뷰는 분리한다.

## Context (load on demand)

@docs/workflow.md
@docs/data-sources.md
@docs/cat-design.md
