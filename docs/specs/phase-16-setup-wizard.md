---
title: "Phase 16 — 하네스 세팅 마법사"
date: 2026-07-11
status: active
---

# 목표

낮은 등급(F~C) 프로젝트를 **한 흐름**으로 끌어올린다:
CLAUDE.md → rules → permissions(deny) → hook 레시피(+검토 후 켜기). 파편적으로 흩어진
Phase 14 액션들과 Phase 15 레시피를 **단계식 마법사**로 엮는다. `docs/direction.md` 로드맵 16.

**도달 등급(점수 산술, 리뷰어 검증)**: 빈 프로젝트 기준 —
훅을 단계 내에서 검토 후 **켜면** 준비1.0+맥락0.667+검증1.0+개선1.0 = **73% = B**.
추가만(비활성) 하면 ~43% = D. 실행축(프로젝트 스킬)은 마법사가 안 건드림(점수용
스킬 생성은 큐레이팅 원칙 위반이라 기각).

신뢰 원칙(direction.md §3) 그대로: **진단 → 제안(미리보기) → 사용자 확인 → 적용**을
단계마다 반복. 자동으로 켜지는 것 없음 — 훅 켜기는 명령 전문을 본 단계에서
사용자가 [추가+켜기]를 **명시 선택**했을 때만.

# 재료 (전부 기존 — 신규 쓰기 로직 없음)

| 단계 | 재사용 |
|------|--------|
| CLAUDE.md 생성 | `HarnessSetup.createClaudeMd(cwd:) -> String?` |
| rule 추가 | `HarnessSetup.createStarterRule(cwd:) -> String?` |
| deny 권한 | `HarnessSetup.addSensitiveDenies(in:) -> HarnessInfo` |
| hook 레시피 | `ProjectHookRecipe.catalog` + `addDisabledHookTemplate(...) -> HarnessInfo` |
| hook 켜기 | `HarnessManager.toggle(hook:in:)` — 단계 내 검토가 곧 리뷰 |
| 점수 | `HarnessScoring.evaluate` — **최종 실재채점만** 표시(단계별 가상 시뮬은 드롭) |

반환 이질성 어댑터: 1·2단계는 `String?`(오류), 3·4단계는 `HarnessInfo.writeError`.
`alreadyExistsMarker`("이미 존재")는 **성공-스킵**으로 처리(HarnessSetup.applyAll 관례).

# 범위

**In:**
- `HarnessWizardView.swift`(신규): 팝오버 안 단계식 뷰(스텝 인디케이터 + 미리보기 + 적용/건너뛰기).
- 진입점: Harness 팝오버 점수 섹션 — 등급 **C 이하**일 때 "세팅 마법사" 버튼 노출.
- 4단계(이미 충족된 단계는 자동 스킵·체크 표시):
  1. **CLAUDE.md** — 3상태: 충족(wc≥20 → ✓스킵) / **존재하나 부족**(wc<20 → 덮어쓰기 금지,
     "수동 보강 필요" 안내만) / 부재(생성 미리보기 → 적용).
  2. **rules** — 프로젝트 rule 0개면 `createStarterRule` 템플릿 미리보기.
  3. **permissions** — deny 0개면 민감 deny 셋 미리보기.
  4. **hook 레시피** — 고정 추천 2개: `build-on-edit`(감지 타입 명령, PostToolUse) +
     `block-sensitive`(PreToolUse). 각각 명령 전문 미리보기 + **[추가+켜기] / [추가만] /
     [건너뛰기]** — 단계에서 명령을 본 것이 곧 검토이므로 켜기 선택 가능(신뢰 원칙 유지).
     2개 고정인 이유: ver-post+ver-pre 충족 + imp-clean(비활성 ≤2) 안전.
- 마지막: 요약(적용 N·스킵 M) + **적용 후 실제 재채점 등급**("D → B") 표시.
- 완료 시 rescan → 팝오버 점수 갱신.

