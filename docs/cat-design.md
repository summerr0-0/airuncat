# Cat Design

메뉴바 고양이 렌더링 (`CatRenderer`).

## 캔버스 / 좌표계

- 캔버스 **32 x 22 pt** (구 26×18에서 확장 — 왼쪽 6pt: 버블 공간, 위 4pt: 귀 클립 방지).
- AppKit `lockFocus` 기본 좌표 (원점 좌하단, 비반전).
- 고양이는 **좌향**: `translateX(32,0) + scaleX(-1,1)` flip 적용 후 드로잉.
- `isTemplate`:
  - `waitingBubble=false` → `isTemplate=true` (시스템이 다크/라이트 틴팅, `NSColor.black` 드로잉)
  - `waitingBubble=true` → `isTemplate=false` (컬러 버블 필요), `NSColor.labelColor` 드로잉

## 모드

- `CatMode.running(Int)`: 다리/꼬리가 `phase`로 갤럽. 연관값 = 활성(active) 세션 수.
- `CatMode.sleeping`: 웅크려 앉은 포즈 + 느린 꼬리 흔들림.
- `waitingBubble: Bool`: 응답 대기 세션(`workState == .responded`) 있을 때 true → 고양이 우상단(cx=28.5, cy=18.0)에 red 배지 표시. flip 해제(`saveGraphicsState` + reset transform)후 screen 좌표로 드로잉.

## 구성 요소

- 몸/머리: `NSBezierPath(ovalIn:)` 채우기
- 귀: 삼각형 2개
- 꼬리: 두꺼운 곡선 스트로크, `sin(phase)`로 흔들림
- 다리(질주): 4개 라인, 발끝이 hip 기준 `cos/sin(phase + offset)`로 진동 (대각 트롯)
- 눈: compositing `.clear`로 구멍 punch

## 속도 매핑

`SessionStore.tick()`:
- running: `step = 0.28 + 0.16 * min(active, 4)` (바쁠수록 빠름)
- sleeping: `step = 0.05` (느린 숨/꼬리)
- 타이머 간격 0.07s 고정, `phase += step` 후 프레임 재생성.

## 검수

`CatRenderer` 수정 후 `/render-cat` 으로 `/tmp/airuncat_frames.png` 컨택트시트를 뽑아 확인한다.
