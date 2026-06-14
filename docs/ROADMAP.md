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
- [x] 저장소: `~/Obsidian/document/07_Prompts/PROMPT_*.md`
- [x] frontmatter 파서: title/tags/category/pinned, flow + block YAML 배열 지원
- [x] 카테고리 그룹 + 핀 고정 + 검색 필터
- [x] [⎘] 클립보드 복사 (1초 체크 피드백, Task cancel 중복 방지)
- [x] [▷] 활성 세션 iTerm 삽입 (클립보드+Cmd+V, 자동 실행 없음)
- [x] "Insert to: X" 헤더로 삽입 대상 명시
- [x] 탭 전환 시 재스캔 (`.onAppear + .task(id: scanID)`)
- [x] ITermController.findSessionID 헬퍼 추출 (focus + insertText 중복 제거)

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

## Next Action
- [ ] Phase 2 + 2.5 + 3 커밋 → PR 생성 (git push + gh pr create)
- [ ] Phase 4(Unified Control) 또는 Phase 1.5 백로그 아이템 선택

## 주요 결정 / 기술 메모
- 형태: macOS 메뉴바 앱 (SwiftUI MenuBarExtra, `LSUIElement`)
- 빌드: Swift 6.3 + SwiftPM + CLT (풀 Xcode 불필요)
- 고양이: 벡터 드로잉 + 템플릿 이미지 (다크/라이트 자동)
- 데이터: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, mtime로 활성 판정
- 세션 이동: Warp는 AppleScript 미지원 -> 탭 포커스 불가 -> iTerm2로 전환
- 권한 영속: ad-hoc 서명은 재빌드마다 TCC 권한이 풀림 -> 자체 서명 인증서 `airuncat Self-Signed`로 사인
- 참고: ai-monitor(hyunho058)는 모니터링 전용, Gemini 로그 경로만 차용
