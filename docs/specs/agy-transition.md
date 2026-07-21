# Antigravity(agy) 전환 — G 복제 재지정 + 세션 관제

## Goal

gemini CLI 지원종료(2026-06, IneligibleTierError) 후속으로 airuncat의 Gemini 연동 2축을
공식 후계인 Antigravity CLI(`agy`)로 옮긴다. agy는 `~/.gemini`을 홈으로 공유한다.

사용자 지시: "gemini말고 그 antigravity? 이걸로 명령하도록 해줘" + "이어서 해줘".

## A. G 복제 재지정 (스킬)

- **이전**: `~/.gemini/commands/<n>.toml` symlink → SKILL.md (죽은 gemini CLI의 커맨드 포맷)
- **이후**: `~/.gemini/skills/<name>` **디렉토리 symlink** → `~/.claude/skills/<name>`
  - 근거: Antigravity 공식 공유 스킬 경로(IDE+CLI 공용), SKILL.md 포맷이 Claude와 동일 — 변환 불필요
- 마이그레이션 `migrateGeminiLinksToAgyIfNeeded`(시작 시 1회, idempotent):
  commands의 symlink 중 `~/.claude/skills/`를 가리키는 것 → skills 디렉토리 symlink로 전환.
  skills에 같은 이름 실체가 있으면 자리 보존(스킵), legacy 링크는 어느 쪽이든 제거.
- `SkillToggler.enableGemini` = 디렉토리 symlink 생성, `disableGemini`/`deleteSkill` =
  신형 링크 + legacy toml/md 중 이 스킬을 가리키거나 깨진 것만 제거.

## B. 세션 관제 (AgyScanner ← GeminiScanner)

- 소스 (전부 읽기 전용):
  - `~/.gemini/antigravity-cli/conversations/<id>.db` — 활동 = db/-wal 최신 mtime, maxAge 48h.
    내용은 프로토버프 blob이라 파싱하지 않는다 (summaries db는 실측상 0행이라 불신).
  - `history.jsonl` tail 256KB — conversationId별 첫/마지막 프롬프트, workspace, 타임스탬프.
    `agy -p`는 여기 기록 안 됨.
  - `cache/last_conversations.json` — cwd 폴백 (id→cwd 역매핑).
- workState: 마지막 유저 입력 ts보다 db mtime이 5초 이상 뒤면 `.responded`(응답 옴), 아니면 `.working`.
  history가 없으면 `.working` (보수적 — 버블 오탐 방지).
- 재개: `agy --conversation <id>` (ITermController). 프로세스 감지: comm == "agy" (Go 단일 바이너리).
- `agyPath`: `~/.local/bin/agy` 직접 확인 → `which agy` 폴백 (GUI 앱 PATH에 ~/.local/bin 없음).
- 검증 CLI: `airuncat --agy-scan`.

## 검증 (실측)

1. `--agy-scan`: 신규 `agy -p` 대화가 1초 만에 감지, cwd 폴백으로 projectName "clawde" 표시 ✓
2. 48h 초과 대화 필터링 ✓ (구 대화 미표시)
3. 앱 재시작 후 마이그레이션: commands 비워짐, skills에 architect/code-review/commit
   디렉토리 symlink 생성, 기존 실체 3개(convert-tsv 등) 보존 ✓
4. `swift build` 그린, 죽은 코드(shellEscapeSingle in ProcessDetector) 제거 ✓

## Non-goals

- agy 대화 SQLite blob 디코딩 (프로토버프 — 취약, 읽기 전용 원칙 유지)
- Stats/사용량의 agy 집계 (Claude 전용 유지)
- `~/.gemini/skills`의 기존 실체 스킬과 Claude 스킬의 내용 동기화
