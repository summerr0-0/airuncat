---
title: "Phase 11 — 퀵 팔레트"
date: 2026-06-22
status: draft
---

# 목표

글로벌 단축키 `⌥Space`로 스포트라이트 스타일 팔레트 창을 띄워, 스킬·프롬프트를 검색한 뒤
현재 활성 iTerm 세션에 즉시 주입한다. OMC의 Tier-0 워크플로우(autopilot, ultrawork, ralph 등)를
단축키 하나로 실행하는 airuncat의 킬러 피처.

# 현재 상태

- Skills / Prompts 탭: 드롭다운 메뉴바를 열어야만 접근 가능
- 주입: Skills 탭 "삽입" 버튼으로 가능하지만 단축키 없음
- 글로벌 단축키 없음

# 범위

**In:**
- `GlobalShortcut.swift` — `CGEvent` tap 기반 `⌥Space` 글로벌 단축키 등록·해제
- `PaletteViewModel.swift` — 스킬+프롬프트 통합 데이터, fuzzy 필터, 히스토리 정렬
- `QuickPalette.swift` — `NSPanel` 플로팅 창 + SwiftUI `PaletteView` + 키 처리
- `AiruncatApp.swift` — 앱 시작 시 단축키 등록, store 클로저 캡처로 sessions 전달
- `~/.airuncat/palette-history.json` — 최근 사용 이력 (최대 50건)

**Out:**
- 사용자 정의 단축키 설정 UI (향후)
- Gemini 세션 주입 (Claude iTerm 세션만)
- 팔레트에서 스킬·프롬프트 생성·편집
- Spotlight 수준의 trigram fuzzy (단순 contains로 충분)

# 사전 조건 / 배포 타깃 상향

**macOS 14.0으로 상향:** SwiftUI `.onKeyPress` API는 macOS 14+ 전용.
`Package.swift` 변경: `.macOS(.v13)` → `.macOS(.v14)`.
현재 CLT 빌드 환경(macOS 15.x)에서 실행·배포하므로 v14 전제는 안전하다.

# UI

```
┌─────────────────────────────────────┐  ← 화면 중앙, 폭 480pt
│  /                                  │  ← 검색 필드 (자동 포커스)
│─────────────────────────────────────│
│ ▶ /run-clawde        [Skills]  최근  │  ← 선택 행 (배경 강조)
│   /ultrawork         [Skills]  최근  │
│   코드 리뷰 체크리스트   [Prompts]      │
│   git-commit          [Prompts]      │
│   …                                  │
│─────────────────────────────────────│
│ 삽입 대상: airuncat ▼                 │  ← 활성 세션 (드롭다운)
│      [Enter] 삽입    [⌘Enter] 복사    │
└─────────────────────────────────────┘

[Esc] 닫기  ·  결과 없음: "일치하는 항목 없음"
```

- 최대 높이: 결과 6행 기준 자동 조정 (행 높이 32pt, min 200pt, max 320pt)
- 결과 없을 때: "일치하는 항목 없음" 빈 상태 텍스트

# 모델

```swift
enum PaletteItemKind: String, Sendable { case skill, prompt }

struct PaletteItem: Identifiable, Sendable {
    let id: String            // 스킬 name 또는 프롬프트 stem
    let title: String         // 표시 제목
    let kind: PaletteItemKind
    let injectText: String    // 주입 텍스트 — 스킬: "/name", 프롬프트: body
    var lastUsed: Date?       // 히스토리에서 로드
}
```

# GlobalShortcut.swift

```swift
@MainActor
enum GlobalShortcut {
    static func register(handler: @escaping @Sendable () -> Void) -> CFMachPort?
    static func unregister(_ tap: CFMachPort)
}
```

**구현 상세:**
- `CGEventTapCreate(tap: .cgSessionEventTap, placement: .headInsertEventTap,
   options: .defaultTap, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), ...)`
- 콜백에서 `keyCode == 0x31 (kVK_Space)` + `flags.intersection(.maskNonCocoaFlags) == .maskAlternate`
  → handler 호출 + **`nil` 반환 (이벤트 소비)** — Spotlight 등 다른 앱이 ⌥Space 받지 않도록
- `CGEventTapCreate` 가 `nil` 반환 → 접근성 권한 없음 → `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)` 열기
- 탭 생성 성공 → `CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)` 로 메인 런루프에 연결
- `CGEvent` tap 콜백은 `@convention(c)` 전역 함수 — `Unmanaged.passRetained` 로 handler 클로저 캡처

