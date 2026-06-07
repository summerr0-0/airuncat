# Spec: launchagent-login-autostart

## Meta
- **Created**: 2026-06-06
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-06-06

## Goal
macOS 로그인 시 Clawde가 자동으로 실행되도록 LaunchAgent를 설치한다.

## Non-goals
- 앱 업데이트 자동 배포 (Sparkle 등)
- notarization / App Store 배포
- 시스템 전체 LaunchDaemon (root 권한 불필요)
- GUI 설정 패널 (메뉴바 토글 UI는 별도 피처)

## Research
- `build.sh`는 프로젝트 루트에 `Clawde.app` 번들 조립 후 ad-hoc/자체서명 코드사인 — `build.sh:1-25`
- 번들 ID: `com.jeongilin.clawde` — `Info.plist:8`
- 현재 앱 위치: `/Users/jeong-ilin/study/clawde/Clawde.app` (프로젝트 디렉토리, 비표준)
- LaunchAgent 경로 패턴: `~/Library/LaunchAgents/{bundle-id}.plist` (기존 com.google.*, com.valvesoftware.* 참고)
- LaunchAgent 등록 방법: `launchctl load` (구형, deprecated) vs `launchctl bootstrap gui/$(id -u)` (macOS 10.11+, 권장)
- LSUIElement = true → Dock 아이콘 없음, 메뉴바 전용 — `Info.plist:20`
- `build.sh`에 install 스텝 추가 가능 (set -e 사용 중, 오류 시 즉시 중단)
- 기존 LaunchAgent 비활성화: `launchctl bootout gui/$(id -u) {plist}` 또는 `launchctl unload`

## Confirmed Goal
`~/Library/LaunchAgents/com.jeongilin.clawde.plist`를 생성·등록해 macOS 로그인 시 Clawde.app이 자동 실행된다. 설치는 `build.sh` 끝에 통합한다. `uninstall.sh`로 제거도 가능하다. 재로그인 후 아무것도 안 해도 메뉴바에 고양이가 나타난다.

## Decisions

### D1: 설치 트리거 — build.sh 끝에 통합
- **Status**: resolved
- **Rationale**: 빌드 후 자동으로 plist 생성·등록. 매 빌드마다 경로가 갱신되므로 프로젝트 이동 후 재빌드 시 자동 수정. **Steelman 반론**: build.sh는 빌드 도구이지 인스톨러가 아니므로 단일책임 위반이라는 주장. **반박**: build.sh는 이미 코드사인(설치 부작용)을 포함하고 있어 "빌드 = 로컬 배포"가 이 프로젝트의 기존 패턴. 개인 도구이므로 별도 파일보다 단일 스크립트가 실용적. 향후 분리가 필요하면 `INSTALL=1 ./build.sh` 플래그로 격리 가능.

### D2: 앱 위치 — 프로젝트 폴더 (`/Users/jeong-ilin/study/clawde/Clawde.app`)
- **Status**: resolved
- **Rationale**: /Applications 복사는 경로 관리가 단순해지지만 매 빌드마다 복사 필요. 프로젝트 폴더 유지로 개발 흐름 간소화. 이동 시 재빌드로 plist 재생성.

### D3: 제거 — `uninstall.sh` 별도 작성
- **Status**: resolved
- **Rationale**: `launchctl bootout gui/$(id -u) {plist}` 실행 → launchd가 실행 중인 Clawde를 종료하고 서비스를 등록 해제. 그 후 plist 파일 삭제. bootout이 프로세스 종료까지 처리하므로 별도 kill 불필요. install과 분리해 실수로 삭제 방지.

### D4: launchctl 등록 방식 — `bootstrap gui/$(id -u)`
- **Status**: resolved
- **Rationale**: macOS 10.11+ 권장 방식. `launchctl load`는 macOS 11+에서 deprecated. 재빌드 시 기존 서비스를 `bootout` 후 `bootstrap`해 경로 갱신 보장.

### D5: 중복 실행/경로 갱신 — 매 build.sh 실행마다 무조건 bootout → bootstrap
- **Status**: resolved
- **Rationale**: bootout은 서비스가 등록되지 않은 경우 non-zero 종료. build.sh의 `set -e` 환경에서 스크립트가 중단되지 않도록 `launchctl bootout ... || true` 로 suppress. 그 뒤 무조건 `launchctl bootstrap ...` 실행. 이 unconditional 순서가 "이미 로드됨", "미등록", "경로 변경 후 재빌드" 세 케이스를 모두 커버.

