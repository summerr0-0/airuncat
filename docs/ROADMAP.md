# airuncat Roadmap

메뉴바에 사는 작은 고양이가 병렬로 도는 모든 AI 작업(Claude Code + Gemini CLI)을 한눈에
관제하고, 클릭하면 그 세션으로 이동하며, 프롬프트/스킬을 한 곳에서 관리하는 통합 도구.

- 컨셉: AI가 바쁠수록 고양이가 빨리 뛰고, 다 쉬면 앉아서 존다 (RunCat 영감)

## 현재 상태 (v0.6)

- Swift / SwiftUI MenuBarExtra 앱, Command Line Tools만으로 빌드 (`build.sh`)
- 세션 모니터: Claude + Gemini CLI 세션 통합 관제 (AIKind 배지, live process 필터)
- WorkState 판정: JSONL 마지막 이벤트 기반 working/responded 구분, statusBar 색상 연동
- 대기 버블: 응답 대기 세션 있으면 고양이 아이콘에 red 배지 표시 (non-template)
- Recently Closed: 세션 종료 후 30초간 드롭다운 하단 표시, 클릭 시 재개
- 세션 이동: iTerm2 탭 포커스 (cwd prefix 매칭), 없으면 새 탭 (`claude -r` / `gemini`)
- 로그인 자동 시작 LaunchAgent, 자체 서명 인증서 (재빌드해도 접근성 권한 유지)
- 세션 커스텀 이름 (인라인 편집), 수동 태그/필터, idle 알림
- **Skills Manager**: Sessions/Skills 탭 전환, Obsidian SKILL_*.md symlink 관리
  - C/G 배지로 링크 상태 (linked/broken/unlinked) 시각화
  - 배지 클릭으로 on/off 토글, [수리] 버튼으로 broken 일괄 수정
  - Orphan Links 섹션 + 원클릭 삭제
  - 검색 필터
- **Harness Manager**: 세션 행에 H 배지, 클릭 시 팝오버
  - `.claude/rules/` 파일 목록, settings.json hooks on/off 토글
  - CLAUDE.md 내 OMC 존재 여부 감지
  - atomic write + mtime 충돌 가드, SHA256 기반 hook 식별
- **[NEW] Prompt Library**: Prompts 탭에서 재사용 프롬프트 관리
  - `~/Obsidian/document/07_Prompts/PROMPT_*.md` 파일 자동 스캔
  - frontmatter (title/tags/category/pinned), flow + block YAML 양 형식 지원
  - [⎘] 클립보드 복사 (1초 피드백), [▷] 활성 iTerm 세션 클립보드+Cmd+V 삽입
  - 핀 고정 섹션 + 카테고리 그룹, 검색 필터, 탭 전환 시 재스캔
- 하네스 일습 완비 (CLAUDE.md, AGENTS.md, rules, skills, settings.json, docs)

## 목표: OMC(oh-my-claudecode) 대체

OMC는 Claude 세션 **내부**에서 CLAUDE.md 주입 + hooks + skills로 동작한다.
airuncat은 세션 **외부**의 컨트롤 플레인으로, OMC가 하는 일을 GUI로 관리·대체한다.

| OMC 기능 | 대체 방식 | 담당 Phase |
|---------|---------|-----------|
| 세션 모니터링 | Session Monitor (이미 앞서 있음) | Phase 0-1 완료 |
| Skills 등록/링크 관리 | Skills Manager GUI | Phase 2 |
| Harness 설정 (rules, hooks, settings.json) | Harness Manager GUI | Phase 2.5 |
| 프롬프트/스킬 빠른 실행 | Prompt Library | Phase 3 |
| 멀티 에이전트 오케스트레이션 | Spawning (앱이 직접 Claude CLI 실행) | Phase 5 |
| Claude/Gemini 통합 관제 | Unified Control | Phase 4 |

