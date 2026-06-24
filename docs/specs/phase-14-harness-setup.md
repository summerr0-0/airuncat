---
title: "Phase 14 — Harness 자동 세팅"
date: 2026-06-24
status: draft
---

# 목표

Phase 13의 Harness Score에서 **미충족(✗) 항목을 클릭 한 번으로 보완**한다.
점수의 ✗ 항목이 곧 "무엇을 만들어야 하는지" 목록이므로, 각 항목 옆에 안전한
생성/추가 액션을 붙여 누락된 하네스 기본기(CLAUDE.md / 프로젝트 rule / 민감파일 deny
권한)를 템플릿으로 자동 생성한다. 생성 후 재스캔으로 점수가 즉시 갱신된다.

# 설계 원칙

1. **기존 생성기 재사용 + 중복 제거** — 새 쓰기 로직을 만들지 않고 `RuleManager.create`,
   `HarnessManager.addPermission`을 묶는다. CLAUDE.md 템플릿은 기존
   `ClaudeMdPopoverView.createFile`과 **중복되지 않게 공유 함수로 추출**해 양쪽이 같은
   템플릿을 쓰게 한다(버튼별로 다른 CLAUDE.md가 생기는 것 방지).
2. **behavior-additive·비파괴** — 절대 기존 파일을 덮어쓰지 않는다. 파일이 "있지만 빈약"한
   경우(예: CLAUDE.md가 짧음)는 생성 대신 보강 안내만. 진짜 "부재"일 때만 생성.
3. **메트릭 게이밍 금지** — 점수만 올리는 빈 파일 생성 안 함. 템플릿에 실제 시작 내용 +
   TODO 가이드를 넣어 사용자가 이어 쓰게 한다. (템플릿은 의도적으로 토큰 ≥ 20을 충족해
   `prep-claudemd`/`설정 간결`를 즉시 통과시키되, 본문은 사용자가 채울 가이드다.)
4. **위험한 자동화 제외** — hook은 임의 명령을 실행하므로 **자동 주입하지 않는다**.
   hook 미충족 항목은 "settings.json 열기" 안내만(사용자가 직접 작성).
5. **부재 파일 견고성** — deny 추가 대상 프로젝트는 대개 `.claude/settings.json` 자체가
   없다. `addPermission`이 파일 부재 시 빈 `{}`에서 시작하도록 보강한다(기존엔 "읽기 실패"로
   막히던 잠재 버그 — 수동 "+ 추가"에도 영향).

# 범위

**In:**
- `HarnessSetup.swift`(신규) — 정적 함수로 생성 액션 캡슐화
  - `createClaudeMd(cwd:) -> String?` (부재 시에만, 템플릿 쓰기)
  - `createStarterRule(cwd:) -> String?` (`RuleManager.create` 위임)
  - `addSensitiveDenies(in:) -> HarnessInfo` (deny 권한 일괄 추가)
- `ScoreItem`에 `action: HarnessSetupAction?` 추가 — evaluate가 ✗ 항목 중
  자동 보완 가능한 것에만 액션 부여
- `HarnessPopoverView` axisRow: ✗ + action 있는 항목에 작은 "생성"/"추가" 버튼.
  실행 → 해당 함수 호출 → `rescan()`

**In (hook):**
- hook은 **비활성(`_disabledHooks`) 참고 템플릿**으로만 생성. 팝오버에 "꺼진 hook"으로
  나타나고, 사용자가 settings.json에서 실제 명령을 채운 뒤 기존 토글로 켠다.
  검토 전 자동 실행 0. 점수는 사용자가 **켜야** 오름(게이밍 방지).

**Out:**
- 켜진(활성) hook 자동 주입 (임의 명령 실행 위험)
- skill 생성 (Skills 탭에서 별도)
- `@import` 자동 추가 (참조할 docs 부재 가능 → 보류)
- "전체 한 번에 세팅" 벌크 버튼 (Phase 14.1 백로그 — 우선 항목별 수동 제어)
- 기존 파일 덮어쓰기/내용 품질 개선

# 액션 매핑 (✗ 항목 → 자동 보완)

| 점수 항목(id) | 조건 | 액션 | 구현 |
|---------------|------|------|------|
| `prep-claudemd` | CLAUDE.md **부재**(`claudeMdWordCount == 0`) | `.createClaudeMd` | 템플릿을 프로젝트 루트 `CLAUDE.md`에 쓰기 |
| `prep-rules` | 프로젝트 rule 0개 | `.createRule` | `RuleManager.create(name:"project-conventions", scope:.project, projectCwd:)` |
| `prep-deny` | deny 권한 0개 | `.addDenies` | 민감파일 deny 일괄 추가 |
| `ver-post`/`ver-pre` | hook 부재 | `.addHookTemplates` | Pre/PostToolUse 참고 hook을 **비활성**으로 생성 |
| 그 외 ✗ | — | 없음(버튼 미표시) | — |

