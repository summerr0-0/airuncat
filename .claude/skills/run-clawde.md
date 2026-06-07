# /run-clawde

airuncat 재빌드 후 메뉴바에서 재시작.

## Steps

1. 기존 인스턴스 종료: `pkill -f "airuncat.app/Contents/MacOS/airuncat"`
2. 빌드 + 번들: `cd /Users/jeong-ilin/study/clawde && ./build.sh`
3. 실행: `open /Users/jeong-ilin/study/clawde/airuncat.app`
4. 확인: `pgrep -lf "airuncat.app/Contents/MacOS/airuncat"`

## Usage

UI나 렌더 로직을 바꾼 뒤 항상 실행해서 실제 메뉴바 동작을 확인한다.
