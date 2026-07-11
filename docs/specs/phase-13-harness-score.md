---
title: "Phase 13 — Harness Score (5축 성숙도)"
date: 2026-06-24
status: draft
---

# 목표

Harness 팝오버에 프로젝트 하네스 **성숙도**를 표시한다.
참조 프레임워크 `harness-session` 플러그인의 **5축 35항목 체크리스트**
(`materials/harness-checklist.md`: 준비/맥락/실행/검증/개선, L1~L3)를 airuncat이
**이미 스캔 중인 정적 신호에 매핑**해, 네트워크·LLM 없이 로컬에서 축별 점수와
전체 등급(A~F)을 보여준다.

# 설계 원칙

1. **정직한 정적 판정** — 파일로 판정 가능한 항목만 점수 분모에 넣는다.
   행동(세션 패턴)으로만 알 수 있는 항목(병렬 실행, 인수인계, 자율 반복, dry-run,
   검증 AI 분리 등)은 회색 "심층 분석 필요(Phase 13.1+)"로 **표시만** 하고 점수 제외.
2. **프로젝트-로컬 신호만 채점** — 전역 신호(`~/.claude/rules`, `~/.mcp.json`,
   `~/.airuncat/skills`, 전역 orphan 링크)는 모든 프로젝트에서 동일하므로 **프로젝트
   성숙도 변별력이 없다.** 따라서 점수는 프로젝트 스코프 신호만 사용
   (프로젝트 rules, 프로젝트 settings.json hooks/permissions, 프로젝트 CLAUDE.md,
   `scope == .project` skill). 전역 신호는 점수에서 제외(표시는 가능).
3. **자기참조 가점 금지** — "airuncat 사용 자체 = 충족" 같은 무조건 만점 항목은 두지 않는다.
4. **축 동등가중** — 축마다 항목 수가 다르므로(준비3/맥락3/실행1/검증2/개선2) 단순 항목
   합산은 항목 많은 축이 등급을 지배한다. 전체 점수는 **각 축 ratio의 평균**으로 계산해
   5축을 동등 취급한다.

# 현재 상태

- `HarnessInfo`(struct) — `rules`, `hooks`, `permissions`, `omcPresent` 보유. 멤버와이즈
  이니셜라이저 사용. 유일 생성부 `HarnessScanner.scan()`.
- `HarnessManager` — toggle/add/removePermission/deleteHook가 `var updated = info` 부분 갱신.
  `HarnessPopoverView.rescan()`은 detached 전체 재스캔.
- `ClaudeMdScanner.scan(cwd:)` → `ClaudeMdInfo`(globalEntry + projectEntries 배열, 각
  `wordCount`/`exists`). 본문 텍스트/`@import` 검출 API는 **없음**.
- `SkillScanner.scan(projectCwd:)` → `(skills:[SkillRecord(scope)], orphans:[OrphanLink])`.
  skills는 전역+프로젝트 혼재, `scope`로 구분 가능.

# 범위

**In:**
- `HarnessInfo`에 점수 입력 필드 추가: `claudeMdWordCount`, `claudeMdHasImports`,
  `projectSkillCount` (scope==.project 만)
- `HarnessScanner.scan()`이 위 필드를 **명시적으로 채움** (아래 "데이터 흐름" 참조)
- `HarnessScoring.swift`(신규) — `HarnessGrade`, `AxisResult`, `ScoreItem`, `HarnessScore`,
  순수 함수 `evaluate(_:)`
- 팝오버 헤더에 전체 Grade 배지 + 비율 + 접이식 5축 체크리스트(기존 수동 토글 패턴)
- 점수 일관성: 모든 mutation 후 **`rescan()`으로 전체 갱신**(부분 갱신만으로 점수 stale 방지)

**Out:**
- LLM 심층 분석(비동기/네트워크) — C안, Phase 13.1+ 백로그
- rules/CLAUDE.md **내용 품질** 평가 — Phase 13.2 백로그
- 전역 신호 채점, MCP 채점(전역이라 변별력 없음 → deferred 표시만)
- 세션 행 배지에 등급 노출 (팝오버 내부만)
- 행동 항목(병렬/인수인계/자율반복/검증AI분리 등) 자동 판정

# 5축 매핑 (채점 항목 = 프로젝트-로컬 정적 신호)

각 축 `axisRatio = pass / total`. 전체 = 5개 `axisRatio`의 평균.

