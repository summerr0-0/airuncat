---
title: "Phase 2.5 — Harness Manager spec"
date: 2026-06-11
status: complete
---

# 목표

활성 세션 행에 **하네스 배지(H)**를 추가하고, 클릭하면 그 세션 프로젝트의
`.claude/rules/` + `.claude/settings.json` hooks를 한눈에 보여주는 팝오버를 띄운다.
hooks는 팝오버 안에서 on/off 토글이 가능하다.

현재 hooks를 켜거나 끄려면 settings.json을 수동으로 편집해야 한다.
세션 행에서 프로젝트의 하네스 상태를 바로 파악하고 hooks를 빠르게 제어한다.

# 범위

**In:**
- `HarnessScanner` — 세션 cwd의 `.claude/rules/*.md` 개수, `settings.json` hooks 파싱
- `HarnessInfo` 모델 — ruleNames: [String], hookGroups: [HookGroup], omcPresent: Bool
- SessionRow: "H N" 소형 배지 (rules+hooks 합계) — .claude 존재할 때만 표시
- 배지 클릭 → `HarnessPopover` (NSPopover)
  - Rules 섹션: 파일명 목록 (읽기 전용)
  - Hooks 섹션: matcher + 요약 커맨드 + on/off 토글
  - OMC 여부: CLAUDE.md에 "oh-my-claudecode" 포함 시 "OMC 활성" 표시
- hooks on/off: `settings.json`의 `_disabledHooks` 배열로 이동/복원

**Out:**
- rules 파일 내용 편집 (Obsidian/에디터에서)
- settings.local.json 관리
- 전역(`~/.claude/`) 하네스 관리 (프로젝트별만)
- hooks 새로 추가 / 삭제 (toggle만)
- Harness 전용 탭 (세션 행 팝오버로 충분)

# 동작 / UI

## SessionRow 배지

```
● clawde             C ✓        14s  [tag]
  "다음 작업 이어서"            H 4/5   ← 배지: 활성 4개 / 전체 5개
  Bash: swift build
```

- `H enabled/total` 형식. 모두 활성이면 `H 5`, 일부 비활성이면 `H 4/5` (주황색).
- `.claude/` 없는 세션은 배지 미표시.
- 배지 minWidth 고정 (보통/주황 전환 시 레이아웃 jitter 방지).
- 스캔 시점: 팝오버 열릴 때 on-demand. 세션 목록 스캔에 포함하지 않음 (I/O 절약).

## HarnessPopover (250pt 너비, ScrollView 내부)

```
.claude/rules  (4개)
──────────────────────────
  clt-build-only
  read-only-sessions
  template-image-only
  vector-cat-no-assets

Hooks  (3개 / 2 활성)
──────────────────────────
  [●] PostToolUse · Edit|Write
      swift build on .swift edit
  [●] PreToolUse · Edit|Write
      BLOCKED: build artifact
  [○] PreToolUse · Edit|Write     ← 꺼진 hook
      BLOCKED: session logs

~OMC: 비활성                      ← "~" = 추정치
──────────────────────────
  settings.json 열기
```

- `[●]` 채운 원 = 활성, `[○]` 빈 원 = 비활성
- 토글 클릭 → `settings.json` 즉시 수정 후 재스캔
- 쓰기 실패 시 팝오버 상단에 인라인 에러 표시
- ScrollView + maxHeight 320pt (rule/hook 수 많아도 안전)
- OMC 표시: `CLAUDE.md`에 "oh-my-claudecode" 포함 → "~OMC 활성 (추정)"

## on/off 토글 구현

**비활성화 (off)**: `settings.json.hooks.<Event>[]` 배열에서 해당 그룹을 꺼내
`settings.json._disabledHooks.<Event>[]`로 이동 후 저장.

**활성화 (on)**: `_disabledHooks`에서 꺼내 `hooks`로 복원.

```json
{
  "hooks": {
    "PostToolUse": [ ... 활성 항목 ]
  },
  "_disabledHooks": {
    "PreToolUse": [ ... 비활성 항목 ]
  }
}
```