### D6: plist 절대경로 — `$(cd "$(dirname "$0")"; pwd)` (assumed)
- **Status**: assumed
- **Rationale**: launchd는 ProgramArguments에 절대경로 필요. `$(dirname "$0")`는 상대경로를 줄 수 있으므로 `$(cd "$(dirname "$0")"; pwd)`로 절대경로 확보.

## Constraints
- plist의 `ProgramArguments`는 반드시 절대경로 (launchd 요구사항)
- build.sh의 `set -e` 환경에서 bootout 실패(미등록 상태)가 스크립트를 중단하면 안 됨 → `|| true`
- `~/.claude/projects/**/*.jsonl` 쓰기 금지 (read-only-sessions.md rule)
- `swift build` / `./build.sh`만 사용 (clt-build-only.md rule)

## Known Gaps
(none)

## Requirements

### R0: 로그인 시 Clawde 자동 실행

#### R0.1: 재로그인 후 Clawde가 자동 시작된다
- **Given**: LaunchAgent가 설치된 상태에서 macOS에 로그아웃 후 재로그인
- **When**: 세션이 시작된다
- **Then**: 아무 작업 없이 메뉴바에 고양이 아이콘이 나타난다

---

### R1: build.sh 실행 시 LaunchAgent plist 생성·등록 (D1, D2, D4, D5, D6)

#### R1.1: build.sh가 절대경로가 박힌 plist를 생성한다
- **Given**: `/Users/jeong-ilin/study/clawde/build.sh` 실행
- **When**: 빌드·번들 조립 완료 후 plist 생성 단계
- **Then**: `~/Library/LaunchAgents/com.jeongilin.clawde.plist`가 생성되고, `ProgramArguments`에 `/Users/jeong-ilin/study/clawde/Clawde.app/Contents/MacOS/Clawde` 절대경로가 포함된다

#### R1.2: build.sh가 LaunchAgent를 등록(bootstrap)한다
- **Given**: plist가 생성된 직후
- **When**: `launchctl bootstrap gui/$(id -u)` 실행
- **Then**: LaunchAgent가 등록되고 Clawde가 즉시 실행된다

#### R1.3: 이미 등록된 LaunchAgent가 있어도 build.sh가 중단되지 않는다
- **Given**: 이전 build.sh 실행으로 LaunchAgent가 이미 로드된 상태
- **When**: build.sh를 다시 실행한다
- **Then**: `bootout || true`로 기존 서비스를 종료하고 새 경로로 재등록. build.sh는 오류 없이 완료된다

#### R1.4: 미등록 상태에서 build.sh를 실행해도 중단되지 않는다
- **Given**: LaunchAgent가 등록되지 않은 초기 상태
- **When**: build.sh를 처음 실행한다
- **Then**: bootout 실패를 `|| true`로 무시하고 bootstrap이 정상 진행된다

---

### R2: uninstall.sh로 LaunchAgent 제거 (D3)

#### R2.1: uninstall.sh가 실행 중인 Clawde를 종료하고 서비스를 해제한다
- **Given**: LaunchAgent가 등록되고 Clawde가 실행 중
- **When**: `./uninstall.sh` 실행
- **Then**: `launchctl bootout`으로 Clawde 프로세스가 종료되고 서비스가 등록 해제된다

#### R2.2: uninstall.sh가 plist 파일을 삭제한다
- **Given**: `~/Library/LaunchAgents/com.jeongilin.clawde.plist` 존재
- **When**: uninstall.sh 실행
- **Then**: plist 파일이 삭제되고 재로그인 시 Clawde가 자동 실행되지 않는다

## Tasks

### T1: build.sh에 LaunchAgent 설치 스텝 추가 [vertical]
- **Fulfills**: R0.1, R1.1, R1.2, R1.3, R1.4
- **Depends on**: (none)
- **Files**: `build.sh`
- plist 템플릿을 heredoc으로 생성 (`ProgramArguments`에 절대경로)
- `launchctl bootout gui/$(id -u) {plist} || true`
- `launchctl bootstrap gui/$(id -u) {plist}`

### T2: uninstall.sh 작성 [vertical]
- **Fulfills**: R2.1, R2.2
- **Depends on**: (none)
- **Files**: `uninstall.sh` (신규)
- `launchctl bootout gui/$(id -u) {plist} || true`
- `rm -f {plist}`
- 실행 권한(`chmod +x`) 포함

## External Dependencies

### Pre-work
- (none)

### Post-work
- `./build.sh` 실행 후 로그아웃·재로그인으로 자동 실행 확인
- `./uninstall.sh` 후 재로그인 시 미실행 확인
