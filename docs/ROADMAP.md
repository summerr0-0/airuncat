# airuncat Roadmap

메뉴바에 사는 작은 고양이가 병렬로 도는 모든 AI 작업(Claude Code + Gemini CLI)을 한눈에
관제하고, 클릭하면 그 세션으로 이동하며, 프롬프트/스킬을 한 곳에서 관리하는 통합 도구.

- 컨셉: AI가 바쁠수록 고양이가 빨리 뛰고, 다 쉬면 앉아서 존다 (RunCat 영감)

## 현재 상태 (v0.7)

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

### Phase 6 — MCP 서버 관리 [완료]
- [x] `MCPScanner`: `~/.mcp.json` 파싱, `enabledMcpjsonServers` 활성 상태 연동
- [x] `MCPManager`: toggle(enabledMcpjsonServers 배열 편집) / create / delete (atomic JSON write)
- [x] `MCPView`: MCP 탭 UI — 활성/비활성 토글, 2단계 삭제, 인라인 생성 폼, Finder 열기
- [x] `MenuContentView`: Sessions/Skills/Prompts/**MCP** 4탭 확장
- [x] toggle/delete async (Task.detached), errors UUID 태깅 (ForEach ID 충돌 방지)

### Phase 6.1 — MCP broken 탐지 [백로그]
- [ ] MCPRecord에 `isBroken: Bool` 추가
- [ ] 절대경로 command만 존재 여부 체크 (`npx`/`node`/`python`/`uvx`/`deno` 제외)
- [ ] broken 항목에 ⚠ 배지 + 별도 섹션 표시

---

### Phase 7 — Rules 에디터 [완료]
- [x] `RuleFile` 모델 확장: `id(scope:stem)` / `summary` / `mtime` / `scope` 추가
- [x] `HarnessScanner`: 글로벌 `~/.claude/rules/` 추가 스캔, `readSummary` / stat mtime
- [x] `HarnessBadgeButton.Coordinator.tapped` 비동기 (`Task.detached`) — main thread I/O 방지, double-tap guard
- [x] `RuleManager` (신규): create / delete (원자 쓰기, 디렉토리 자동 생성)
- [x] `HarnessPopoverView`: [G]/[P] 배지, hover 삭제·Finder 버튼, 미리보기 토글(5줄), 생성 폼, 재스캔 패턴
- [x] 글로벌 rule 삭제 시 "모든 프로젝트에 영향" 경고 문구

---

### Phase 8 — Memory 뷰어 [완료]
- [x] `MemoryScanner`: jsonl 경로 → `memory/` 유도 (cwd 인코딩 재구현 없이), frontmatter 파싱 (nested `metadata.type`)
- [x] `MemoryManager`: delete (파일 삭제 + MEMORY.md `](\(filename))` 앵커 매칭으로 인덱스 줄 제거)
- [x] `MemoryPopoverView`: user/feedback/project/reference 타입별 그룹, 행 클릭 미리보기 토글, 삭제
- [x] Session 행 `[M N]` 배지 — `.task(id: session.id)` 비동기 카운트, `SessionInfo` 비수정
- [x] `MemoryBadgeButton`: `HarnessBadgeButton` 패턴, double-tap guard

### Phase 8.1 — Memory All-projects 뷰 [백로그]
- [ ] 전체 프로젝트 메모리 통합 뷰 (탭 또는 별도 패널)

---

### Phase 9 — 설정 패널 (Permissions + Hook 삭제) [완료]
- [x] `PermissionEntry` 모델: `id="kind:pattern"`, `HarnessInfo.permissions` 추가
- [x] `HarnessScanner.scanPermissions`: `permissions.allow/deny` 파싱
- [x] `HarnessManager.addPermission`: 신규 중첩 키 생성, 중복 체크
- [x] `HarnessManager.removePermission`: 배열에서 제거 + atomic write
- [x] `HarnessManager.deleteHook`: disabled hook extract-only (no re-insert)
- [x] `HarnessPopoverView`: Permissions 섹션 (allow ✓/deny ⊘), 인라인 생성 폼, disabled hook 삭제 버튼, maxHeight 480

### Phase 9.1 — Hook 생성 폼 [백로그]
- [ ] `+ 새 Hook` 인라인 폼 (event type / matcher / command 입력)
- [ ] Hook 명령어 인라인 편집

---

### Phase 10 — CLAUDE.md 관리 [완료]
- [x] `ClaudeMdScanner`: `exists(cwd:)`(배지 prefetch, fileExists만) / `scan(cwd:)`(팝오버 full parse + wordCount)
- [x] `ClaudeMdPopoverView`: 글로벌/프로젝트 탭, 첫 20줄 미리보기, wordCount 표시(500+ 경고), "에디터로 열기", 없을 때 "+ 생성" 버튼
- [x] Session 행 `[C]` 배지 16pt (존재 시만 opacity 1)
- [x] footer "G.md" 버튼 — 글로벌 CLAUDE.md 항상 접근

### Phase 10.1 — AGENTS.md 지원 [백로그]
- [ ] AGENTS.md 존재 시 팝오버에 탭 추가

---

### Phase 11 — 퀵 팔레트 [완료]

OMC의 Tier-0 workflows(autopilot, ultrawork, ralph 등)를 단축키 하나로 실행하는
스포트라이트 스타일 글로벌 팔레트.

**동작:**
```
⌥Space  →  팔레트 창 표시 (토글)
────────────────────────────────
  /            검색: 스킬 + 프롬프트 통합
────────────────────────────────
  > /run-clawde      [Skills]     최근
  > /ultrawork       [Skills]     최근
  > 코드 리뷰 체크리스트  [Prompts]
  > git-commit        [Prompts]
────────────────────────────────
  삽입 대상: airuncat  ←  현재 활성 세션
  [↩] 삽입   [⌘↩] 복사   [Esc] 닫기
```

**구현:**
- [x] `CGEvent` tap 기반 `⌥Space` 글로벌 단축키 (접근성 권한 재사용)
- [x] `NSPanel` 플로팅 창 (floating level, canJoinAllSpaces, hidesOnDeactivate=false)
- [x] 스킬 + 프롬프트 통합 검색 — 관련도(prefix>contains) → 최근 사용 → 알파벳 정렬
- [x] 최근 사용 이력 — `~/.airuncat/palette-history.json` (최대 50건, 원자 쓰기)
- [x] `↩` → NSPasteboard + `ITermController.insertText(cwd:)` + 자동 닫기
- [x] `⌘↩` → 클립보드 복사만
- [x] 삽입 대상 자동 감지 (active > idle, Claude, lastActivity 최신)
- [x] 스킬 주입 시 `"/name\n"` — Claude CLI slash command 즉시 실행
- [x] 팔레트 열 때마다 최신 스킬·프롬프트 재스캔
- [x] `Package.swift` macOS 14로 상향 (`.onKeyPress` 사용)
- [x] `ApplicationController` — CGEvent tap `CFMachPort` 생명주기 관리

**신규 파일:**
- `QuickPalette.swift` — `NSPanel` + SwiftUI `PaletteView` + 키 처리
- `GlobalShortcut.swift` — CGEvent tap 등록·해제 (`HandlerBox` 타입 안전)
- `PaletteViewModel.swift` — 검색·필터·히스토리 로직
- `ApplicationController.swift` — tap 생명주기 `@StateObject` 관리

**백로그:**
- [ ] Phase 11.1: 삽입 대상 수동 드롭다운 선택
- [ ] Phase 11.2: 사용자 정의 단축키 설정 UI

---

### Phase 12 — 세션 통계 [완료]

JSONL 파싱 집계로 Claude 세션 사용 패턴 시각화.

**구현:**
- [x] `StatsScanner`: `~/.claude/projects/` 전체 JSONL 순회, mtime 기반 증분 캐시
  - 세션 수, 활동 시간 (이벤트 타임스탬프 기반, 120min 캡)
  - 7×24 히트맵 배열 (mtime 기준 요일·시간대)
  - 스킬 사용 빈도 (tool_use name=Skill 이벤트, 4MB 이하 전체 / 초과 시 head+tail)
- [x] 캐시 — `~/.airuncat/stats-cache.json` (mtime 증분 업데이트, 원자 쓰기)
- [x] 기간 필터 이번 주 / 이번 달 / 전체
- [x] 자주 쓴 스킬 top-N 바 차트
- [x] Stats 탭 추가 (Sessions / Skills / Prompts / MCP / Stats)
- [x] 히트맵 컬러 — `accentColor.opacity(density)`, 셀 10×8pt

**신규 파일:**
- `StatsScanner.swift` — 집계 로직, cache IO
- `StatsStore.swift` — `@MainActor ObservableObject`, period 필터
- `StatsView.swift` — 기간 피커 + 요약 + 히트맵 + 스킬 바 차트

**백로그:**
- [ ] Phase 12.1: Gemini 세션 통계 통합 (Phase 4 이후)
- [ ] Phase 12.2: 프롬프트 사용 빈도 (palette-history.json 연동)

---

---

## 프로덕션 리뷰 (2026-06-22) — 완료 항목

Phase 11·12 완성 후 전체 코드 리뷰 실시. 완료된 수정 사항:

### 완료 (코드 수정)
- [x] `FileIOHelper.swift` 신규 — `splitLines / headData / tailData / jsonObject / firstLine / trim / mtime` 공통 유틸 추출. SessionScanner/GeminiScanner/StatsScanner 3곳의 중복 IO 헬퍼 제거.
- [x] `FrontmatterParser.swift` 신규 — 4군데 흩어진 YAML 프론트매터 파서 통합. PromptScanner 500줄 파서 제거. SkillScanner 내부 파서를 델리게이션으로 교체.
- [x] `PathConstants.swift` 신규 — 10+ 파일에 흩어진 `NSHomeDirectory() + appendingPathComponent` 패턴 중앙화 (claudeProjects/Commands/Rules/Settings, geminiCommands/Tmp, skills/prompts/statsCache/paletteHistory/customNames/mcpJson).
- [x] `SkillToggler.createSkill` 버그 수정 — link 경로와 record.id에 `name`(원본 입력값) 대신 `stem`(kebab-case 정규화) 사용. 스킬명 대소문자 불일치로 심볼릭 링크 경로가 틀리던 문제 해결.
- [x] `onChange(of:)` deprecated API 수정 — 5개 파일 (MenuContentView, MCPView, HarnessPopoverView, SkillsView, PromptLibraryView). macOS 14의 새 단일 클로저 형식으로 전환.
- [x] `StatsScanner` 캐시 무한 성장 수정 — `loadCache()`에 6개월(180일) pruning 추가. 오래된 JSONL 엔트리 자동 정리.
- [x] `StatsScanner.readSkillsUsed` 중복 IO 제거 — 자체 head/tail 구현 제거, `FileIOHelper.readLines` 사용.
- [x] `StatsScanner` magic number 제거 — `4 * 1024 * 1024` → `FileIOHelper.smallFileLimit` 통일.

### 백로그 (미수정, 향후 작업)

#### 코드 품질
- [ ] **P1: MemoryScanner 프론트매터 파서** — `metadata.type` 네스트 처리가 필요해 FrontmatterParser 직접 사용 불가. `FrontmatterParser.parseYAML`에 nested dict 지원 추가 후 MemoryScanner 간소화.
- [ ] **P2: `relativeTime` / `mtimeLabel` 중복** — MenuContentView, MemoryPopoverView, HarnessPopoverView 3곳에 각기 다른 상대 시간 포맷터 구현. 공통 `Date+RelativeLabel.swift` 익스텐션 추출.
- [ ] **P2: 파일 쓰기 원자성 불일치** — MCPManager/CustomNameStore는 `.atomic` 옵션, HarnessManager는 임시 파일 + rename 사용. 후자가 더 안전 — MCPManager도 통일.
- [ ] **P3: QoS 우선순위 혼용** — SessionStore는 `.utility`, MenuContentView/SkillsView는 `.background`. 스캔 타입별 기준 정립 필요.
- [ ] **P3: SkillToggler 이름 정규화 이중 처리** — `createSkill`에서도, `SkillsView`에서도 sanitize 수행. 한 곳에서만 처리하도록 정리.

#### 기능
- [ ] **Phase 11.1**: 팔레트 삽입 대상 수동 드롭다운 선택
- [ ] **Phase 11.2**: 사용자 정의 단축키 설정 UI
- [ ] **Phase 12.1**: Gemini 세션 통계 통합
- [ ] **Phase 12.2**: 프롬프트 사용 빈도 (palette-history.json 연동)
- [ ] **Phase 10.1**: AGENTS.md 지원
- [ ] **Phase 6.1**: MCP broken 배지 탐지
- [ ] **Phase 8.1**: Memory 전체 프로젝트 통합 뷰
- [ ] **Phase 9.1**: Hook 생성 폼
- [ ] **Phase 1.5**: Gemini 세션 재개 플래그 조사

---

## Next Action
- [ ] git push → PR 생성 (Phase 11·12 + 프로덕션 리뷰 수정 포함)
- [ ] 다음 Phase 선택 (Phase 11.1 팔레트 대상 선택 / Phase 12.1 Gemini 통계 중 택1)

## 주요 결정 / 기술 메모
- 형태: macOS 메뉴바 앱 (SwiftUI MenuBarExtra, `LSUIElement`)
- 빌드: Swift 6.3 + SwiftPM + CLT (풀 Xcode 불필요)
- 고양이: 벡터 드로잉 + 템플릿 이미지 (다크/라이트 자동)
- 데이터: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, mtime로 활성 판정
- 세션 이동: Warp는 AppleScript 미지원 -> 탭 포커스 불가 -> iTerm2로 전환
- 권한 영속: ad-hoc 서명은 재빌드마다 TCC 권한이 풀림 -> 자체 서명 인증서 `airuncat Self-Signed`로 사인
- 참고: ai-monitor(hyunho058)는 모니터링 전용, Gemini 로그 경로만 차용