**오케스트레이션 전략 (Phase 5 이전 결정 필요):**
- 전략 A (현실적): 오케스트레이션 로직은 CLAUDE.md에 유지, airuncat이 그 설정을 GUI로 관리.
- 전략 B (장기): airuncat이 `claude -p "..."` 프로세스를 직접 spawn해서 외부에서 에이전트 지시.
  - 단방향 실행이라 Claude가 중간에 되묻는 경우 처리가 복잡함. Phase 5로 미룸.

## 핵심 기둥 (Pillars)

1. Session Monitor — 병렬 AI 작업 실시간 관제 (Claude + Gemini)
2. Skills Manager — `SKILL_*.md` <-> `~/.claude/commands`, `~/.gemini/commands` 링크 관리, 중복/고아 탐지, on/off
3. Harness Manager — rules, hooks, settings.json, CLAUDE.md per-project 설정 관리
4. Prompt Library — 재사용 프롬프트 저장/분류/빠른 삽입
5. Unified Control — Claude / Gemini 양쪽 통합 뷰 및 동기화
6. Spawning (장기) — airuncat이 Claude CLI를 직접 실행해 에이전트 오케스트레이션

## 개발 워크플로우

상세 기획 -> Gemini 검토 -> 승인 -> 개발 -> 리뷰 -> Gemini 리뷰 -> 문서 완료 -> PR
(상세: `docs/workflow.md`. 작성/리뷰 분리, self-approve 금지, 승인 전 개발 금지.)

## Phases

### Phase 0 — Session Monitor MVP [완료]
- [x] 고양이 렌더러 (벡터, 질주/수면, 템플릿 이미지)
- [x] JSONL 세션 스캐너 + mtime 캐시
- [x] 메뉴바 드롭다운 세션 목록 UI
- [x] `.app` 번들 빌드 스크립트 + 자체 서명 인증서(권한 영속)

### Phase 1 — 세션 이동 / 모니터 고도화 [완료]
- [x] 클릭 -> iTerm2 탭 포커스 (cwd prefix 매칭) + 없으면 새 탭 resume
- [x] live process 없는 세션 자동 제거 (ProcessDetector — ps + lsof)
- [x] iTerm 자동화 권한 허용 후 최종 동작 확인
- [x] 로그인 자동 시작 LaunchAgent (`com.jeongilin.airuncat`)
- [x] Gemini CLI 세션 소스 연동 (`~/.gemini/tmp/<hash>/chats/*.jsonl`)
- [x] 멈춤 알림 (active→idle 전환 시 UNUserNotification)
- [x] 세션별 커스텀 이름 붙이기 (더블클릭 인라인 편집)
- [x] 세션 태그 수동 선택 (TagStore, 필터 바)
- [x] WorkState 판정 + C/G 배지 + statusBar 색상 (working=green, responded=orange)
- [x] Recently Closed 30초 복구 버퍼
- [x] 고양이 대기 버블 배지 (응답 대기 세션 있을 때 red badge)
- [x] 고양이 좌향 전환 (수평 flip), 캔버스 26×18 → 32×22
- [ ] **[백로그] Refresh 버튼 동작 안 함** — MenuBarExtra 컨텍스트 버튼 탭 미전달 추정
- [ ] **[백로그] Gemini 세션 재개 미구현** — 현재 클릭 시 `cd <cwd> && gemini` (새 세션 시작). `claude -r <id>` 같은 resume 플래그가 Gemini CLI에 없어 기존 대화를 이어받지 못함. Gemini resume API/플래그 지원 여부 조사 후 연동.

### Phase 1.5 — 세션 행 표시 개선 [백로그]
- [ ] **커스텀 이름**: 사용자가 지정한 이름 (수정 가능, 디폴트 폴더명) — 현재 구현됨, 표시 위치/우선순위 재검토
- [ ] **최근 질문 표시**: 사용자가 마지막으로 입력한 메시지를 행에 표시 (현재 tool activity만 표시)
- [x] **활성 스킬 표시**: 세션 행에 현재 실행 중인 스킬 이름 표시.
  - JSONL backward pass에서 `Skill` tool_use 탐지, `tool_result` 미존재 시 실행 중 판정.
  - `SessionInfo.activeSkill: String?` 추가. 세션 행에 `"/skill-name"` (accentColor monospaced) 표시.