- Claude Code는 `_disabledHooks`를 무시하므로 데이터 유실 없음.
- `_disabledHooks`는 airuncat 전용 필드. Claude Code가 추후 동명 필드를 도입하면 마이그레이션 필요.
- hooks 그룹 식별자: `SHA256(event + matcher + fullCommand)[0..<8]` hex — 내용 기반 hash.
- 저장 전 mtime 체크: 팝오버 열린 이후 파일 변경 시 "외부에서 변경됨 — 재스캔 후 다시 시도" 경고.
- Atomic write: tmp 파일 쓴 뒤 `rename(2)` 사용.

## 데이터 모델

```swift
struct RuleFile {
    let name: String    // 파일명 stem, e.g. "clt-build-only"
    let path: String
}

struct HookEntry: Identifiable {
    let id: String        // SHA256(event+matcher+command)[0..<8]
    let event: String     // "PreToolUse" | "PostToolUse"
    let matcher: String   // e.g. "Edit|Write"
    let commandSummary: String  // first 60 chars of first command
    var enabled: Bool
}

struct HarnessInfo {
    let projectPath: String
    let settingsPath: String   // <cwd>/.claude/settings.json
    let settingsMtime: Date    // 팝오버 열린 시점의 mtime
    var rules: [RuleFile]
    var hooks: [HookEntry]
    var omcPresent: Bool       // 추정치 (CLAUDE.md 문자열 매칭)
    var writeError: String?

    var enabledCount: Int { hooks.filter(\.enabled).count }
    var totalCount: Int  { rules.count + hooks.count }
    var badgeLabel: String {
        let active = rules.count + enabledCount
        return active == totalCount ? "H \(totalCount)" : "H \(active)/\(totalCount)"
    }
    var hasDisabledHook: Bool { hooks.contains { !$0.enabled } }
}
```

# 데이터 소스 / 의존

| 소스 | 경로 | 접근 |
|------|------|------|
| Rules | `<cwd>/.claude/rules/*.md` | FileManager glob |
| Hooks | `<cwd>/.claude/settings.json` | JSONSerialization read/write |
| OMC 감지 | `<cwd>/CLAUDE.md` | 문자열 포함 여부 |
| 설정 열기 | `open <cwd>/.claude/settings.json` | NSWorkspace |

**settings.json 쓰기 주의**: 쓰기 전 파일을 읽어 현재 내용에서 최소한 수정
(pretty-print로 저장). 포맷 변환으로 인한 불필요한 diff 최소화.

# 엣지케이스

- `.claude/` 없는 세션 → 배지 미표시 (조용히 생략)
- `settings.json` 파싱 실패 → hooks = [] 처리, 팝오버에 "파싱 오류" 표시
- hooks 그룹이 중첩 배열인 경우 (hooks-in-hooks): 첫 번째 depth만 처리
- 여러 세션이 같은 cwd를 공유 → 한 쪽에서 toggle하면 다른 쪽 팝오버도 재스캔 필요 (팝오버 열 때 매번 스캔)
- settings.json 쓰기 중 앱 강제 종료 → atomic write (tmp 파일 쓰기 후 rename) 사용
- `_disabledHooks` 키가 이미 있는 settings.json → 기존 항목에 append

# 검증 방법

1. `swift build` 통과
2. `/run-clawde` → 활성 세션(clawde) 행에 `H 5` 배지 (rules 4 + hooks 1 활성)
3. 배지 클릭 → 팝오버 열림: Rules 4개, Hooks 3개 (2 활성 / 1 비활성)
4. 비활성 hook 토글 ON → settings.json `_disabledHooks`에서 `hooks`로 이동 확인
5. 활성 hook 토글 OFF → settings.json `hooks`에서 `_disabledHooks`로 이동 확인
6. `.claude/` 없는 세션 → 배지 없음

# 미해결 질문

- `HookEntry` 식별을 index 기반으로 하면 settings.json이 외부에서 수정될 때 인덱스가 틀릴 수 있음.
  → 팝오버 열 때마다 fresh scan으로 해결 (캐시 없음).
- hooks 그룹 안에 `hooks` 배열이 여러 개인 경우: 각 하위 command를 별도 HookEntry로 펼칠지,
  그룹 전체를 하나의 단위로 볼지. → 그룹 단위가 UX 단순. 그룹 안에 여러 command는 summary로 "N개 명령"으로 표시.
