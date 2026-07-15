# Claude Native Skills — airuncat 고유 스킬 저장소 폐지

## Goal

airuncat 고유 스킬 저장소(`~/.airuncat/skills/`)를 없애고 **Claude 네이티브 스킬
(`~/.claude/skills/<name>/SKILL.md`)을 원본**으로 삼는다. Claude는 기본(항상 활성)이고,
관리 대상은 **Gemini에 복제할지 여부(G 토글)** 하나만 남긴다.

사용자 결정(2026-07-14): "ai run cat 스킬을 클로드 스킬로 옮길거임. 이제 airuncat 고유의
skill은 없음. 클로드가 기본이고 gemini에 복제할지 말지 여부로 하자."

## Non-goals

- Gemini 커맨드 포맷 개선(현행 `.toml` symlink → SKILL.md 유지).
- 프로젝트 스킬(`<cwd>/.claude/{commands,skills}`) 동작 변경 — 읽기 전용 표시 그대로.
- Claude Code plugin/내장 스킬과의 이름 충돌 해소.

## 설계

### 데이터 모델

| 이전 | 이후 |
|------|------|
| 원본 `~/.airuncat/skills/SKILL_*.md` | 원본 `~/.claude/skills/<kebab>/SKILL.md` |
| C 토글: `~/.claude/commands/<n>.md` symlink | 없음 — 네이티브 스킬은 Claude가 자동 인식(항상 활성) |
| G 토글: `~/.gemini/commands/<n>.toml` symlink → store | G 토글: 동일 symlink, 대상만 `SKILL.md`로 |
| scope: global / project / native | scope: **native(=글로벌, 관리 대상)** / project |

### 1회 마이그레이션 (`SkillManager.migrateStoreToClaudeIfNeeded`, 앱 시작 시)

`~/.airuncat/skills/*.md` 각각에 대해 (kebab 이름 = `SKILL_` 제거 + 소문자 + `_`→`-`):

1. `~/.claude/skills/<kebab>/SKILL.md`가 **store를 가리키는 symlink**면 → symlink 제거 후
   원본 파일을 그 자리로 **move** (실체화. ai-slop-cleaner/learner/trace가 이 케이스).
2. 대상 디렉토리가 이미 실체로 존재하면 → skip (네이티브 우선, 원본 보존).
3. 없으면 → 디렉토리 생성 + move.
4. move 성공 시 구 링크 정리:
   - `~/.claude/commands/<kebab>.md` symlink(store 대상) → **제거** (네이티브가 대체).
   - `~/.gemini/commands/<kebab>.{toml,md}` symlink(store 대상) → 새 `SKILL.md`로 **재지정**
     (Gemini 복제 상태 보존).
5. 종료 시 store가 비면(.DS_Store 제외) 디렉토리 삭제. idempotent: store 없으면 no-op.

기존 `migrateFromObsidianIfNeeded`는 삭제 (store 디렉토리를 재생성하므로 공존 불가).

### 스캐너 (`SkillScanner`)

- `.global` scope 및 store 스캔 제거. scope = `.native` | `.project`.
- `SkillRecord`에서 `claudeState/claudeLinkPath/claudeError` 제거.
- 네이티브 스킬에 `geminiState`/`geminiLinkPath` 계산 추가 (`~/.gemini/commands/<n>.toml`).
- 고아 판정 단순화: 두 commands 디렉토리에서 **깨진 symlink만** orphan으로 표시
  (건강한 무관 링크는 사용자 소유물 — 건드리지 않음).

### 토글러 (`SkillToggler`)

- `enum AI` 제거. `enableGemini/disableGemini(_ skill)`로 단순화.
- `createSkill(name:description:linkGemini:)` → `~/.claude/skills/<n>/SKILL.md` 생성
  (frontmatter: `name`, `description`) + 선택적 Gemini 링크.
- `deleteSkill` → Gemini 링크 제거 + 스킬 디렉토리 제거. 안전 가드:
  경로가 `~/.claude/skills/` 아래일 때만. symlink 디렉토리(harness-main 등)는
  링크만 제거되고 원본은 남는다(FileManager.removeItem 의미론).
- `repairAll` → Gemini 깨진 링크만 수리.

### UI (`SkillsView`)

- C 배지 제거. 네이티브 행: G 토글 + 삭제. 프로젝트 행: P 배지만(현행 유지).
- 섹션: "글로벌"(로컬 네이티브) / "글로벌 · <출처>"(symlink 네이티브) / "프로젝트 · <폴더>".
- 생성 폼: C 체크박스 제거. 중복 검사는 `~/.claude/skills/<n>` 존재 여부.

### 수동 정리 (마이그레이션 전 1회)

store의 `gemini-review.md`, `render-cat.md`, `run-clawde.md`는 이 repo
`.claude/skills/`와 **byte-identical 중복**(diff로 확인) → store에서 삭제하고
프로젝트 스킬만 남긴다 (글로벌 중복 방지, 데이터 손실 없음).

## 검증

1. `swift build` 그린.
2. 마이그레이션 시뮬레이션: 임시 HOME 없이 실제 실행 전 dry-run 불가하므로,
   실행 후 `~/.claude/skills/` 실체화·`~/.airuncat/skills` 소멸·Gemini symlink 재지정을 ls로 확인.
3. UI: Skills 탭에서 글로벌/프로젝트 섹션, G 토글 온오프, 생성/삭제 동작 확인.
4. 팔레트(⌥Space)에 스킬 계속 노출 (PaletteViewModel은 id만 사용 — 영향 없음).