> `addHookTemplates`는 두 항목(ver-post/ver-pre) 어느 쪽을 눌러도 Pre+Post 템플릿 한 쌍을
> `_disabledHooks`에 1회 추가(이미 동일 템플릿 있으면 스킵). 비활성이라 점수 즉시 변화 없음 —
> 사용자가 명령을 채우고 켜야 `ver-*`가 충족된다.

- CLAUDE.md가 **있지만 짧음**(wc>0 && wc<20)인 경우 `prep-claudemd`는 ✗지만
  `action == nil` → 버튼 대신 "내용 보강 필요"로 둔다(덮어쓰기 방지).

# 데이터 모델 변경

```swift
enum HarnessSetupAction {
    case createClaudeMd, createRule, addDenies, addHookTemplates
    var label: String {
        switch self {
        case .createClaudeMd, .createRule, .addHookTemplates: return "생성"
        case .addDenies:                                      return "추가"
        }
    }
}

struct ScoreItem: Identifiable {
    let id: String
    let label: String
    let passed: Bool
    let detail: String?
    var action: HarnessSetupAction? = nil   // ✗ 항목 중 자동 보완 가능한 것만
}
```

`evaluate()`에서 해당 항목에 액션 부여 (passed면 무시되므로 항상 세팅해도 무방하나,
명확성 위해 미충족 시 의미 있는 것만):
- `prep-claudemd`: `wc == 0 ? .createClaudeMd : nil`
- `prep-rules`: `.createRule`
- `prep-deny`: `.addDenies`
- `ver-post`/`ver-pre`: `.addHookTemplates`

# HarnessSetup.swift

```swift
enum HarnessSetup {
    /// 공유 CLAUDE.md 시작 템플릿. ClaudeMdPopoverView.createFile도 이걸 호출(중복 제거).
    /// 토큰 ≥ 20을 충족해 생성 직후 prep-claudemd/설정 간결 통과.
    static func claudeMdTemplate(projectName: String) -> String {
        """
        # \(projectName)

        ## 역할
        이 프로젝트가 무엇인지 한 줄로 적는다. (TODO)

        ## 구조
        주요 디렉토리와 파일의 역할을 적는다. (TODO)

        ## 규칙
        반복 지시·컨벤션을 적는다. 길어지면 .claude/rules/ 로 분리한다. (TODO)
        """
    }

    /// 프로젝트 루트 CLAUDE.md 생성 (부재 시에만). 반환: 에러 문자열 or nil.
    static func createClaudeMd(cwd: String) -> String? {
        let path = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        guard !FileManager.default.fileExists(atPath: path) else {
            return "CLAUDE.md가 이미 존재합니다"
        }
        let name = (cwd as NSString).lastPathComponent
        do {
            try claudeMdTemplate(projectName: name)
                .write(toFile: path, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "CLAUDE.md 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 프로젝트 시작 rule 생성 (RuleManager 위임).
    static func createStarterRule(cwd: String) -> String? {
        RuleManager.create(name: "project-conventions", scope: .project, projectCwd: cwd)
    }

    /// 민감파일 deny 권한 일괄 추가. 이미 있는 패턴은 addPermission이 스킵.
    /// settings.json 부재 시에도 addPermission이 빈 {}에서 시작(아래 HarnessManager 변경).
    static func addSensitiveDenies(in info: HarnessInfo) -> HarnessInfo {
        let patterns = ["Read(./.env)", "Read(./.env.*)", "Read(./**/*.pem)", "Read(./secrets/**)"]
        var current = info
        for p in patterns {
            let updated = HarnessManager.addPermission(pattern: p, kind: .deny, in: current)
            // "이미 존재"는 정상(스킵)으로 보고 계속, 그 외 쓰기 실패면 중단
            if let err = updated.writeError, !err.contains("이미 존재") {
                current.writeError = err
                return current
            }
            current = updated
            current.writeError = nil
        }
        return current
    }

    /// Pre/PostToolUse 참고 hook을 비활성(_disabledHooks)으로 1회 추가.
    /// 명령은 주석 플레이스홀더(켜도 no-op) — 사용자가 채워 넣고 토글로 켠다.
    static func addHookTemplates(in info: HarnessInfo) -> HarnessInfo {
        let templates: [(event: String, matcher: String, command: String)] = [
            ("PostToolUse", "Edit|Write", "# TODO: 편집 후 포맷터/빌드 실행 (예: swift build)"),
            ("PreToolUse",  "Edit|Write", "# TODO: 민감/빌드 산출물 편집 차단 (비제로 종료로 block)"),
        ]
        var current = info
        for t in templates {
            let updated = HarnessManager.addDisabledHookTemplate(
                event: t.event, matcher: t.matcher, command: t.command, in: current)
            if let err = updated.writeError, !err.contains("이미 존재") {
                current.writeError = err
                return current
            }
            current = updated
            current.writeError = nil
        }
        return current
    }
}
```

