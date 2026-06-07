# /render-cat

고양이 프레임을 PNG 컨택트시트로 뽑아 눈으로 확인.

## Steps

1. 빌드: `cd /Users/jeong-ilin/study/clawde && swift build -c release`
2. 렌더: `./.build/release/Clawde --render-frames /tmp/clawde_frames.png`
3. `/tmp/clawde_frames.png` 를 열어 질주 프레임 + 수면 포즈를 확인한다.

## Usage

`CatRenderer`를 수정한 뒤 메뉴바에 올리기 전에 모양을 빠르게 검수할 때 사용.
