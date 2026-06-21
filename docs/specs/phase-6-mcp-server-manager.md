---
title: "Phase 6 — MCP 서버 관리"
date: 2026-06-21
status: active
---

# 목표

`~/.mcp.json`(글로벌)과 `<project>/.mcp.json`(프로젝트)에 등록된 MCP 서버를
airuncat GUI에서 목록 조회·활성화/비활성화·추가·삭제할 수 있게 한다.
OMC의 `skill-portfolio-analyzer`(MCP 등록 상태 감사)를 GUI로 대체한다.

# 데이터 소스

| 파일 | 역할 |
|------|------|
| `~/.mcp.json` | MCP 서버 목록 (등록/삭제) |
| `~/.claude/settings.local.json` | 활성화 상태 (`enabledMcpjsonServers` 배열) |
| `<project>/.mcp.json` | 프로젝트 로컬 서버 (현재 세션의 cwd 기준, Phase 6.1 이후) |

`~/.mcp.json` 형식:
```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": {}
    }
  }
}
```

`~/.claude/settings.local.json` 활성화 상태:
```json
{
  "enabledMcpjsonServers": ["context7"],
  "enableAllProjectMcpServers": true
}
```

**활성화 판정:**
- `enabledMcpjsonServers` 배열에 이름이 있으면 활성
- 없으면 비활성 (Claude Code가 실행하지 않음)
- `enableAllProjectMcpServers: true`는 프로젝트 `.mcp.json` 전체 허용 — 글로벌과 별개

**토글 메커니즘:** `~/.mcp.json`은 건드리지 않고 `enabledMcpjsonServers` 배열에서 이름 추가/제거.

# 범위

**In:**
- `MCPRecord` 모델: name, command, args, env, disabled, scope(global/project), sourcePath
- `MCPScanner`: `~/.mcp.json` 파싱 + 현재 활성 세션 cwd의 `.mcp.json` 파싱
- `MCPManager`: enable/disable(toggle `_disabled`), create, delete (atomic JSON write)
- `MCPView`: Sessions/Skills/Prompts/MCP 탭 추가 또는 Settings 패널 내 섹션
- 고아 탐지: command 실행파일 경로가 존재하지 않는 항목 (경고 표시)
- 글로벌(G) vs 프로젝트(P) 배지 구분

**Out:**
- MCP 서버 stdout/stderr 모니터링
- MCP 인증 플로우 (auth 필요 서버)
- `~/.claude/settings.json`의 `enabledMcpjsonServers` 편집 (Claude Code 내부 상태)

# UI 설계

## 탭 배치
Sessions / Skills / Prompts / **MCP** — 4번째 탭으로 추가.
탭 레이블 폭 검토: "Sessions"(56pt) + "Skills"(38pt) + "Prompts"(50pt) + "MCP"(28pt) + padding ≈ 280pt → 320pt 안에 들어감.

## MCP 탭 레이아웃
```
[검색 바]
──────────────────────────────────────────
  [G] context7     npx -y @upstash/...   ● 활성   [토글] [삭제]
  [G] my-server    python -m myserver    ○ 비활성  [토글] [삭제]
  [P] local-tool   node ./tool.js        ● 활성   [토글] [삭제]
──────────────────────────────────────────
  ⚠ broken-server: 명령어 없음 (npx foo) [삭제]
──────────────────────────────────────────
[Finder 열기]  [+ 추가]  [새로고침]
```

## 생성 폼 (인라인)
```
이름:     [my-server              ]
명령어:   [npx                    ]
인수:     [-y @my/mcp@latest      ]  (공백 구분)
범위:     [글로벌 ●] [프로젝트 ○]
[취소]                         [추가]
```

# 모델

```swift
enum MCPScope { case global, project }

struct MCPRecord: Identifiable {
    let id: String           // server name
    let command: String
    let args: [String]
    let env: [String: String]
    var disabled: Bool
    let scope: MCPScope
    let sourcePath: String   // ~/.mcp.json 또는 <cwd>/.mcp.json
}
```

# MCPScanner

