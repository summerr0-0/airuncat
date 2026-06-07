# Menu Bar Icon = Template Image

메뉴바 아이콘(고양이)은 항상 template image여야 한다.

- `CatRenderer`가 반환하는 NSImage는 `isTemplate = true`.
- 색을 직접 칠하지 마라. 검정 실루엣 + 알파만 그리면 시스템이 다크/라이트에 맞춰 자동 틴팅한다.
- 눈 등 내부 디테일은 별도 색 대신 compositing `.clear`로 구멍을 뚫어 표현한다.