**tapRef 저장 방법:** `App` struct는 value type이라 `@State CFMachPort?` 생명주기가 취약.
`ApplicationController` 를 `@MainActor` 클래스로 신설, `@StateObject` 로 보유:
```swift
@MainActor
final class ApplicationController: ObservableObject {
    private(set) var tap: CFMachPort?
    func registerShortcut(handler: @escaping @Sendable () -> Void) { ... }
    func unregisterShortcut() { ... }
}
```
`AiruncatApp` 에 `@StateObject var appCtrl = ApplicationController()` 로 보유.

**접근성 권한:** 기존 `ITermController.insertText` 가 Cmd+V keystroke 주입에 이미 요구하므로
신규 권한 추가 없이 동작한다.

# PaletteViewModel.swift

```swift
@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var filtered: [PaletteItem] = []
    @Published var selectedIndex: Int = 0
    @Published var targetSession: SessionInfo? = nil

    func load(sessions: [SessionInfo])  // 팔레트 열릴 때 — 스킬+프롬프트 스캔 + 히스토리 로드
    func moveUp()
    func moveDown()
    func inject() -> Bool               // Enter — insertText + 히스토리 업데이트 + 닫기
    func copyOnly()                     // ⌘Enter — 클립보드만
    func close()                        // Esc

    private func applyFilter()          // query 변경 시 자동 호출 (onChange)
}
```

**필터 로직:**
1. 쿼리 비어있음 → `lastUsed` 내림차순 전체 표시
2. 쿼리 있음 → `title.localizedCaseInsensitiveContains(query)` 매칭
   - 접두사 매칭이 contains보다 상위 정렬 (점수 2 vs 1)
3. `selectedIndex` 는 filter 후 항상 0으로 리셋

**히스토리 저장 형식** (`~/.airuncat/palette-history.json`):
```json
[
  {"id": "run-clawde", "lastUsed": 1750000000.0},
  {"id": "git-commit",  "lastUsed": 1749990000.0}
]
```
- 최대 50건 — 초과 시 가장 오래된 항목 삭제
- 원자적 쓰기 (`.atomicWrite` 옵션)

**삽입 텍스트:**
- 스킬: `"/\(skill.id)\n"` — `/skill-name` + newline(Enter) 자동 포함 → Claude CLI 즉시 실행
- 프롬프트: `record.body` (본문만, Enter 없음 — 사용자가 확인 후 직접 전송)

**ITermController.insertText 연동:**
`insertText(cwd:)` 는 **클립보드에 미리 쓰인 텍스트를 Cmd+V로 붙여넣는** 방식이다.
inject() 흐름:
1. `NSPasteboard.general.setString(item.injectText, forType: .string)`
2. `ITermController.insertText(cwd: targetSession.cwd)` 호출 (Cmd+V 전송)

`copyOnly()` 흐름:
1. `NSPasteboard.general.setString(item.injectText, forType: .string)` 만 수행, iTerm 미전환

**삽입 대상 자동 감지:**
- `sessions` 중 `status == .active` 이고 `aiKind == .claude` 인 세션 중 `lastActivity` 최신 1개
- 없으면 `status == .idle` 중 `lastActivity` 최신 Claude 세션
- 없으면 `nil` → "삽입 대상 없음" 표시 + Enter 비활성화

**`load(sessions:)` 는 async:**
```swift
func load(sessions: [SessionInfo]) async {
    self.targetSession = detectTarget(sessions)
    let (skills, _) = await Task.detached(priority: .userInitiated) {
        SkillScanner.scan()
    }.value
    let prompts = await Task.detached(priority: .userInitiated) {
        PromptScanner.scan()
    }.value
    allItems = build(skills: skills, prompts: prompts)
    applyFilter()
}
```
팔레트 열릴 때마다 최신 스킬·프롬프트 반영.

# QuickPalette.swift

```swift
@MainActor
final class QuickPalette {
    static let shared = QuickPalette()
    private var panel: NSPanel?
    private let viewModel = PaletteViewModel()

    func show(sessions: [SessionInfo])
    func hide()
}
```