## 축 1 — 준비 (Scaffolding) · 3항목
| 항목 | 판정 신호 |
|------|----------|
| CLAUDE.md 존재 | `claudeMdWordCount >= 20` |
| 프로젝트 규칙 분리 | 프로젝트 rules(`scope == .project`) `>= 1` |
| 행동범위/민감파일 제한 | `permissions.contains { $0.kind == .deny }` (deny 단독, allow는 불충분) |

## 축 2 — 맥락 (Context) · 3항목
| 항목 | 판정 신호 |
|------|----------|
| 설정 간결 | `20 <= claudeMdWordCount <= 1500` (너무 길면 미충족 → 분리 신호) |
| 점진적 노출 | `claudeMdHasImports` (CLAUDE.md에 `@` import 존재) |
| 규칙으로 맥락 분리 | 프로젝트 rules(`scope == .project`) `>= 1` |

## 축 3 — 실행 (Orchestration) · 1항목 (단일 → 성숙도 L 표기 생략, ✓/✗만)
| 항목 | 판정 신호 |
|------|----------|
| 커스텀 자동화 | `projectSkillCount >= 1` |
| (계획·위임·병렬·인수인계·자율반복) | 심층 분석 필요 — 점수 제외 (6항목) |

## 축 4 — 검증 (Verification) · 2항목
| 항목 | 판정 신호 |
|------|----------|
| 포맷터/린터/빌드 자동 적용 | enabled `PostToolUse` hook `>= 1` |
| 위험 작업 차단 | enabled `PreToolUse` hook `>= 1` (deny permission과 중복 가점 회피 — PreToolUse 단독) |
| (테스트환경·dry-run·E2E·검증AI분리) | 심층 분석 필요 — 점수 제외 (4항목) |

## 축 5 — 개선 (Compounding) · 2항목
| 항목 | 판정 신호 |
|------|----------|
| 반복 작업 자동화 | `projectSkillCount >= 1 || enabledHookCount >= 1` |
| 정리됨(쌓이지 않음) | `!hasDisabledHook` (비활성 hook 없음) |
| (반복실수→규칙화·미사용 정리·관찰추적) | 심층 분석 필요 — 점수 제외 (3항목) |

> 채점 항목 합계: 준비3 + 맥락3 + 실행1 + 검증2 + 개선2 = **11항목**.
> deferred(회색 표시): 실행6 + 검증4 + 개선3 = **13항목** (와이어프레임 "심층 N항목"의 N 근거).

# 점수 / 등급

```
overallRatio = (Σ axisRatio) / 5          // 축 동등가중
```

| overallRatio | 등급 |
|--------------|------|
| ≥ 0.85 | A |
| ≥ 0.65 | B |
| ≥ 0.45 | C |
| ≥ 0.25 | D |
| < 0.25 | F |

> 임계값은 "정적으로 도달 가능한 상한"을 고려해 A=0.85로 잡음(행동축이 빠져 만점이 드뭄).
> Step 4에서 airuncat 자기 자신으로 실측해 등급이 합리적인지 확인하고 필요 시 조정.

```swift
enum HarnessGrade: String {
    case a = "A", b = "B", c = "C", d = "D", f = "F"
    static func from(ratio: Double) -> HarnessGrade {
        switch ratio {
        case 0.85...:     return .a
        case 0.65..<0.85: return .b
        case 0.45..<0.65: return .c
        case 0.25..<0.45: return .d
        default:          return .f
        }
    }
    var color: Color {
        switch self {
        case .a: return .green
        case .b: return Color(red: 0.4, green: 0.8, blue: 0.2)
        case .c: return .yellow
        case .d: return .orange
        case .f: return .red
        }
    }
}
```

성숙도 표기(2항목 이상 축만): `axisRatio >= 0.67 → L3`, `>= 0.34 → L2`, `> 0 → L1`, `0 → —`.
실행축(1항목)은 L 표기 생략, ✓/✗만.

# 데이터 모델

```swift
struct ScoreItem: Identifiable {
    let id: String
    let label: String
    let passed: Bool
    let detail: String?     // "312 words", "rules 4개" 등
}

struct AxisResult: Identifiable {
    let id: String          // "준비" 등
    let title: String
    let items: [ScoreItem]  // 채점 항목
    let deferredCount: Int  // 심층 분석 필요 항목 수 (표시용)
    let showsMaturity: Bool // 단일 항목 축은 false
    var pass: Int { items.filter(\.passed).count }
    var total: Int { items.count }
    var ratio: Double { total == 0 ? 0 : Double(pass) / Double(total) }
}

struct HarnessScore {
    let axes: [AxisResult]
    var ratio: Double {                         // 축 동등가중
        axes.isEmpty ? 0 : axes.map(\.ratio).reduce(0, +) / Double(axes.count)
    }
    var grade: HarnessGrade { .from(ratio: ratio) }
}

enum HarnessScoring {
    static func evaluate(_ info: HarnessInfo) -> HarnessScore { /* 위 매핑 */ }
}
```