**기존 자동 세팅과의 관계** (리뷰어 §3): 축 행의 인라인 생성/추가 버튼(Phase 14)은
**개별 스팟픽스**로 유지, 마법사는 낮은 등급용 **가이드 경로** — 같은 함수·rescan을 공유.

**Out:**
- 신규 콘텐츠 생성 로직(전부 Phase 14/15 재사용 — 마법사는 순서와 UI만).
- 점수용 프로젝트 스킬 자동 생성(실행축) — 껍데기 스킬은 큐레이팅 위반.
- LLM 내용 품질 진단(Phase 17).
- 전역(글로벌) 설정 마법사.

# UI

```
│ Harness  [D] 42%   [세팅 마법사]      │ ← C 이하일 때만
├──────────────────────────────────────┤
│ 마법사 (2/4)  ●●○○                    │
│ rules — 프로젝트 규칙이 없습니다       │
│ ┌ 미리보기 ─────────────────┐        │
│ │ # Read-only sessions      │        │
│ │ ...                        │        │
│ └───────────────────────────┘        │
│        [건너뛰기]      [적용]         │
└──────────────────────────────────────┘
(마지막 단계 후) 적용 2 · 건너뜀 1 · 등급 D → B
```

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 4단계 전부 이미 충족 | 마법사 버튼 자체를 숨김(등급 C 이하 조건이 대부분 걸러줌) |
| `.claude` 디렉토리 부재 | scan이 nil → 팝오버/배지 자체가 없음(기존 노출 조건과 동일) — 마법사 진입은 `.claude` 존재 전제 |
| 적용 중 쓰기 실패 | 해당 단계에 인라인 오류 + 재시도, 다음 단계 진행 가능 |
| settings.json 외부 변경 | Phase 14 가드(mtime 비교) 그대로 — 오류 표시 후 재스캔 유도 |
| 마법사 도중 팝오버 닫힘 | 상태 비저장 — 다시 열면 처음부터(이미 적용된 단계는 ✓ 스킵) |

# 변경 파일

| 파일 | 변경 |
|------|------|
| `HarnessWizardView.swift`(신규) | 단계식 마법사 뷰 |
| `HarnessPopoverView.swift` | 점수 섹션에 진입 버튼 + 마법사 표시 상태 |

# 검증

1. `swift build` 그린 + 재실행.
2. 더미 프로젝트(빈 디렉토리)로 F 등급 → 4단계 적용(훅 2개 켜기 포함) → 재채점 **B(73%)** 확인.
   (더미가 어려우면: 각 단계 적용 함수 호출을 코드 경로로 검증 + 이 repo에서 스킵 동작 확인)
3. 이 repo(높은 등급): 마법사 버튼 미노출 확인.
4. 단계 건너뛰기·중간 닫기·재진입 시 ✓ 스킵 동작.

# 구현 중 발견 (기록)
- **Phase 14 잠복 버그 수리**: `HarnessManager.writeJSON`이 temp→`moveItem`을 썼는데
  moveItem은 대상 존재 시 실패 → **기존 settings.json에 두 번째 쓰기부터 전부 실패**
  (deny 4개 중 1개만 들어가고 중단되는 식). `--wizard-sim` 헤드리스 검증으로 발견,
  `Data.write(.atomic)`으로 교체. Phase 14 인라인 버튼들도 이 수리로 정상화.
- 검증 결과: 더미 프로젝트 **F 10% → B 73%** (deny 4 · 활성 Post/PreToolUse 각 1) — 스펙 산술 일치.

# Next Action
- [x] Claude 리뷰어 패스 — NEEDS_FIX 반영(F→B 산술 블로커: 단계 내 검토 후 켜기로 해결, 함수명 명시, 어댑터/3상태/고정 2레시피/관계 정의)
- [x] 사용자 승인 — 루프 사전 전체 승인