- [ ] **진행 상황 (터미널 최근 줄)**: 해당 세션 tty의 마지막 stdout 라인 표시.
  - `lsof` tty 매핑은 이미 있음 (`ITermController.cwdsForTTY`). tty를 통해 pty output 읽는 방법 검토.
  - 부하/복잡도가 크면 생략. 우선순위 낮음.

### Phase 2 — Skills Manager [완료]
OMC의 skills 레지스트리 + 링크 관리를 GUI로 대체한다.
- [x] `06_AI_Config/SKILL_*.md` 전체 스캔 + 파싱 (frontmatter: description)
- [x] `~/.claude/commands/`, `~/.gemini/commands/` 링크 상태 매핑 (linked/broken/unlinked)
- [x] 스킬 on/off 토글 — off = symlink 제거, on = symlink 재생성 (lstat 보호)
- [x] 깨진 링크/고아 탐지 + 배지 표시 + 원클릭 수리
- [x] 스킬 목록 드롭다운 패널 (Sessions/Skills 탭, 검색 필터)

### Phase 2.7 — 스킬 로컬 독립 저장 [완료]
Phase 3.1(프롬프트 로컬화)과 동일한 패턴으로 스킬도 Obsidian 의존 제거.
- [x] 저장 경로: `~/Obsidian/document/06_AI_Config/SKILL_*.md` → `~/.airuncat/skills/SKILL_*.md`
- [x] `SkillManager.swift` 신규: skillsDir 상수 + migrateFromObsidianIfNeeded
- [x] `SkillScanner`: obsidianBase 제거 → SkillManager.skillsDir, obsidianPath → sourcePath
- [x] `SkillToggler`: createSkill/deleteSkill 경로 교체, enable() 심볼릭링크 대상 교체
- [x] `SkillsView`: obsidianBase/obsidianPath 참조 제거, 빈 상태 문구 업데이트
- [x] OMC 유용 스킬 10개 추가: ultrawork, autopilot, ralph, ralplan, deep-interview, code-review, commit, ask, remember, ai-slop-cleaner

### Phase 2.6 — 스킬 추가 & 삭제 [완료]
- [x] "+ 추가" 버튼 → 인라인 폼 (이름/설명/C+G 연결 토글)
- [x] 이름 실시간 sanitize: ASCII 소문자+숫자+하이픈만, 선두/말미 하이픈 제거
- [x] 중복 체크 2단계: 메모리(skills 배열) + 디스크(kebab 정규화 비교)
- [x] 생성: `SKILL_*.md` 원자적 쓰기 + 선택한 AI symlink 자동 생성
- [x] 삭제: 호버 → 휴지통 → 확인 배너 → [삭제]
- [x] 삭제 순서: Claude symlink → Gemini symlink(.toml+.md) → 원본 파일 → reload
- [x] 에러 표시: 파일 에러는 인라인, 링크 에러는 reload 후 errorBanner에 표시

### Phase 2.5 — Harness Manager [완료]
OMC가 CLAUDE.md 주입으로 강제하는 설정들을 GUI로 관리한다.
- [x] 프로젝트별 `.claude/rules/` 파일 목록 조회
- [x] `settings.json` hooks 목록 조회 (PreToolUse/PostToolUse, enabled/disabled 구분)
- [x] hooks on/off 토글 (settings.json `_disabledHooks` 키로 non-destructive 관리)
- [x] CLAUDE.md 내 "oh-my-claudecode" 문자열 기반 OMC 감지
- [x] 활성 세션 행에 "H N" 또는 "H A/T" 배지 (비활성 hook 있으면 주황)
- [x] per-project 하네스 팝오버 (rules + hooks + OMC 상태 + settings.json 열기)
- [x] `.task(id: session.cwd)` lifecycle-bound 스캔 (뷰 사라질 때 자동 취소)
- [x] 배지 공간 예약으로 pop-in 레이아웃 시프트 방지

