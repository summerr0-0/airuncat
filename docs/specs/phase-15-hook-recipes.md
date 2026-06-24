---
title: "Phase 15 — Hook 레시피 카탈로그"
date: 2026-06-24
status: draft
---

# 목표

"훅도 세팅해줘"의 안전한 구현. Phase 14의 **빈 비활성 템플릿**을, 프로젝트 타입에 맞춰
**실제 명령이 채워진 큐레이팅 레시피**로 진화시킨다. 사용자는 Harness 팝오버에서
레시피를 **고르고 → 채워진 명령을 보고 → (수정) → 켠다**. 명령 추측·자동 활성화는 하지 않는다.

`docs/direction.md`의 복리 루프 중 "심화" 단계를 구현.

# 설계 원칙

1. **검토 후 활성화** — 레시피도 **비활성(`_disabledHooks`)으로 추가**한다. 명령이 실제로
   채워져 있어 사용자는 *확인 + 토글*만 하면 됨(Phase 14는 빈 TODO라 직접 작성 필요였음).
2. **프로젝트 타입 인식** — cwd의 마커 파일로 타입 감지해 맞는 명령을 채운다.
3. **기존 쓰기 경로 재사용** — Phase 14의 `HarnessManager.addDisabledHookTemplate`을 그대로 사용.
   Phase 15는 **카탈로그 + 타입 감지 + 피커 UI**만 추가.
4. **큐레이팅·안전** — 명령은 검증된 것만. guard(차단) 레시피는 Claude Code hook 프로토콜을
   검증해 확정(아래 Out/검증 참조).

# 범위

**In:**
- `HookRecipe.swift`(신규): `ProjectType`, `ProjectTypeDetector.detect(cwd:)`,
  `HookRecipe`, `RecipeCategory`, `HookRecipes.all` 정적 카탈로그
- `HarnessPopoverView`: hooks 섹션에 "+ 레시피에서 추가" → 레시피 피커(목록 + 해석된 명령 미리보기)
- 추가 시 `addDisabledHookTemplate(event:matcher:command:)`로 비활성 추가 → rescan

**Out:**
- 훅 자동 활성화(여전히 검토 후 토글)
- 사용자 커스텀 레시피 저작(Phase 15.1 백로그)
- 비-훅 자동화
- guard 레시피의 복잡한 차단 스크립트 완성형(초기엔 build/format/lint 위주, guard는
  프로토콜 검증 후 추가 — 아래 "검증" 참조)

# 데이터 모델

```swift
enum ProjectType: String, CaseIterable {
    case swift, node, python, rust, go, generic
    var label: String {
        switch self {
        case .swift: return "Swift"; case .node: return "Node"
        case .python: return "Python"; case .rust: return "Rust"
        case .go: return "Go"; case .generic: return "일반"
        }
    }
}

enum ProjectTypeDetector {
    /// cwd의 마커 파일로 타입 감지(모노레포 대비 복수 반환, 없으면 [.generic]).
    static func detect(cwd: String) -> [ProjectType] {
        let fm = FileManager.default
        func has(_ f: String) -> Bool { fm.fileExists(atPath: (cwd as NSString).appendingPathComponent(f)) }
        var types: [ProjectType] = []
        if has("Package.swift") { types.append(.swift) }
        if has("package.json") { types.append(.node) }
        if has("pyproject.toml") || has("requirements.txt") || has("setup.py") { types.append(.python) }
        if has("Cargo.toml") { types.append(.rust) }
        if has("go.mod") { types.append(.go) }
        return types.isEmpty ? [.generic] : types
    }
}

enum RecipeCategory: String { case build = "빌드", format = "포맷", lint = "린트", guardRule = "차단" }

struct HookRecipe: Identifiable {
    let id: String
    let title: String
    let description: String
    let category: RecipeCategory
    let event: String          // "PostToolUse" | "PreToolUse"
    let matcher: String        // "Edit|Write" | "Bash"
    let riskNote: String?
    let commands: [ProjectType: String]   // 타입별 명령(없으면 해당 타입 미지원)

    /// 감지된 타입들 중 첫 매칭 명령, 없으면 generic, 그것도 없으면 nil.
    func command(for types: [ProjectType]) -> String? {
        for t in types where commands[t] != nil { return commands[t] }
        return commands[.generic]
    }
}
```

# 카탈로그 (초기)

| id | 제목 | category | event/matcher | 타입별 명령 |
|----|------|----------|---------------|-------------|
| `build-on-edit` | 편집 후 빌드 | build | PostToolUse / Edit\|Write | swift:`swift build` · node:`npm run build` · rust:`cargo build` · go:`go build ./...` |
| `format-on-edit` | 저장 시 포맷 | format | PostToolUse / Edit\|Write | swift:`swift format -i` · node:`npx prettier --write .` · python:`black .` · rust:`cargo fmt` · go:`gofmt -w .` |
| `lint-on-edit` | 편집 후 린트 | lint | PostToolUse / Edit\|Write | swift:`swiftlint` · node:`npx eslint .` · python:`ruff check` |
| `block-sensitive` | 민감파일 편집 차단 | guard | PreToolUse / Edit\|Write | generic:`<.env/secrets 차단 가드>` |
| `block-dangerous-bash` | 위험 bash 차단 | guard | PreToolUse / Bash | generic:`<rm -rf 등 차단 가드>` |

