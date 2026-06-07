# /run-clawde

Clawde 재빌드 후 메뉴바에서 재시작.

## Steps

1. 기존 인스턴스 종료: `pkill -f "Clawde.app/Contents/MacOS/Clawde"`
2. 빌드 + 번들: `cd /Users/jeong-ilin/study/clawde && ./build.sh`
3. 실행: `open /Users/jeong-ilin/study/clawde/Clawde.app`
4. 확인: `pgrep -lf "Clawde.app/Contents/MacOS/Clawde"`

## Usage

UI나 렌더 로직을 바꾼 뒤 항상 실행해서 실제 메뉴바 동작을 확인한다.
