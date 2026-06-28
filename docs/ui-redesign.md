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

## Iteration 4 — Skills 탭 AI 색 전파 (완료, build·실행 그린)
- LinkBadge C/G: **글자색 = AI 정체성**(Claude 보라/Gemini 청록), 글리프(✓/⚠/–)·배경 = 링크 상태.
  → 상태 정보 손실 없이 어느 AI 링크인지 즉시 식별.
- OrphanRow C/G 글자도 AI 색(경고 맥락 주황 배경 유지).
- 생성 폼 FormLinkToggle: ON 시 accent → AI 색.
- 이로써 AI 색 정체성이 Sessions·RecentlyClosed·Skills 전반에 일관 적용됨.

## Iteration 5 — 고양이 실루엣 (완료, render·실행 그린)
- 메뉴바 크기에선 실루엣이 전부 → 디테일 대신 **실루엣 명료도**를 개선(벡터/템플릿 유지).
- 달리기/수면 포즈 **귀를 더 뾰족·길게**(즉시 "고양이"로 읽힘).
- 달리기 **꼬리를 위로 말아올림**(처진 꼬리 → 경쾌·기민한 실루엣).
- `--render-frames` 컨택트시트로 2패스 시각 검증(목업 아님). build.sh로 라이브 반영.

## Iteration 6 — 고양이 더 다듬기 (완료, render·실행 그린)
- **갤로핑 바운스**: `bob = sin(phase*2)*0.7`로 몸·머리·귀·꼬리·hip이 위아래로 통통,
  발은 땅 고정 → 다리가 자연스레 늘었다 줄어듦(달리는 생기). 다리 amp/lift 소폭↑.
- **머즐(코) 범프**: 얼굴 앞에 작은 오발 → 어느 쪽을 보는지 명확, 스냅샷에서 스냇 느낌.
- 컨택트시트로 검증, build.sh 라이브 반영. (귀/꼬리는 iteration 5)

## Iteration 7 — 셸 헤더 색 전파 (완료, build·실행 그린)
- 헤더 summary의 **C는 Claude 보라 / G는 Gemini 청록**으로 칠해(`summary: String`→
  `summaryText: Text` 스팬 합성) 헤더도 AI 색 언어를 쓴다. "all quiet"/idle은 secondary.
- 헤더 **응답 대기 배지**: 하드코딩 `.orange` → `AiruncatDesign.statusColor(.waiting)`로
  라우팅(상태 색 토큰 단일화).
- **팝오버는 색 적용 보류** — Harness/CLAUDE.md/Memory/Tag는 Claude-vs-Gemini 대비형이
  아니라(AI-typed 아님) AI 색이 정보를 더하지 않음. MCP/Prompts와 같은 판단. 이미
  semantic 색(green pass·red deny·grade 배지)을 쓰고 있어 추가 전파 무의미.

# 다음 후보 (정책 필요 → 사용자 결정 후 진행)
- **Stats 탭**: 히트맵/바 색 — 단일 hue 선택은 디자인 정책(물어볼 것).
- **고양이**: 표정/포즈 — 큰 주관적 작업. `--render-frames` 컨택트시트로 시각 검증 가능.
- **퀵 팔레트**: 검색창 정리.
- 색 전파는 소진(셸 완료 · MCP/Prompts/팝오버는 AI-typed 아님 → 색 적용 무의미).