```swift
enum MCPScanner {
    static let globalMCPPath: String  // ~/.mcp.json

    // 글로벌 + 현재 활성 세션 cwd의 .mcp.json 파싱
    // 세션 없으면 글로벌만
    static func scan(activeCwd: String?) -> [MCPRecord]

    // JSON 파싱: mcpServers 딕셔너리 → [MCPRecord]
    private static func parse(path: String, scope: MCPScope) -> [MCPRecord]
}
```

# MCPManager

```swift
enum MCPManager {
    static let mcpJsonPath: String    // ~/.mcp.json
    static let settingsLocalPath: String  // ~/.claude/settings.local.json

    // enabledMcpjsonServers 배열에서 이름 추가/제거
    static func toggle(_ record: MCPRecord) -> String?

    // ~/.mcp.json mcpServers에 신규 항목 추가
    // + enabledMcpjsonServers에 자동 추가 (활성 상태로 생성)
    static func create(name: String, command: String, args: [String]) -> String?

    // ~/.mcp.json에서 항목 제거 + enabledMcpjsonServers에서도 제거
    static func delete(_ record: MCPRecord) -> String?

    // JSON atomic write (.prettyPrinted + .sortedKeys 으로 diff 안정화)
    private static func writeJSON(_ dict: [String: Any], to path: String) -> String?
}
```

**toggle 구현:**
1. `settings.local.json` 읽기
2. `enabledMcpjsonServers` 배열에서 name 있으면 제거(비활성), 없으면 추가(활성)
3. atomic write

**create 구현:**
1. `~/.mcp.json` 읽기 (없으면 `{}`)
2. `mcpServers[name]` 추가
3. atomic write
4. `settings.local.json`의 `enabledMcpjsonServers`에 name 추가
5. atomic write

# MCPView

```swift
struct MCPView: View {
    @ObservedObject var store: SessionStore  // activeCwd용
    @State private var records: [MCPRecord] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showCreateForm = false
    // create form fields: name, command, argsText, scope
    @State private var errors: [String] = []
}
```

`activeCwd`: 가장 최근 활성 세션의 cwd (Phase 6.0에서는 글로벌 `~/.mcp.json`만 관리하므로 불필요 — 프로젝트 `.mcp.json` 지원은 Phase 6.1로 미룸).

# MenuContentView 변경

```swift
private enum Tab { case sessions, skills, prompts, mcp }  // mcp 추가

// tabBar에 "MCP" 탭 버튼 추가
// body에 MCPView(store: store) 분기 추가
```

# 수정/신규 파일 목록

| 파일 | 변경 |
|------|------|
| `Sources/airuncat/MCPScanner.swift` | 신규 |
| `Sources/airuncat/MCPManager.swift` | 신규 |
| `Sources/airuncat/MCPView.swift` | 신규 |
| `Sources/airuncat/MenuContentView.swift` | Tab enum + tabBar + body 분기 |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| `~/.mcp.json` 없음 | MCPManager.create 시 신규 생성 |
| JSON 파싱 실패 | 에러 배너 표시, 파일 미수정 |
| 동일 name 중복 추가 | "이미 존재하는 서버" 에러 |
| command 경로 없음 (npx 계열 제외) | ⚠ broken 배지 표시 |
| 프로젝트 .mcp.json 없음 | 프로젝트 범위 추가 시 신규 생성 |
| 활성 세션 없음 | 프로젝트 탭 숨김 또는 비활성 |

> `npx`, `node`, `python`, `python3`, `uvx`, `deno` 등 PATH 명령어는 broken 판정 제외.
> 절대경로(`/usr/local/bin/...`) 만 존재 여부 체크.

# 검증 방법

1. `swift build` 통과
2. 앱 재시작 → MCP 탭에 context7 서버 표시 (글로벌, 활성)
3. 토글 클릭 → `~/.claude/settings.local.json`의 `enabledMcpjsonServers`에서 이름 제거 확인, 배지 ○ 전환
4. 토글 재클릭 → `enabledMcpjsonServers`에 이름 재추가, 배지 ● 전환
5. `+ 추가` → name: `test-server`, command: `echo`, args: `hello` → 추가
   - `~/.mcp.json` mcpServers에 항목 추가 확인
   - 목록 즉시 표시
6. 삭제 → `test-server` 항목 제거 확인
7. Finder 열기 → `~/.mcp.json` 파일 열림 확인
