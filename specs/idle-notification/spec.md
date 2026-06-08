# Spec: 입력 대기 / 작업 완료 알림

## 목표

Claude 세션이 작업을 마치고 사용자 입력을 기다리는 상태로 전환될 때
macOS 알림을 보내, 딴짓 중에도 세션을 놓치지 않게 한다.

## 범위

### In

- 세션 상태 `active → idle` 전환 시 macOS 알림 발송
  - 알림 제목: 세션 표시 이름 (customName ?? title)
  - 알림 본문: "입력 대기 중"
- 알림 클릭 → 해당 세션 iTerm2 탭 포커스 (ITermController.open)
- 앱 최초 실행 시 알림 권한 요청 (`UNUserNotificationCenter`)
- 같은 세션의 `active → idle` 전환은 한 번만 알림 (재진입 중복 방지)
- 앱 기동 직후 이미 idle인 세션은 알림 생략 (기존 세션 노이즈 방지)

### Out

- `idle → resting` 전환 알림 (범위 외)
- 배지(Badge) / 사운드 커스터마이징 (기본값 사용)
- 알림 on/off 설정 UI (macOS 시스템 설정에서 제어)

## 동작 흐름

```
SessionStore.refresh() 완료
  ↓
이전 상태(prevStates) vs 새 상태 비교
  ↓
prevState == .active && newState == .idle ?
  ↓ Yes
NotificationManager.send(session)
  ↓
UNUserNotificationCenter: 알림 발송

사용자 클릭
  ↓
UNUserNotificationCenterDelegate.didReceive
  ↓
ITermController.open(sessionId, cwd)
```

## 엣지케이스

- 앱 기동 시 스캔 첫 결과는 prevStates가 비어있음 → 전환 감지 안 함 (노이즈 방지)
- active 였다가 다음 스캔에서 바로 resting이 되는 경우 (긴 스캔 간격) → 알림 발송
- 알림 권한 거부 시: 조용히 무시, 앱 동작에 영향 없음
- 같은 세션이 active → idle → active → idle 반복: 매 전환마다 알림 (정상)
- 여러 세션이 동시에 전환: 각각 개별 알림

## 구현 파일

- `NotificationManager.swift` (신규) — 권한 요청, 알림 발송, 클릭 핸들러
- `SessionStore.swift` — `prevActiveIds: Set<String>` 추가, refresh 후 전환 감지
- `AiruncatApp.swift` — NotificationManager 초기화 (권한 요청 시점)

## 검증

1. `./build.sh` 그린
2. active 세션이 idle로 바뀌면 알림 표시
3. 알림 클릭 시 iTerm2 탭 포커스
4. 앱 기동 직후 기존 idle 세션은 알림 없음
5. 알림 권한 거부 시 앱 정상 동작
