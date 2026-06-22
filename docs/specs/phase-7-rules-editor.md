---
title: "Phase 7 — Rules 에디터"
date: 2026-06-22
status: draft
---

# 목표

Harness 팝오버의 Rules 섹션을 읽기 전용 목록에서 CRUD 가능한 에디터로 확장한다.
글로벌(`~/.claude/rules/`) 과 프로젝트(`.claude/rules/`) 규칙을 함께 관리하고,
OMC의 rule injection 기능을 GUI로 대체한다.

# 현재 상태

`HarnessScanner.scan(cwd:)`
- `.claude/rules/*.md` 파일명 목록만 반환 (`RuleFile { id, path }`)
- 글로벌 `~/.claude/rules/` 미스캔

`HarnessPopoverView`
- rules 섹션: 파일 stem만 나열 (수정/삭제/생성 없음)
- 하단 `settings.json 열기` 링크 + OMC 배지만 존재

# 범위

**In:**
- `RuleFile` 모델 확장: `summary: String`, `mtime: Date`, `scope: RuleScope` 추가
- `RuleFile.id` = `"\(scope.prefix):\(stem)"` — scope 포함해 전역 유일 보장
- `HarnessScanner`: 글로벌 `~/.claude/rules/` 스캔 추가; 파일별 첫 비빈 줄 + stat mtime 읽기
- `RuleManager` (신규): create / delete (원자 쓰기)
- `HarnessPopoverView` 확장:
  - Rule 행에 hover 시 "Finder 열기" + "삭제" 버튼
  - 행 클릭 시 인라인 미리보기 토글 (첫 5줄, 스크롤 없이 인라인 확장)
  - 글로벌 / 프로젝트 섹션 구분 헤더
  - `+ 새 Rule` 버튼 → 이름 입력 → 범위(글로벌/프로젝트) 선택 → 생성
  - mtime "N일 전" 또는 "오늘" 표시 (행 우측 작은 글자)
  - 2단계 삭제 확인 (글로벌 rule 삭제 시 "모든 프로젝트에 영향" 경고 문구 추가)

**Out:**
- Rule 파일 내용 인라인 편집 (외부 에디터 유도로 대체)
- `.claude/settings.json` hooks CRUD (이미 구현됨)
- 전역 CLAUDE.md / settings.json 편집

# 모델 확장

```swift
enum RuleScope {
    case global, project
    var prefix: String { self == .global ? "g" : "p" }
}

struct RuleFile: Identifiable {
    let id: String       // "\(scope.prefix):\(stem)" — scope 포함, ForEach 충돌 방지
    let stem: String     // 파일명 stem (표시용)
    let path: String
    let summary: String  // 파일 첫 비빈·비헤더 줄 (없으면 "")
    let mtime: Date      // stat mtime (권한 없어도 stat은 성공)
    let scope: RuleScope
}
```

`HarnessInfo`는 변경 없음 — `rules: [RuleFile]` 그대로 (타입 변경으로 자동 반영).

# HarnessScanner 변경

```swift
// 추가: 글로벌 rules 경로
static let globalRulesDir: String =
    (NSHomeDirectory() as NSString).appendingPathComponent(".claude/rules")

// scanRules 변경:
// 1. globalRulesDir 스캔 → scope: .global
// 2. claudeDir/rules 스캔 → scope: .project
// 3. 두 배열 합쳐서 반환 (stem 중복 가능, id가 scope 포함이므로 안전)

// summary: 내용 읽기 (실패 시 "")
private static func readSummary(path: String) -> String {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
    return content.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
}

// mtime: stat 사용 (기존 mtime(of:) 재사용, nil 시 .distantPast fallback)
```

**주의 — 비동기 스캔:** `HarnessScanner.scan(cwd:)`은 현재 `Coordinator.tapped`에서 main thread 동기 호출된다. `readSummary`(파일 읽기)가 추가되어 I/O 비중이 늘어나므로, `Coordinator.tapped`에서 `Task.detached`로 스캔을 백그라운드로 옮기고 결과를 `@MainActor`로 hop하여 팝오버를 표시한다.

```swift
// Coordinator.tapped 변경:
@objc func tapped(_ sender: NSButton) {
    if let p = popover, p.isShown { p.close(); return }
    Task {
        let info = await Task.detached(priority: .userInitiated) {
            HarnessScanner.scan(cwd: self.session.cwd)
        }.value
        await MainActor.run {
            harness.wrappedValue = info
            guard let info else { return }
            let p = NSPopover()
            p.behavior = .transient
            p.contentViewController = NSHostingController(rootView: HarnessPopoverView(info: info))
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            self.popover = p
        }
    }
}
```

# RuleManager (신규)

```swift
enum RuleManager {
    // 파일 생성 후 갱신된 [RuleFile] 반환 (에러 시 nil, 에러 메시지는 inout String?으로)
    // 기본 템플릿: "# <name>\n\n여기에 AI에게 강제할 제약이나 동작을 기술한다.\n"
    static func create(name: String, scope: RuleScope, projectCwd: String) -> String?
    // 반환 nil = 성공, String = 에러 메시지

    // 파일 삭제
    static func delete(_ rule: RuleFile) -> String?
}
```

