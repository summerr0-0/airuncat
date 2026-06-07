# Sessions Are Read-Only

`~/.claude/projects/**/*.jsonl` 와 `~/.gemini/tmp/**` 는 다른 AI 세션의 실시간 기록이다.

- 파싱(읽기)만 한다. 쓰기 / 이동 / 삭제 금지.
- 큰 파일은 head/tail 청크만 읽고 mtime으로 캐시한다 (`SessionScanner` 참고).
- 세션 이동/재개는 원본 파일을 건드리지 않고 iTerm2 탭 포커스 또는 `claude -r <id>` (`ITermController`)로만 한다.