### Phase 3 — Prompt Library [완료]
OMC의 스킬 기반 프롬프트 재사용을 독립 라이브러리로 대체한다.
- [x] 저장소: `~/.airuncat/prompts/*.md` (Phase 3.1에서 Obsidian → 로컬 이전)
- [x] frontmatter 파서: title/tags/category/pinned, flow + block YAML 배열 지원
- [x] 카테고리 그룹 + 핀 고정 + 검색 필터
- [x] [⎘] 클립보드 복사 (1초 체크 피드백, Task cancel 중복 방지)
- [x] [▷] 활성 세션 iTerm 삽입 (클립보드+Cmd+V, 자동 실행 없음)
- [x] "Insert to: X" 헤더로 삽입 대상 명시
- [x] 탭 전환 시 재스캔 (`.onAppear + .task(id: scanID)`)
- [x] ITermController.findSessionID 헬퍼 추출 (focus + insertText 중복 제거)

### Phase 3.1 — Prompt Library 로컬 독립 저장 [완료]
- [x] 저장 경로: `~/Obsidian/document/07_Prompts/PROMPT_*.md` → `~/.airuncat/prompts/*.md`
- [x] 파일명 규칙: `PROMPT_*.md` prefix 제거 → stem = ID
- [x] 1회성 마이그레이션 (`migrateFromObsidianIfNeeded`): 앱 첫 실행 시 자동 복사, Obsidian 원본 유지
- [x] PromptManager.swift 신규: migrate / create / delete / togglePin (atomic write)
- [x] togglePin — 닫는 `---` 없는 파일 방어: `nil` 반환 → 에러 표시, 파일 미수정
- [x] PromptRecord: `var pinned`, `let filePath` 추가
- [x] 인라인 생성 폼 (ID sanitize/validate, 중복 체크, pinned 토글)
- [x] 삭제 UI (2단계 확인, SkillRow 패턴 재사용)
- [x] Finder 열기 버튼
- [x] initialLoaded 패턴: 첫 로드만 스피너, 이후 rescan은 즉시
- [x] 핀 토글: 호버 버튼 그룹 양방향 (pin / unpin)

### Phase 4 — Gemini 연동 고도화 [완료]
- [x] GeminiScanner backward pass: `toolCalls` 파싱 → `toolName`, `toolDetail` 설정
  - `preferredKeys` 배열로 args 키 우선순위 결정 (file_path/path → basename, 나머지 원본)
  - `foundTool` 플래그로 중복 toolCalls 처리 (seenIds 없이도 정확)
  - 결정적 fallback: `args.keys.sorted()` 순회
- [x] `GeminiScanner`: `model` 필드 파싱 → `SessionInfo.modelName: String?`
- [x] `SessionInfo.modelName: String? = nil` 추가 (Gemini = 모델명, Claude = nil)
- [x] `SessionStore.claudeActiveCount` / `geminiActiveCount` computed property
- [x] `MenuContentView.summary`: "2C 1G active · 1 idle" 형태 C/G 구분 표시

### Phase 4.1 — 통합 관제 (백로그)
- [ ] 통합 세션 타임라인 (Claude + Gemini 이벤트 시계열)
- [ ] 스킬 동기화 상태판 (claude 링크 vs gemini 링크 비교)
- [ ] 모델별 사용량 집계 (세션 수, 활성 시간)
- [ ] Gemini 세션에도 activeSkill 표시 (Phase 1.5 동일 방식)

### Phase 5 — Spawning (장기, 전략 B)
airuncat이 직접 Claude CLI를 실행해 에이전트를 오케스트레이션한다.
- [ ] 전략 결정: A(CLAUDE.md 관리) vs B(직접 spawn) 최종 선택
- [ ] `Process` + `Pipe`로 `claude -p "..."` 비동기 실행
- [ ] stdout 스트리밍을 airuncat UI에 표시
- [ ] 중간 질문(interactive prompt) 감지 + UI에서 응답 입력
- [ ] 작업 큐 (여러 작업 순차/병렬 실행)