# HarnessInfo 변경

```swift
struct HarnessInfo {
    // ... 기존 8개 필드 ...
    var claudeMdWordCount: Int = 0
    var claudeMdHasImports: Bool = false
    var projectSkillCount: Int = 0

    var projectRuleCount: Int { rules.filter { $0.scope == .project }.count }
    var score: HarnessScore { HarnessScoring.evaluate(self) }
}
```

> 기본값을 줘 멤버와이즈 이니셜라이저 깨짐을 막는다. `score`는 순수 함수라 비용 작음.
> **stale 방지:** `HarnessManager`의 toggle/add/removePermission/deleteHook는 부분 갱신
> 후 점수 입력 필드가 옛 값으로 남을 수 있으므로, 팝오버는 mutation 직후 `rescan()`을
> 호출해 전체 재스캔된 `HarnessInfo`로 교체한다(점수 입력 일관성 보장). 토글은 드문
> 사용자 액션이라 추가 IO 허용.

# 데이터 흐름 — HarnessScanner.scan()

`scan(cwd:)`가 기존 rules/hooks/permissions/omc 스캔에 더해:

1. **프로젝트 CLAUDE.md 1회 읽기** (root `CLAUDE.md` 우선, 없으면 `.claude/CLAUDE.md`):
   존재하는 파일 1개를 읽어 `claudeMdWordCount`(공백 split 단어 수) +
   `claudeMdHasImports`(`@`로 시작하는 라인 존재 여부) 동시 산출.
   - 선택 규칙: 둘 다 존재 시 root 우선. 둘 다 없으면 wordCount=0, hasImports=false.
   - 기존 `ClaudeMdScanner`는 wordCount만 주고 `@` 검출이 없으므로 **이 1회 파일 읽기를
     HarnessScanner에 추가**한다(작은 파일, IO 1회 — "재사용으로 IO 0"이 아님을 명시).
2. **프로젝트 skill 수**: `SkillScanner.scan(projectCwd: cwd).skills.filter { $0.scope == .project }.count`
   → `projectSkillCount`.
3. 위 값을 이니셜라이저 인자(또는 생성 후 대입)로 `HarnessInfo`에 채워 반환.

> MCP/전역 skill/orphan/전역 rule은 점수에서 제외하므로 scan에 추가 부담 없음.

# UI

팝오버 헤더(rules 섹션 위)에 점수 영역:

```
┌────────────────────────────────────────────┐
│ Harness            [B] 72%        (▶ 5축)    │  ← 헤더 행 탭으로 토글
├────────────────────────────────────────────┤  ← scoreExpanded 시
│ 준비   L3  ●●●                               │
│   ✓ CLAUDE.md 존재 (312 words)              │
│   ✓ 프로젝트 규칙 분리 (rules 4)            │
│   ✓ 행동범위 제한 (deny 2)                  │
│ 맥락   L2  ●●○                               │
│   ✓ 설정 간결 (312 words)                   │
│   ✗ 점진적 노출 (@import 없음)              │
│   ✓ 규칙으로 맥락 분리                       │
│ 실행       ✓                                 │
│   ✓ 커스텀 자동화 (skill 3)   · 심층 6항목  │
│ 검증   L2  ●○        · 심층 4항목           │
│ 개선   L3  ●●        · 심층 3항목           │
└────────────────────────────────────────────┘
```

- Grade 배지: `Text(grade.rawValue)` 흰 글씨 + `RoundedRectangle(fill: grade.color)`. + `Int(ratio*100)%`.
- `@State var scoreExpanded = false` — 헤더 행 `onTapGesture` + `withAnimation`
  (**기존 RuleRow 수동 토글 패턴 사용, DisclosureGroup 아님** — 시각 컨벤션 통일).
