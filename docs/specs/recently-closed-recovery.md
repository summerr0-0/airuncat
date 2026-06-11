# Spec: Recently-Closed Session Recovery

## 목표
세션을 실수로 닫은 후 30초 이내에 드롭다운에서 바로 재개할 수 있게 한다.

## 범위

### In
- 종료된 세션을 30초간 드롭다운에 "최근 종료" 섹션으로 표시
- 클릭 시 iTerm2에서 세션 재개
- 30초 경과 시 자동 제거
- Claude / Gemini 모두 지원

### Out
- 30초 초과 세션 복구
- 알림 발송 (조용한 드롭다운 UI만)
- 영구 히스토리 / 세션 로그 저장

## 동작 상세

### 버퍼 관리 (`SessionStore`)
- `recentlyClosed: [(info: SessionInfo, closedAt: Date)]` 배열 유지
- `refresh()` 후 이전 `visibleSessions`와 비교 → 사라진 세션을 `recentlyClosed`에 추가
- 이미 버퍼에 있는 세션은 중복 추가 안 함
- 30초 초과 항목은 애니메이션 tick(0.07s)마다 정리

### UI (`MenuContentView`)
- 현재 활성 세션 목록 아래 구분선 + "Recently Closed" 헤더
- 각 행: `[C/G]  프로젝트명  ·  N초 전` (회색 텍스트)
  - Claude: hover 레이블 "Resume" — `claude -r <id>` 재개
  - Gemini: hover 레이블 "Open new" — 새 세션 (맥락 복구 아님)
- 클릭 시 `ITermController.open(session)` 호출 (기존 로직 재사용)
- 버퍼가 비어 있으면 섹션 전체 숨김
- 최대 5개 제한 (초과 시 가장 오래된 것부터 제거)

### 재개 동작
- **Claude**: `claude -r <sessionId>` — 정확한 세션 재개
- **Gemini**: `cd <cwd> && gemini` — 새 세션으로 같은 디렉터리 열기 (Gemini는 세션 ID 재개 미지원)

## 엣지케이스
- 앱 시작 직후: 이전 실행 때 종료된 세션은 버퍼에 없음 (메모리 한정, 디스크 미저장)
- cwd가 빈 세션: 재개 불가 → 버퍼에 추가하지 않음
- 같은 세션이 재시작되어 다시 `visibleSessions`에 나타나면 버퍼에서 제거

## 검증
1. Claude 세션 종료 → 30초 내 드롭다운에 표시 확인
2. Reopen 클릭 → iTerm2에서 `claude -r <id>` 실행 확인
3. 30초 경과 → 자동 제거 확인
4. Gemini 세션 종료 → 동일하게 표시·재개 확인
5. cwd 없는 세션 → 버퍼에 미추가 확인
