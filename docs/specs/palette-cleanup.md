---
title: "퀵 팔레트 시각/검색창 정리 spec"
date: 2026-06-27
status: approved   # draft | approved
---

# 목표
⌥Space 퀵 팔레트의 시각 일관성을 앱 전역 디자인 언어(상태 색 토큰)에 맞추고,
검색 결과/푸터의 군더더기를 정리한다. UI 개편 흐름(iter 1~8)의 마지막 손질.

# 범위
- In:
  1. **세션 피커 상태 점 색 통일** (핵심): `statusColor(for:)` 로컬 정의
     (green/yellow/secondary, `session.status` 기반) 제거 → `session.displayStatus`
     + `AiruncatDesign.statusColor`로 라우팅. 효과:
     - 앱 전역 상태 색 언어와 일치(idle=yellow 어긋남 제거).
     - **"응답 대기"(orange)** 세션이 피커에서도 드러남 — 현재 `status`만 봐서
       waiting을 표현 못 함. 앱 핵심 가치(대기 세션 우선)와 정합.
  2. **검색 결과 빈/플레이스홀더 카피 정리**: placeholder·빈 문구를 짧고 일관되게.
  3. **선택 행 가독성 점검**: `Color.accentColor` 배경 + 하드코딩 `.white` 텍스트가
     라이트 accent에서 대비가 약할 수 있음 → 표준 팔레트 패턴 유지하되 필요 시
     `.white`만 보정(아래 미해결 질문 참조).
- Out:
  - 검색 알고리즘 변경(현재 prefix=2/contains=1/recency 정렬 유지).
  - 카테고리 필터·핀 등 신규 기능 추가.
  - Skills/Prompts kind 배지에 색 추가 — 이미 폰트(monospace vs default)로 구분되고
    AI-typed가 아니라 색 추가는 무의미(MCP/Prompts 판단과 동일).

# 동작 / UI
- 세션 피커 메뉴의 각 세션 앞 점:
  - waiting → orange, working → green, idle → secondary, resting → secondary 0.4
    (= `AiruncatDesign.statusColor` 그대로).
- 나머지 레이아웃/단축키(↩ 삽입 / ⌘↩ 복사 / Esc 닫기)는 동일.

# 데이터 소스 / 의존
- 신규 데이터 없음. `SessionInfo.displayStatus`(이미 존재) 사용.
- `AiruncatDesign.statusColor(SessionDisplayStatus)` 재사용.

# 엣지케이스
- availableSessions는 Claude 전용(`aiKind == .claude`) → AI 색은 무의미(모두 Claude).
  상태 색만 적용.
- displayStatus가 waiting인 세션이 여러 개면 모두 orange 점 — 정상(피커에서 골라 삽입).
- 빈 세션 목록("삽입 대상 없음") 분기는 그대로.

# 검증 방법
- `swift build` 그린.
- `./build.sh` + 앱 재시작 후 ⌥Space로 팔레트 열어 세션 피커 점 색 확인
  (대기 세션이 있을 때 orange로 뜨는지). 라이브 수동 시나리오.
- diff 코드리뷰(stage 5) + 필요 시 Gemini 리뷰(stage 6).

# 미해결 질문
- 선택 행 텍스트: 시스템 accent가 밝은 색(노랑 등)일 때 `.white`가 안 보일 수 있음.
  (a) 그대로 두기, (b) accent 배경 위 `.white` 유지가 표준이라 OK로 간주,
  (c) 선택 배경을 accent 대신 `Color.primary.opacity(0.12)` + primary 텍스트로 전환.
  → 기본은 (b). (c)는 별도 판단 필요하면 알려주세요.