**NSPanel 설정:**
```swift
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.nonActivatingPanel, .titled, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
panel.titlebarAppearsTransparent = true
panel.titleVisibility = .hidden
panel.isMovableByWindowBackground = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isReleasedWhenClosed = false
panel.hidesOnDeactivate = false
panel.becomesKeyOnlyIfNeeded = false
```

- `contentViewController = NSHostingController(rootView: PaletteView(vm: viewModel))`
- 화면 중앙 위쪽 배치: `NSScreen.main?.frame.midX`, `midY * 1.3`
- 팔레트 열릴 때 `panel.makeKeyAndOrderFront(nil)` — 포커스를 가져와 검색창 활성화
- `hidesOnDeactivate = false` — 다른 앱 클릭해도 유지 (Esc 또는 다른 클릭으로 닫기)

**키 처리 (SwiftUI, macOS 14+):**
```swift
// PaletteView
.onKeyPress(.return)       { vm.inject(); return .handled }
.onKeyPress(.escape)       { vm.close(); return .handled }
.onKeyPress(.upArrow)      { vm.moveUp(); return .handled }
.onKeyPress(.downArrow)    { vm.moveDown(); return .handled }
// ⌘Enter
.onKeyPress(.return, modifiers: .command) { vm.copyOnly(); return .handled }
```

**닫기 트리거:**
- `Esc` / 주입 성공 / 복사 완료 → `QuickPalette.shared.hide()`
- 팔레트 외부 클릭: `NSWindowDelegate.windowDidResignKey` → `hide()`

# AiruncatApp.swift 수정

```swift
@StateObject var appCtrl = ApplicationController()
@StateObject var store    = SessionStore()  // 기존

// @MainActor body 내부
.onAppear {
    appCtrl.registerShortcut {
        // store는 @MainActor 클래스라 캡처 안전
        let sessions = store.sessions
        QuickPalette.shared.show(sessions: sessions)
    }
}
```

- `SessionStore` 는 싱글톤 없음 — 핸들러 클로저가 `store` 인스턴스를 직접 캡처
- `ApplicationController` 가 `tap: CFMachPort?` 를 class 프로퍼티로 관리 (생명주기 안정)

# 수정·신규 파일

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/GlobalShortcut.swift` | 신규 |
| `Sources/airuncat/PaletteViewModel.swift` | 신규 |
| `Sources/airuncat/QuickPalette.swift` | 신규 (PaletteView 포함) |
| `Sources/airuncat/AiruncatApp.swift` | 글로벌 단축키 등록 추가 |
| `Sources/airuncat/ApplicationController.swift` | 신규 (`@MainActor` 클래스, tapRef 보관) |
| `Package.swift` | `.macOS(.v13)` → `.macOS(.v14)` |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 접근성 권한 없음 | `CGEventTapCreate` nil → 시스템 설정 Accessibility 페이지 열기 |
| 활성 iTerm 세션 없음 | 삽입 대상 "없음" 표시, Enter 비활성화, ⌘Enter만 활성 |
| 스킬·프롬프트 0건 | "항목 없음" 빈 상태 |
| ⌥Space → 팔레트 이미 열림 | `panel.isVisible` 체크 → 닫기 (토글) |
| 주입 성공 후 | `hide()` 자동 호출 |
| 주입 실패 (iTerm 없음) | 오류 없음, 클립보드에는 복사됨 → 사용자가 직접 붙여넣기 가능 |
| 프롬프트 본문 여러 줄 | 그대로 주입 (iTerm는 멀티라인 붙여넣기 지원) |
| 검색 중 결과 선택 후 방향키 | `selectedIndex` clamp `[0, filtered.count-1]` |

# 검증 방법

1. `swift build` 통과
2. 앱 재시작 → `⌥Space` → 팔레트 창 열림 확인
3. 팔레트 열린 상태에서 다른 앱 클릭 → 팔레트 여전히 보임 확인
4. 검색 쿼리 입력 → 실시간 필터 확인
5. `↑↓` 방향키로 항목 이동 확인
6. `Enter` → 활성 iTerm 세션에 텍스트 주입 확인 (iTerm 창 열려있어야 함)
7. `⌘Enter` → 클립보드 복사만 (iTerm 변화 없음)
8. `Esc` → 팔레트 닫기 확인
9. ⌥Space 재입력 → 팔레트 토글(닫기) 확인
10. 팔레트에서 항목 사용 후 재열기 → 최근 사용 항목 상단 확인
