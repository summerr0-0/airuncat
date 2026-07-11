---
title: "Phase 15.1 — 글로벌 레시피 GUI"
date: 2026-07-10
status: active
---

# 목표

OMC 갭 백로그(T2/T5)와 statusline(T3)이 만든 **글로벌 레시피**들에 GUI를 붙인다.
현재 표면이 디버그 CLI뿐(`--hook-recipe`, `--statusline`)이라 실사용 진입점이 없다.

대상 4종 (모두 airuncat 저작·검증 스크립트, `~/.claude/settings.json` 전역):
| id | 종류 | 이벤트 | 하는 일 |
|----|------|--------|---------|
| session-telemetry | 훅 | SessionEnd | 세션 메트릭(지속시간·메시지/도구 수) 기록 |
| subagent-tracker | 훅 | SubagentStop | 서브에이전트 이벤트 누적 기록 |
| rules-injector | 훅 | PreToolUse | 편집 파일에 매칭되는 rules 주입(해시 중복 방지) |
| statusline | statusLine | (렌더마다) | 네이티브 ctx %·rate limits 캐시 + "모델·ctx%" 표시 |

# 설계 원칙 (Phase 15 리뷰어 스틸맨 반영)

1. **Harness 팝오버에 넣지 않는다** — 거긴 프로젝트 스코프(점수도 프로젝트-로컬).
   전역 토글은 별도 표면에.
2. **토글 = 설치/제거** — 프로젝트 레시피의 "비활성 추가→검토→켜기"와 다른 의미임을
   UI에서 명확히(스코프 라벨 "전역", 설명 상시 노출). 자체 저작·검증 스크립트라
   직접 토글 허용(15 정합화 §2에서 승인된 예외).
3. **켜기 전에 뭘 켜는지 보이게** — 각 행에 설명 + 이벤트 + 상태 경로. 스크립트
   전문 보기는 소스 파일 열기(Finder)로 갈음.

# 범위

**In:**
- `MenuContentView`에 **6번째 탭 "Global"** (icon: `globe`) — "Hooks"는 Harness 팝오버의
  hooks 섹션과 혼동되고 statusline은 훅이 아님(리뷰어 지적). 스코프가 구분 차원.
  탭 바는 활성 탭만 라벨 펼침이라 6탭 수용 확인됨(리뷰어 계산 ~240pt < 304pt).
  Phase 9(설정 패널)가 생기면 그리로 접힐 수 있음을 전제.
- 신규 `GlobalRecipesView.swift`: 레시피 4종 행(이름·설명·이벤트 태그·"전역" 배지·토글)
  + statusline은 `.foreign` 상태(외부 statusline 존재) 시 토글 비활성 + 안내.
- **행 클릭 = 스크립트 본문 펼침**(인앱, monospaced) — 스크립트는 Swift 상수라 설치 전에도
  가용. "켜기 전에 뭘 켜는지" 원칙을 설치 여부와 무관하게 충족.
  (Finder/기본앱 열기는 미설치 시 파일이 없어 부적합 — 리뷰어 지적)
- 토글 핸들러: `HookRecipeManager.install/uninstall`, `StatuslineManager.install/remove`
  — Task.detached 후 상태 재조회. **진행 중 토글 비활성(스피너)** — 동시 read-modify-write 방지.
  오류는 행 아래 인라인 표시.
- 상태 조회: `isInstalled`/`status()` 재사용. **단 1건 매니저 가드 추가**(로직 무변경 예외):
  settings.json이 *존재하는데 파싱 불가*면 install 거부(파손 파일을 빈 {}로 덮는 사고 방지).

**Out:**
- hook-state 데이터 열람 UI(기록된 메트릭/서브에이전트 뷰) — Phase 15.2 후보.
- 레시피 신규 저작/편집.
- 프로젝트 레시피와의 통합 뷰(의미가 달라 분리 유지).

# UI

```
[Sessions][Skills][Prompts][MCP][Stats][Hooks]   ← 6번째 탭
┌──────────────────────────────────────────────┐
│ 글로벌 레시피 — Claude Code 전역에 설치됩니다   │
│                                                │
│ 세션 텔레메트리            SessionEnd  [전역] ◉ │
│  세션 종료 시 지속시간·도구 수 기록              │
│ 서브에이전트 트래커        SubagentStop [전역] ○ │
│  ...                                           │
│ Rules 주입기               PreToolUse  [전역] ○ │
│  ...                                           │
│ ───────────────────────────────────────────── │
│ statusline                 상태줄      [전역] ◉ │
│  네이티브 ctx%·rate limit 캐시 + 상태줄 표시     │
│  (외부 statusline 감지 시: "기존 설정 있음 —    │
│   airuncat이 덮지 않습니다" + 토글 비활성)       │
└──────────────────────────────────────────────┘
```

- 행 클릭 = 스크립트 본문 펼침/접힘(인앱 미리보기).
- 토글 색: 설치됨 = Claude 보라(디자인 토큰), 미설치 = secondary.
- "새 세션부터 적용" 캡션은 **훅 3종 행에만**(훅 설정은 세션 시작 시 스냅샷).
  statusline은 렌더마다 호출이라 즉시 적용 — 캡션 없음.

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| statusline `.foreign` | 토글 비활성 + 기존 command 표시("덮지 않음", C5) |
| settings.json 존재하나 파싱 불가 | install 거부 + 인라인 오류(파손 파일 클로버 방지 — 매니저 가드) |
| 토글 연타 | 진행 중 비활성(스피너)으로 동시 쓰기 차단 |
| settings.json 외부 변경 중 토글 | install/uninstall은 read-modify-write — 실패 시 인라인 오류, 재시도 가능 |
| 훅 설치 후 기존 세션 | Claude Code는 세션 시작 시 훅 로드 — "새 세션부터 적용" 캡션 |
| 제거 시 hook-state 데이터 | 남겨둠(기록은 사용자 것) — 삭제 안 함 |

# 변경 파일

| 파일 | 변경 |
|------|------|
| `GlobalRecipesView.swift`(신규) | 레시피 4종 목록 + 토글 + 오류 인라인 |
| `MenuContentView.swift` | Tab enum에 `.hooks` + 탭 버튼 + 분기 |
| `HookRecipeManager.swift` | 파싱 불가 가드 1건(existsButCorrupt 시 install 거부) |
| `StatuslineManager.swift` | 동일 가드 1건 |

# 검증

1. `swift build` 그린 + 재실행.
2. Hooks 탭에서 세션 텔레메트리 토글 ON → `settings.json`에 항목 + 스크립트 생성 확인
   → OFF → 원형 복원(T2 왕복 검증과 동일 경로).
3. statusline: 현재 airuncat 설치 상태(`installed`)로 표시되는지 → OFF → settings에서
   statusLine 제거 → ON → 복원.
4. 외부 statusline 시나리오: settings에 임시 외부 command 넣고 `.foreign` 표시·토글 비활성 확인 후 복원.
5. 육안: 6탭 레이아웃 320pt 수용(활성 탭만 라벨).

# Next Action
- [x] Claude 리뷰어 패스 — NEEDS_FIX 6건 반영(탭명 Global·스크립트 인앱 미리보기·
      파손 가드·연타 방지·캡션 스코프·Phase 9 접힘 전제)
- [x] 사용자 승인 — 승인됨(2026-07-10) → 구현 완료