---

## OMC 총괄 허브 확장 로드맵

OMC(oh-my-claudecode)가 Claude 세션 내부에서 처리하는 컨텍스트 관리·설정·오케스트레이션을
airuncat GUI로 완전 대체하기 위한 Phase 6+ 계획.

| Phase | 이름 | OMC 대체 기능 | 우선순위 |
|-------|------|-------------|---------|
| 6 | MCP 서버 관리 | skill-portfolio-analyzer, MCP 등록/해제 | 높음 |
| 7 | Rules 에디터 | rules 추가/삭제/편집 (Harness 확장) | 높음 |
| 8 | Memory 뷰어 | auto-memory 열람·편집 | 중간 |
| 9 | 설정 패널 | settings.json CRUD (Harness 확장) | 중간 |
| 10 | CLAUDE.md 관리 | 글로벌·프로젝트 컨텍스트 파일 관리 | 중간 |
| 11 | 퀵 팔레트 | 글로벌 단축키 → 프롬프트/스킬 즉시 주입 | 높음 |
| 12 | 세션 통계 | 사용 패턴·모델 집계, 히트맵 | 낮음 |

---

### Phase 6 — MCP 서버 관리 [백로그]

OMC의 `skill-portfolio-analyzer`(MCP 등록 상태 감사)를 GUI로 대체한다.
`~/.claude.json` 내 `mcpServers` 블록을 읽어 활성 MCP 서버를 시각화·관리.

**소스:**
- `~/.claude.json` — 글로벌 Claude Code 설정 (`mcpServers` 키)
- `.claude/settings.json` — 프로젝트 로컬 오버라이드

**화면 구성 (Sessions 탭 하단 또는 별도 탭):**
```
[MCP Servers]                              [+ 추가] [새로고침]
────────────────────────────────────────
  context7       ● 활성   npx @context7    [편집] [삭제]
  google-drive   ● 활성   node /path/...   [편집] [삭제]
  my-server      ○ 비활성  python -m ...   [편집] [삭제]  (disabled 키 존재 시)
────────────────────────────────────────
  고아 항목 (명령어 경로 없음): broken-server  [삭제]
```

**기능:**
- [ ] `MCPScanner`: `~/.claude.json` 파싱, `mcpServers` 배열 → `MCPRecord` (name, command, args, env, disabled)
- [ ] 활성/비활성 토글 — `disabled: true` 키 추가/제거 (atomic write)
- [ ] 고아 탐지 — command 실행파일이 존재하지 않는 항목
- [ ] `+ 추가` 인라인 폼 — name / command / args 입력
- [ ] 삭제 — 2단계 확인 후 `mcpServers` 블록에서 제거
- [ ] 편집 — command/args 인라인 수정
- [ ] 글로벌 vs 프로젝트 소스 배지 (G / P)

**신규 파일:**
- `MCPScanner.swift` — `~/.claude.json` 파싱
- `MCPManager.swift` — enable/disable/create/delete (atomic write)
- `MCPView.swift` — 탭 내 UI

---

### Phase 7 — Rules 에디터 [백로그]

현재 Harness 팝오버는 `.claude/rules/` 파일 목록을 보여주기만 한다.
이를 CRUD 가능한 에디터로 확장한다. OMC의 rule injection 기능을 GUI로 대체.

**현재 상태:** `HarnessScanner`가 rule 파일 목록 반환 → `HarnessPopoverView`에서 파일명 나열 + `settings.json` 열기 링크.

**확장 기능:**
- [ ] Rule 파일 내용 인라인 미리보기 (팝오버 내 스크롤 텍스트, 첫 5줄)
- [ ] `+ 새 Rule` 버튼 → 이름 입력 → `.claude/rules/<name>.md` 생성 (기본 템플릿 포함)
  ```markdown
  # Rule 이름
  
  여기에 AI에게 강제할 제약이나 동작을 기술한다.
  ```