> build/format/lint은 명령이 단순(검증 쉬움). guard 2종은 hook JSON(stdin) 파싱 + 비제로 종료가
> 필요해 **Claude Code hook 프로토콜 검증 후 확정**(claude-code-guide/문서). 초기 릴리스는
> build/format/lint 먼저, guard는 검증 완료분부터 추가.

# UI

Harness 팝오버 hooks 섹션 아래(또는 헤더 우측)에 진입점:

```
│ hooks (2) · 2 활성        [+ 레시피에서 추가]   │
│  ... 기존 hook 행들 ...                          │
├──────────────────────────────────────────────┤  ← 레시피 피커(펼침/시트)
│ 감지: [Swift]                                   │
│  편집 후 빌드   빌드                             │
│    swift build                          [추가]  │
│  저장 시 포맷   포맷                             │
│    swift format -i                      [추가]  │
│  편집 후 린트   린트                             │
│    swiftlint                            [추가]  │
│  민감파일 편집 차단  차단                         │
│    (가드 스크립트)                       [추가]  │
└──────────────────────────────────────────────┘
```

- `@State recipesExpanded` 토글(기존 수동 토글 패턴). 감지된 타입을 칩으로 표시.
- 각 레시피 행: 제목 + category 태그 + **해석된 명령**(monospaced, `command(for:)`), 우측 "추가" 버튼.
- 타입 미지원(`command(for:) == nil`): "이 프로젝트 타입엔 해당 없음" 회색, 버튼 비활성.
- "추가" → `HarnessManager.addDisabledHookTemplate(event:matcher:command:in:)` → rescan →
  hooks 섹션에 **비활성**으로 등장. 안내: "검토 후 토글로 켜세요."
- 이미 추가됨(동일 해시): "이미 존재" → 무해 무시(배너 또는 행 비활성 표시).

# 데이터 흐름

1. 팝오버에서 `ProjectTypeDetector.detect(cwd: info.projectPath)` 1회 → 칩 + 명령 해석.
2. "추가" → detached로 `HarnessManager.addDisabledHookTemplate(...)` (Phase 14 함수, settings.json
   부재도 처리됨) → 반환 info의 writeError 확인 → `rescan()`.
3. 점수: 비활성이라 `ver-*` 즉시 불변(Phase 14 imp-clean이 TODO/레시피 비활성을 클러터로 안 봄 —
   단, 레시피 명령은 `# TODO`로 시작하지 않으므로 **imp-clean 예외 규칙을 레시피에도 적용 필요**.
   → HarnessScoring의 staleDisabled 필터를 "비활성=클러터" 대신 "사용자 검토 대기"로 일반화하거나,
   레시피 추가분을 식별하는 마커 검토. **이 상호작용은 개발 단계에서 재확인**.)

> ⚠ Phase 14의 `imp-clean`은 `commandSummary.hasPrefix("# TODO")`만 클러터 제외한다. 레시피는
> 실제 명령이라 이 prefix가 없어 **비활성 추가 시 imp-clean이 다시 ✗가 된다(개선축 역행 재발).**
> 해결안(개발 시 택1): (a) 비활성 hook 전부를 "검토 대기"로 보고 imp-clean에서 제외,
> (b) 레시피 추가 시 command에 식별 주석 접두(예약), (c) imp-clean을 "활성 자동화 존재"로 재정의.
> 권장: (a) — 비활성 hook은 본질적으로 "아직 안 켠 것"이지 "안 쓰는 클러터"가 아님.

# 변경 파일

| 파일 | 변경 |
|------|------|
| `HookRecipe.swift`(신규) | ProjectType / ProjectTypeDetector / HookRecipe / RecipeCategory / HookRecipes.all |
| `HarnessPopoverView.swift` | 레시피 피커 UI + 추가 핸들러(rescan) |
| `HarnessScoring.swift` | imp-clean을 "비활성 hook 전체 제외"로 일반화(개선축 역행 방지) |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 타입 미감지(generic) | build/format/lint는 "해당 없음", guard(generic)만 명령 노출 |
| 모노레포(복수 타입) | `command(for:)`가 첫 매칭 타입 명령 채택 |
| 레시피 이미 추가됨 | addDisabledHookTemplate "이미 존재" → 무시/표시 |
| settings.json 부재 | Phase 14에서 빈 {} 처리 완료 |
| guard 레시피 미검증 | 초기엔 카탈로그에서 숨김 또는 "준비 중" 비활성 |

# 검증

1. `swift build` 그린
2. airuncat 자신(Swift): "레시피에서 추가" → `build-on-edit`이 `swift build` 표시 → 추가 →
   hooks에 비활성 등장, imp-clean 역행 없음 확인 → 토글 ON → `ver-post` 충족·점수 상승
3. generic 더미 프로젝트: build 레시피 "해당 없음" 표시
4. 동일 레시피 재추가 → "이미 존재" 무해 처리
5. guard 레시피: Claude Code hook 프로토콜(stdin JSON, 종료코드)로 실제 차단 동작 검증 후 활성화
6. `/run-clawde` 팝오버 육안 확인

# Next Action
- [ ] Gemini 검토(불가 → 별도 Claude 리뷰어 패스)
- [ ] 사용자 승인 (Step 3) — 승인 전 개발 금지
- [ ] guard 레시피 hook 프로토콜 검증(claude-code-guide)
