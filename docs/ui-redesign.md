---
title: "UI 개편 — 디자인 언어 & 진행 로그"
date: 2026-06-24
status: active
---

# 원칙 (사용자 지시)
- 디자인부터 개편하되 **목업 금지 — 동작하는 코드로** 바꾼다.
- **깡통(빈 껍데기) 금지** — 모든 요소는 실제 데이터·동작에 연결.
- 안 되는 것/정책 필요한 건 **물어본다**.

# 확정된 디자인 언어 (정책 답변)

## 컬러 정체성: "AI별 색 구분 + 상태색 강화"
- **AI 종류 색**(`AiruncatDesign.aiColor`): Claude=보라(0.55,0.40,0.95), Gemini=청록(0.20,0.65,0.70).
- **상태 색**(`AiruncatDesign.statusColor`): 응답대기=주황 · working=초록 · idle=secondary · resting=secondary 40%.
- accent는 macOS 시스템 설정 유지(브랜드 색 강제 안 함).

## 레이아웃 방향: "상태 우선 (Status-first)"
- 세션을 **상태 우선 정렬**: 응답 대기 > 작업 중 > idle > 휴식, 동률은 최근순.
- **응답 대기(나를 기다리는) 세션을 맨 위로** 띄우고 주황 구분선으로 분리.

# 토큰 (실제 사용 중인 것만)
`Sources/airuncat/DesignSystem.swift` — `AiruncatDesign.aiColor / statusColor / statusLabel`.
`Sources/airuncat/SessionScanner.swift` — `SessionDisplayStatus`(waiting/working/idle/resting) + `SessionInfo.displayStatus`.

# 진행 로그

## Iteration 1 — Sessions 행 (완료, build·실행 그린)
- `SessionDisplayStatus` 모델: workState + recency(status)를 사용자 관점으로 통합.
- 상태 우선 정렬 + 응답 대기 그룹을 상단에 분리(주황 2pt 구분선).
- 행: 상태색 캡슐 + **상태 라벨**(응답대기는 볼드 주황) + **색 구분 C/G 배지** + 제목/서브타이틀.
- 응답 대기 행은 **주황 배경 워시**로 즉시 식별.
- RecentlyClosed의 C/G도 색 구분 적용.
- 죽은 코드 `statusBarColor` 제거.

### 검증
- `swift build` 그린, `build.sh` 번들 + 실행 크래시 없음.
- 육안 확인 필요(메뉴바 드롭다운): 사용자.

## Iteration 2 — 팝오버 전파: Memory (완료, build·실행 그린)
- Memory 타입 색을 `AiruncatDesign.memoryTypeColor`로 중앙화(중복 제거, 색 정체성 통일).
- 타입 섹션 헤더에 **색 점** 추가(Sessions 상태점 언어 전파).
- 레코드 행에 **타입색 캡슐**(좌측 2.5pt) — Sessions 행 상태 캡슐과 동일 언어.
- 로컬 `typeColor` 죽은 코드 제거.
- Tag 팝오버는 이미 tagColor 사용(일관), ClaudeMd는 단순 → 보류.

## Iteration 3 — 셸(헤더/탭) (완료, build·실행 그린)
- **헤더**: 응답 대기 세션이 있으면 `bell.fill` + "N 대기"를 **주황으로 가장 먼저** 표시(status-first 연결).
  기존 summary(active/idle)는 유지. `waitingCount` 실데이터 연결.
- **탭 바**: 텍스트 탭 → **아이콘 탭**(rectangle.stack/wand.and.stars/text.bubble/puzzlepiece/chart.bar).
  활성 탭만 라벨 펼침(Capsule, accent) — 320pt에 5탭 깔끔히. 전환 시 0.15s 애니메이션. help 툴팁.
- SF Symbol 6종 모두 존재 검증(blank 아이콘 없음). `.fill` 변형은 미존재 위험으로 미사용.

# 다음 후보 (사용자 피드백 후 진행)
- **셸**: 헤더(airuncat 타이틀 + summary) / 탭 바 — 색·위계·아이콘.
- **팝오버**: Harness(점수 배지), CLAUDE.md, Memory, Tag — 같은 언어 전파.
- **Stats 탭**: 히트맵/바 차트 색을 디자인 토큰에 맞춤.
- **고양이**: 표정/포즈 개선(별도, 벡터 유지).
- **퀵 팔레트**: 검색창 시각 정리.