- [ ] Rule 파일 삭제 (2단계 확인)
- [ ] 글로벌(`~/.claude/rules/`) vs 프로젝트(`.claude/rules/`) 구분 섹션
- [ ] Finder에서 열기 버튼 (외부 에디터로 편집 유도)
- [ ] rule 파일 mtime 기반 "마지막 수정" 표시

**수정 파일:**
- `HarnessScanner.swift` — rule 파일 mtime, 첫 줄(요약) 파싱 추가
- `HarnessScanner.swift` — 글로벌 rules 경로(`~/.claude/rules/`) 추가 스캔
- `RuleManager.swift` (신규) — create/delete rule 파일
- `HarnessPopoverView` (확장) — 미리보기 + CRUD UI 추가

---

### Phase 8 — Memory 뷰어 [백로그]

OMC의 auto-memory(`~/.claude/projects/*/memory/`)를 GUI에서 열람·편집.
어떤 기억이 쌓여 있는지 확인하고 오래된 항목을 정리하는 용도.

**소스:**
- `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md` — 인덱스
- `~/.claude/projects/<encoded-cwd>/memory/*.md` — 개별 메모리 파일

**화면 구성:**
```
[Memory]  프로젝트: airuncat            [Finder 열기] [새로고침]
────────────────────────────────────────
  [user]    사용자 프로필·선호도          2개
  [feedback] 작업 피드백·교정           5개
  [project]  프로젝트 현황·목표          3개
  [reference] 외부 시스템 참조          1개
────────────────────────────────────────
  * project-airuncat.md     2026-06-11   [보기] [삭제]
  * feedback-testing.md     2026-06-10   [보기] [삭제]
  ...
```

**기능:**
- [ ] `MemoryScanner`: `~/.claude/projects/` 전체 순회 → 각 프로젝트의 `memory/` 디렉토리 탐지
- [ ] MEMORY.md 인덱스 파싱 → 메모리 파일 목록과 type 연결
- [ ] 메모리 파일 frontmatter 파싱 (`name`, `description`, `type`) 
- [ ] type별 그룹핑 (user / feedback / project / reference)
- [ ] 인라인 미리보기 (팝오버 또는 확장 행)
- [ ] 삭제 — MEMORY.md 인덱스에서 해당 줄 제거 + 파일 삭제 (atomic)
- [ ] Sessions 탭 연동 — 세션 행 클릭 시 해당 프로젝트 메모리 팝오버로 표시
- [ ] "All Projects" 통합 뷰 — 전체 프로젝트 메모리 한눈에

**신규 파일:**
- `MemoryScanner.swift`
- `MemoryManager.swift` — delete (MEMORY.md 인덱스 라인 제거 + 파일 삭제)
- `MemoryView.swift` — 독립 탭 또는 Sessions 탭 하단 섹션

---

### Phase 9 — 설정 패널 [백로그]

현재 Harness 팝오버는 hooks on/off 토글만 지원한다.
`settings.json` 전체를 GUI로 관리할 수 있도록 확장한다.

**소스:**
- `~/.claude/settings.json` — 글로벌 설정
- `.claude/settings.json` — 프로젝트 로컬 설정

**확장 기능:**

_Hooks 섹션 (현재: 토글만)_
- [ ] `+ 새 Hook` 인라인 폼 — type(Pre/PostToolUse), matcher, command 입력
- [ ] Hook 삭제 (현재 `_disabledHooks`로 숨기기만 → 실제 제거 선택지 추가)
- [ ] Hook 명령어 인라인 편집
- [ ] Hook 유형 필터 (PreToolUse / PostToolUse)

_Permissions 섹션 (신규)_
- [ ] `settings.json`의 `permissions.allow` / `permissions.deny` 배열 표시
- [ ] 항목 추가/삭제 (Bash, Read, Write 등 tool 패턴)
- [ ] 글로벌 vs 프로젝트 오버라이드 비교 뷰