> deny 패턴은 Claude Code permission 형식(`Tool(pattern)`)을 따르며 공식 문서 예시
> (`Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)`)와 정렬. `./`=settings 기준 상대,
> `**`=gitignore 글로빙. 기존 airuncat settings의 allow 항목(`Bash(swift *)`)과 동일 컨벤션.

## HarnessManager.addPermission 변경 (must-fix)

settings.json 부재/파싱 실패 시 "읽기 실패"로 막던 것을 **빈 `{}`에서 시작**하도록 보강:

```swift
// 기존: guard let data..., var json... else { writeError="읽기 실패"; return }
// 변경:
var json: [String: Any] = [:]
if let data = try? Data(contentsOf: URL(fileURLWithPath: info.settingsPath)),
   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    json = parsed
}
```

mtime 가드는 그대로 둔다 — 파일 부재 시 `HarnessScanner.mtime`이 nil을 반환해
`if let current = ...` 가드가 자연 통과한다(거짓 "외부 변경됨" 없음). 첫 write가 파일을
원자적으로 생성. **removePermission/deleteHook은 변경 없음**(없는 걸 지울 일 없음).

## HarnessManager.addDisabledHookTemplate (신규)

`_disabledHooks[event]`에 hook 그룹을 추가하는 공개 함수. 기존 private `insertGroup`/
`writeJSON` 패턴 재사용. settings.json 부재 시 빈 `{}`에서 시작. 동일 (event,matcher,command)
해시가 이미 있으면 `"이미 존재"` 반환(중복 방지). 성공 시 `hooks`를 재스캔해 갱신된 info 반환.

```swift
static func addDisabledHookTemplate(event: String, matcher: String,
                                    command: String, in info: HarnessInfo) -> HarnessInfo {
    var updated = info
    var json: [String: Any] = [:]
    if let data = try? Data(contentsOf: URL(fileURLWithPath: info.settingsPath)),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { json = parsed }
    // mtime 가드 (파일 있으면)
    if let current = HarnessScanner.mtime(of: info.settingsPath),
       abs(current.timeIntervalSince(info.settingsMtime)) > 1 {
        updated.writeError = "외부에서 변경됨 — 재스캔 후 다시 시도"; return updated
    }
    let id = hookHash(event: event, matcher: matcher, command: command)
    if updated.hooks.contains(where: { $0.id == id }) { updated.writeError = "이미 존재"; return updated }
    let group: [String: Any] = ["matcher": matcher,
        "hooks": [["type": "command", "command": command]]]
    insertGroup(group, into: &json, key: "_disabledHooks", event: event)
    if let err = writeJSON(json, to: info.settingsPath) { updated.writeError = err; return updated }
    updated.hooks = scanHooks(settingsPath: info.settingsPath)   // ← scanHooks를 internal로
    updated.settingsMtime = HarnessScanner.mtime(of: info.settingsPath) ?? info.settingsMtime
    updated.writeError = nil
    return updated
}
```

> `HarnessScanner.scanHooks`가 현재 private이면 internal로 승격 필요(같은 모듈). insertGroup/
> writeJSON/hookHash는 HarnessManager 내부에 이미 있음.

# UI (axisRow 항목 행 확장)

```
│ 준비   L2  ●●○                              │
│   ✓ CLAUDE.md 존재 (312 words)             │
│   ✓ 프로젝트 규칙 분리 (rules 4)           │
│   ✗ 행동범위 제한            [추가]         │  ← deny 0 → addDenies
```

- ✗ + `item.action != nil` 일 때만 우측에 `Button(item.action!.label)` 표시(작게, accentColor).
- 탭 → 액션 실행(detached) → 성공 시 `rescan()`로 점수 갱신, 실패 시 기존 `errors` 배너에 표시.
- `.openSettings` → `NSWorkspace.shared.open(settingsPath)` (footer의 settings.json 버튼과 동일).
- 액션 진행 중 중복 탭 방지 플래그(`@State settingUp`).

