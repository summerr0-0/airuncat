<!-- BEGIN:airuncat-agent-rules -->
# airuncat 작업 전 필독

- 빌드는 `./build.sh` (SwiftPM + Command Line Tools). 이 맥엔 풀 Xcode가 없으니 `xcodebuild` / `.xcodeproj` 를 만들거나 쓰지 마라.
- 세션 데이터(`~/.claude/projects/**/*.jsonl`, `~/.gemini/tmp/**`)는 **읽기 전용**. 파싱만 하고 절대 쓰지 마라.
- 메뉴바 아이콘 NSImage는 `isTemplate = true` 유지 (다크/라이트 자동 대응). 색을 직접 칠하지 마라.
- 고양이는 벡터 드로잉이다. 외부 PNG/스프라이트 에셋을 추가하지 마라.
- UI/렌더 변경 후 반드시 `./build.sh && open airuncat.app` 로 실제 메뉴바에서 확인.
<!-- END:airuncat-agent-rules -->