_기타 설정_
- [ ] `autoUpdates`, `theme`, `preferredNotificationChannel` 등 키-값 나열
- [ ] 값 인라인 편집 (String/Bool/Int 타입 자동 감지)
- [ ] 변경 사항 저장 전 diff 미리보기

**수정 파일:**
- `HarnessScanner.swift` — permissions 파싱 추가
- `HarnessManager.swift` (신규 또는 기존 확장) — hook/permission CRUD
- `SettingsView.swift` (신규) — 독립 패널 UI

---

### Phase 10 — CLAUDE.md 관리 [백로그]

OMC가 CLAUDE.md를 컨텍스트 주입 수단으로 사용하는 것처럼,
airuncat에서 글로벌·프로젝트 CLAUDE.md를 빠르게 열람·편집.

**소스:**
- `~/.claude/CLAUDE.md` — 글로벌 (모든 프로젝트 공통)
- `<project>/.claude/CLAUDE.md` 또는 `<project>/CLAUDE.md` — 프로젝트 로컬
- `<project>/AGENTS.md` — 에이전트 지시 파일 (Claude + Gemini 공통)

**기능:**
- [ ] Sessions 탭 세션 행에 "M" 배지 — 프로젝트 CLAUDE.md 존재 여부
- [ ] 배지 클릭 → 팝오버에서 첫 20줄 미리보기
- [ ] "에디터에서 열기" 버튼 — `NSWorkspace.open(url)`
- [ ] "Finder에서 열기" 버튼 — 해당 디렉토리
- [ ] 글로벌 CLAUDE.md 빠른 접근 — footer에 "G.md" 버튼
- [ ] AGENTS.md 존재 시 팝오버에 탭 구분 (CLAUDE.md | AGENTS.md)
- [ ] 프로젝트 없는 경우 `+ CLAUDE.md 생성` 버튼 → 기본 템플릿으로 파일 생성
  ```markdown
  # 프로젝트 이름
  
  ## 역할
  
  ## 규칙
  ```
- [ ] 글로벌 CLAUDE.md 단어 수 / 마지막 수정일 표시 (컨텍스트 비대 경고)

**수정 파일:**
- `HarnessScanner.swift` — CLAUDE.md / AGENTS.md 경로·크기·mtime 파싱 추가
- `CLAUDEMDView.swift` (신규) — 팝오버 미리보기 UI

---

### Phase 11 — 퀵 팔레트 [백로그]

OMC의 Tier-0 workflows(autopilot, ultrawork, ralph 등)를 단축키 하나로 실행하는
스포트라이트 스타일 글로벌 팔레트. airuncat의 킬러 피처 후보.

**동작:**
```
⌥Space  →  팔레트 창 표시
────────────────────────────────
  /            검색: 스킬 + 프롬프트 통합
────────────────────────────────
  > /run-clawde      [Skills]     최근
  > /ultrawork       [Skills]     최근
  > 코드 리뷰 체크리스트  [Prompts]
  > git-commit        [Prompts]
────────────────────────────────
  삽입 대상: airuncat  ←  현재 활성 세션
  [Enter] 삽입   [⌘Enter] 복사   [Esc] 닫기
```

**기능:**
- [ ] 글로벌 단축키 등록 — `CGEvent` tap 또는 `NSEvent.addGlobalMonitorForEvents` (`⌥Space` 기본값, 사용자 설정 가능)
- [ ] 플로팅 패널 (`NSPanel`, `NSWindowStyleMask.nonactivatingPanel`) — 다른 앱 포커스 유지
- [ ] 스킬 + 프롬프트 통합 검색 (실시간 fuzzy 필터)
- [ ] 최근 사용 항목 상단 정렬 (LocalStorage: `~/.airuncat/palette-history.json`)
- [ ] `Enter` → 현재 활성 iTerm 세션에 텍스트 주입 (`ITermController.insertText`)
- [ ] `⌘Enter` → 클립보드 복사만 (주입 없이)
- [ ] 삽입 대상 세션 자동 감지 (가장 최근 활성 세션) + 수동 선택 드롭다운
- [ ] 스킬 선택 시 `/skill-name` 형태로 주입 (Claude 세션이면 바로 slash 커맨드 실행)
- [ ] 팔레트 열기 시 세션 목록 최신화