`scope == .global` → `~/.claude/rules/<name>.md`
`scope == .project` → `<projectCwd>/.claude/rules/<name>.md` (디렉토리 없으면 자동 생성)

# HarnessPopoverView 변경

## 상태 관리 원칙

create/delete 후 뷰 갱신 패턴은 `toggle`과 동일하게 "작업 후 재스캔 → info 재할당":
```swift
// create/delete 성공 후:
Task {
    let updated = await Task.detached { HarnessScanner.scan(cwd: info.projectPath) }.value
    if let updated { info = updated }
}
```
(hook toggle과 달리 filesystem을 변경하므로 부분 업데이트보다 재스캔이 안전함)

## 중복 체크

생성 폼에서 "생성" 버튼 클릭 시:
1. `info.rules.filter { $0.scope == selectedScope && $0.stem == trimmedName }` 으로 메모리 체크
2. 있으면 "이미 존재하는 Rule: \(name)" 에러 표시, 파일 쓰기 안 함
3. 없으면 `RuleManager.create` 호출 (파일 I/O는 Task.detached)

## 레이아웃
```
[rules] (4)  글로벌(1) + 프로젝트(3)
──────────────────────────────────────────
  [G] clt-build-only    CLT 빌드만, xcodebuild 금지   오늘  [⌘]
      ▼ 미리보기 (클릭 시 토글):
        이 머신엔 Command Line Tools만 있고 ...
  [P] read-only-sessions  세션 JSONL 읽기 전용         3일 전  [⌘] [🗑]
  ...
──────────────────────────────────────────
[+ 새 Rule]       [settings.json]  [OMC 비활성]
```

- `[G]` = 글로벌 배지 (회색), `[P]` = 프로젝트 배지 (파란색)
- `[⌘]` = Finder에서 열기 (외부 에디터)
- `[🗑]` = 삭제 (글로벌·프로젝트 모두 가능)
  - 글로벌 삭제 확인 문구: "모든 프로젝트에 영향을 줍니다. 삭제하시겠습니까?"
  - 프로젝트 삭제 확인 문구: "이 프로젝트에서 제거합니다"
- 미리보기: `summary` 한 줄 + 클릭 시 최대 5줄 확장
- mtime: stat 기준 → "오늘" / "어제" / "N일 전" (읽기 권한 없어도 stat은 성공)

## 생성 폼 (인라인, 하단)
```
이름:   [my-rule         ]
범위:   [글로벌 ○] [프로젝트 ●]
[취소]                    [생성]
```
- 이름은 영소문자 + 숫자 + `-` + `_` 만 허용 (onChange 필터)
- 중복 이름 체크: in-memory `info.rules` 기준 (위 설명 참조)

# 수정/신규 파일

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/HarnessScanner.swift` | RuleFile 모델 확장(id/stem/summary/mtime/scope), 글로벌 스캔, Coordinator 비동기 패치 |
| `Sources/airuncat/RuleManager.swift` | 신규 — create / delete |
| `Sources/airuncat/HarnessPopoverView.swift` | Rule 행 hover 액션, 미리보기 토글, 생성 폼, 섹션 구분, create/delete 후 재스캔 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| `~/.claude/rules/` 없음 | 글로벌 섹션 숨김 (스캔 결과 빈 배열) |
| `.claude/rules/` 없음 | create 시 디렉토리 자동 생성 |
| 읽기 권한 없는 파일 | summary 빈 문자열, stat mtime으로 날짜 표시 (stat은 읽기 권한 불필요) |
| 동일 stem + 동일 scope 중복 | 메모리 체크로 사전 차단, "이미 존재하는 Rule: \(name)" |
| 글로벌 + 프로젝트 동일 stem | id가 scope prefix 포함이므로 ForEach 충돌 없음 |
| 글로벌 rule 삭제 | 허용, 2단계 확인에 "모든 프로젝트 영향" 경고 문구 포함 |

# 검증 방법

1. `swift build` 통과
2. 앱 재시작 → Harness 팝오버에서 글로벌 `[G]` / 프로젝트 `[P]` 배지 구분 확인
3. rule 행 클릭 → summary 미리보기 토글 확인
4. `[⌘]` 클릭 → Finder에서 파일 열림 확인
5. `+ 새 Rule` → 이름 `test-rule`, 범위 프로젝트 → 생성
   - `.claude/rules/test-rule.md` 파일 생성 확인
   - 목록 즉시 반영 (재스캔)
6. `[🗑]` → 2단계 확인 → 삭제 → 목록에서 제거 확인
7. 중복 이름 입력 → 에러 메시지 확인 (파일 없음 확인)
8. 글로벌 rule 삭제 시 경고 문구 다름 확인
