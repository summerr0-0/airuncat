# Cat Design

메뉴바 고양이 렌더링 (`CatRenderer`).

## 캔버스 / 좌표계

- 캔버스 26 x 18 pt, AppKit `lockFocus` 기본 좌표 (원점 좌하단, 비반전).
- 결과 NSImage는 `isTemplate = true` → 시스템이 다크/라이트 틴팅.

## 모드

- `CatMode.running(Int)`: 다리/꼬리가 `phase`로 갤럽. 연관값 = 활성 세션 수.
- `CatMode.sleeping`: 웅크려 앉은 포즈 + 느린 꼬리 흔들림.

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

`CatRenderer` 수정 후 `/render-cat` 으로 `/tmp/clawde_frames.png` 컨택트시트를 뽑아 확인한다.
