# Data Sources

airuncat이 읽는 외부 데이터와 세션 재개 메커니즘.

## Claude Code 세션

- 위치: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`
- 파일 1개 = 세션 1개. 파일명 stem = `sessionId` (UUID, `claude -r`에 사용).
- 각 라인은 JSON 이벤트. airuncat이 쓰는 `type`:
  - `ai-title` → `aiTitle`: 자동 생성 세션 제목 (드롭다운 제목)
  - `user`: `message.content`(첫 실제 지시 추출), `cwd`, `gitBranch`, `timestamp`
  - `assistant`: `message.content[]`의 `tool_use` → 마지막 도구/인자 = "지금 하는 일"
- 활성 판정은 파일 **mtime** 기준 (timestamp 파싱보다 싸고 안정적):
  - active < 90초, idle < 30분, 그 외 resting
- 성능: `size <= 4MB`면 전체 파싱, 크면 head/tail 512KB만. mtime 동일하면 캐시 재사용.

## Gemini CLI 세션 (Phase 4 예정)

- 위치: `~/.gemini/tmp/<hash>/chats/*.jsonl` (참고: hyunho058/ai-monitor)
- 아직 미연동. 통합 시 SessionScanner에 소스를 추가한다.

## 세션 이동 (iTerm2)

클릭 시 그 세션이 떠 있는 iTerm2 탭으로 포커스, 없으면 새 탭에서 재개 (`ITermController`).

1. AppleScript로 모든 iTerm 세션의 `(id, tty)` 나열
2. 각 tty의 프로세스 cwd를 `ps -t` + `lsof -d cwd`로 구해 세션 cwd와 매칭
3. 매칭되면 그 탭/세션을 `select` + `activate` (탭 단위 정확 포커스)
4. 매칭 실패 시 새 iTerm 창에서 `cd <cwd> && claude -r <id>`

배경: Warp는 AppleScript 미지원이라 탭 포커스가 불가능 -> iTerm2로 전환.
airuncat.app은 자체 서명 인증서(`airuncat Self-Signed`)로 사인하므로, 자동화/접근성 권한이
재빌드 후에도 유지된다 (ad-hoc 서명은 빌드마다 권한이 풀림).