**신규 파일:**
- `QuickPalette.swift` — `NSPanel` 기반 플로팅 창
- `GlobalShortcut.swift` — `CGEvent` tap 글로벌 단축키 등록·해제
- `PaletteViewModel.swift` — 검색·필터·히스토리 로직

**권한:** `com.apple.security.temporary-exception.mach-lookup` 또는 접근성 권한(이미 있음)으로 글로벌 이벤트 모니터 가능.

---

### Phase 12 — 세션 통계 [백로그]

OMC의 `session-pattern-analyzer`를 시각화한다.
JSONL 파싱 결과를 집계해 사용 패턴을 한눈에.

**화면:**
```
[Stats]  이번 주                            [일/주/월]
────────────────────────────────────────
  Claude  47세션  ████████████  12.4h
  Gemini  12세션  ███           3.1h
────────────────────────────────────────
  활동 히트맵 (시간대별)
  00 01 02 03 04 05 06 07 08 09 10 11 ...
  월 ░░░░░░░░░░░░████████████░░
  화 ░░░░░░░░░████████████████░
  ...
────────────────────────────────────────
  자주 쓴 스킬    /ultrawork 23회  /run-clawde 18회
  자주 쓴 프롬프트 code-review 15회  git-commit 12회
  평균 세션 길이  Claude 28분  Gemini 19분
```

**기능:**
- [ ] `StatsScanner`: `~/.claude/projects/` 전체 JSONL 순회, 날짜·mtime 집계
  - 일별 세션 수, 총 활동 시간 (mtime 델타 합산)
  - 시간대별 활동 분포 (히트맵용 24×7 배열)
  - 스킬 사용 빈도 (tool_use type=Skill 이벤트 집계)
- [ ] 캐시 — `~/.airuncat/stats-cache.json` (날짜별, 신규 JSONL만 증분 업데이트)
- [ ] 기간 필터 (일/주/월/전체)
- [ ] Claude vs Gemini 분리 통계
- [ ] 자주 쓴 스킬·프롬프트 top-N 목록
- [ ] 평균 세션 지속 시간
- [ ] Stats 탭 추가 (Sessions / Skills / Prompts / Stats)
- [ ] 히트맵 컬러 — `accentColor` 명도 단계 (0=투명, 4=진함)

**신규 파일:**
- `StatsScanner.swift` — 집계 로직 (background Task)
- `StatsStore.swift` — `@MainActor ObservableObject`, 캐시 관리
- `StatsView.swift` — 히트맵 + 차트 UI

---

## Next Action
- [ ] Phase 3.1 Gemini 리뷰 (step 6) → 문서 완료 (step 7) → 커밋 (step 8)
- [ ] Phase 2 + 2.5 + 2.6 + 3 + 3.1 + 4 커밋 → PR 생성 (git push + gh pr create)
- [ ] Phase 6~12 중 다음 구현할 Phase 선택 후 specs/ 작성

## 주요 결정 / 기술 메모
- 형태: macOS 메뉴바 앱 (SwiftUI MenuBarExtra, `LSUIElement`)
- 빌드: Swift 6.3 + SwiftPM + CLT (풀 Xcode 불필요)
- 고양이: 벡터 드로잉 + 템플릿 이미지 (다크/라이트 자동)
- 데이터: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, mtime로 활성 판정
- 세션 이동: Warp는 AppleScript 미지원 -> 탭 포커스 불가 -> iTerm2로 전환
- 권한 영속: ad-hoc 서명은 재빌드마다 TCC 권한이 풀림 -> 자체 서명 인증서 `airuncat Self-Signed`로 사인
- 참고: ai-monitor(hyunho058)는 모니터링 전용, Gemini 로그 경로만 차용