- 축 행: 축명 + (showsMaturity 시 L1/L2/L3) + `●/○` 도트 + deferredCount>0 시 "· 심층 N항목".
- 항목: `checkmark.circle.fill`(통과, green) / `xmark.circle`(미충족, secondary) + detail 텍스트.
- width 280 과밀 위험: detail 텍스트는 `.lineLimit(1).truncationMode(.tail)`, 폰트 10pt.
  Step 4 `/run-clawde` 실측으로 줄바꿈/잘림 확인.
- 색은 가능한 시맨틱 컬러 우선, Grade 배지만 의미상 하드코딩 컬러(다크모드 대비 Step 4 확인).

# 변경 파일

| 파일 | 변경 |
|------|------|
| `HarnessScanner.swift` | `HarnessInfo`에 3필드 + `projectRuleCount`/`score`. `scan()`에 CLAUDE.md 1회 읽기 + project skill 카운트 |
| `HarnessScoring.swift` (신규) | `HarnessGrade`, `ScoreItem`, `AxisResult`, `HarnessScore`, `evaluate()` |
| `HarnessPopoverView.swift` | 헤더 Grade 배지+비율, `scoreExpanded` 5축 섹션. mutation 후 `rescan()` 보장 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| `.claude` 없는 세션 | `HarnessInfo == nil` → 배지·점수 없음 (기존 유지) |
| `.claude`만 있고 rules/hooks/CLAUDE.md 전부 없음 | 모든 프로젝트-로컬 항목 미충족 → Grade F (전역 신호로 부풀지 않음 — 채점서 제외했으므로) |
| CLAUDE.md 없음 | wordCount=0 → 축1·축2 해당 항목 미충족 |
| CLAUDE.md 과도하게 김(>1500 words) | 축2 "간결" 미충족 |
| root·sub CLAUDE.md 동시 존재 | root 우선해 1개만 채점 |
| 프로젝트 skill 0 (전역 skill만 있음) | 축3 미충족(전역은 프로젝트 전용성 아님) |
| hooks 없음 | 축4 두 항목 미충족, 축5 "정리됨"은 충족(비활성 hook 없음) |
| 단일 항목 축(실행) | 성숙도 L 미표기, ✓/✗만 |

# 검증

1. `swift build` 그린 (빌드 훅)
2. airuncat 자기 자신(rules 4 + hooks + CLAUDE.md + 프로젝트 skill) → H 클릭 →
   Grade 합리성 확인. 비현실적이면 임계값 미세조정.
3. `.claude`만 있고 비어있는 더미 프로젝트 → Grade F, 미충족 X 다수 확인 (전역 신호로 안 부풀음)
4. `.claude` 없는 프로젝트 → 배지/점수 미표시
5. hook 토글 후 점수가 즉시 일관 갱신되는지(rescan) 확인
6. 5축 접기/펼치기, deferred "심층 N항목" 회색 표기, width 280 줄바꿈/잘림 확인 (`/run-clawde`)
7. 고양이 미변경 → `/render-cat` 불필요

# Next Action
- [x] Gemini 검토 — Gemini CLI 무료티어 종료로 불가 → 별도 Claude 리뷰어 패스로 대체, must-fix 7건 반영
- [x] 사용자 승인 (Step 3) — B안 승인
- [x] 개발 (Step 4) — HarnessScoring.swift 신규 + HarnessScanner/HarnessPopoverView 수정, swift build 그린
- [x] 리뷰 (Step 5·6) — 별도 리뷰어 패스, must-fix 2건 반영(Obsidian 마이그레이션 부작용 제거 → .claude/commands+skills 직접 카운트, @import 오탐 방지)
- [x] 테스트 (Step 7) — build.sh 번들 + 실행 크래시 없음. airuncat 자기 점수 예측 A(93%)
- [ ] 팝오버 H 배지 클릭 육안 확인 (사용자) — 5축 펼침/등급 배지/레이아웃
- [ ] PR (Step 8) — 사용자 요청 시 브랜치 푸시 + PR

## 구현 메모 (spec 대비 변경)
- 점수 stale 방지: spec은 "mutation 후 rescan" 제안했으나, HarnessManager가 `var updated = info`
  복사-갱신이라 점수 입력 필드(CLAUDE.md/skill)가 보존되고 hook/permission 토글은 이 필드를
  바꾸지 않음 → 부분갱신만으로 점수 일관, rescan 불필요(플리커 없음).
- 프로젝트 자동화 카운트: SkillScanner.scan은 Obsidian 마이그레이션 쓰기 부작용 + 글로벌 충돌
  필터가 있어, `<cwd>/.claude/commands` + `.claude/skills`의 *.md를 직접 카운트로 대체.