# 변경 파일

| 파일 | 변경 |
|------|------|
| `HarnessSetup.swift`(신규) | claudeMdTemplate / createClaudeMd / createStarterRule / addSensitiveDenies |
| `HarnessManager.swift` | addPermission: settings.json 부재 시 빈 `{}` 시작 (must-fix) + `addDisabledHookTemplate` 신규 |
| `HarnessScanner.swift` | `scanHooks`를 private→internal 승격(HarnessManager에서 재사용) |
| `HarnessScoring.swift` | `ScoreItem.action` 필드(기본값 nil) + evaluate에서 ✗ 항목에 액션 부여 |
| `HarnessPopoverView.swift` | axisRow 항목에 액션 버튼(작게, lineLimit) + 실행 핸들러(rescan), `settingUp` 가드 |
| `ClaudeMdPopoverView.swift` | `createFile` 템플릿을 `HarnessSetup.claudeMdTemplate` 호출로 교체(중복 제거) |

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| CLAUDE.md 있지만 짧음 | `action=nil` → 버튼 없음, 덮어쓰기 방지 |
| rule 같은 이름 이미 존재 | RuleManager.create가 "이미 존재하는 Rule" 반환 → 배너 표시 |
| deny 패턴 일부 이미 존재 | addPermission "이미 존재" 스킵, 나머지 추가 |
| **settings.json 부재**(deny 0의 흔한 케이스) | addPermission이 빈 `{}`에서 시작 → 첫 write가 파일 원자 생성 |
| settings.json 외부 변경됨 | addPermission mtime 가드가 막음 → "외부에서 변경됨" 배너 후 rescan 유도 |
| deny 일괄 중 중간 실패 | 직전까지 추가분은 디스크에 남고 rescan이 실제 상태 반영, 실패는 배너 표시(부분 성공 정직 노출) |
| `.claude` 없는 프로젝트 | HarnessInfo=nil → 애초에 팝오버 없음(기존) |
| 팝오버 transient 닫힘 | 재오픈 시 HarnessPopoverView @State 새로 생성 → `settingUp` 리셋 |
| 액션 실패(쓰기 권한 등) | errors 배너에 에러 표시, 점수 불변 |

# 검증

1. `swift build` 그린
2. 빈 더미 프로젝트(`.claude`만): CLAUDE.md "생성" → 파일 생성·점수 상승 확인
3. deny "추가" → settings.json에 deny 4종 추가·축1 충족 확인
4. rule "생성" → `.claude/rules/project-conventions.md` 생성 확인
5. 이미 있는 항목엔 버튼 미표시 / 짧은 CLAUDE.md엔 버튼 없음 확인
6. hook ✗ → "생성" → hooks 섹션에 **비활성** Pre/Post 템플릿 2개 등장, 점수 즉시 불변 확인.
   settings.json에서 명령 채우고 토글 ON → `ver-*` 충족·점수 상승 확인
7. `/run-clawde`로 팝오버 육안 확인

# Next Action
- [x] Gemini 검토(불가 → 별도 Claude 리뷰어 패스), must-fix 3건 반영
- [x] 사용자 승인 (Step 3) — hook 포함(옵션 2) 승인
- [x] 개발 (Step 4) — HarnessSetup.swift 신규 + 4파일 수정, swift build 그린
- [x] 리뷰 (Step 5·6) — 별도 리뷰어, must-fix 3건 반영:
      ① imp-clean이 TODO 템플릿 hook을 클러터로 보지 않게(개선 축 역행 방지)
      ② settings.json 부재 vs 파싱실패 구분(깨진 파일 덮어쓰기 금지)
      ③ "이미 존재" 마커 상수화 + 스킵 시 settingsMtime 동기화
- [x] 테스트 (Step 7) — build.sh 번들 + 실행 크래시 없음
- [ ] 팝오버 ✗ 항목 "생성/추가/생성" 버튼 동작 육안 확인 (사용자)
- [ ] PR (Step 8) — 사용자 요청 시

## 알려진 트레이드오프
- hook 참고 템플릿은 비활성이라 `ver-*`는 켜야 충족(게이밍 방지). imp-clean은 TODO 템플릿을
  클러터로 보지 않으므로 점수 역행 없음. 단 H 배지는 비활성 hook 존재로 주황색이 됨(정상 신호).
