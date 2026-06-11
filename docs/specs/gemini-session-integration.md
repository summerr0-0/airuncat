# Spec: Gemini CLI 세션 연동

## 목표

`~/.gemini/tmp/*/chats/*.jsonl`을 파싱해 Gemini CLI 세션을 드롭다운에 Claude 세션과 함께 표시한다.
각 세션의 AI 종류를 구분 표시하고, 활성 Gemini 세션도 고양이 속도에 반영한다.
클릭 시 iTerm2 탭 포커스 또는 새 탭에서 Gemini 재개.

## 범위

### In

- Gemini 세션 파싱 (`GeminiScanner.swift` 신규)
- 드롭다운에 Claude + Gemini 세션 통합 표시 (mtime 기준 정렬 유지)
- 각 세션 행에 AI 종류 뱃지: `C` (Claude, 기본 accent) / `G` (Gemini, Google 계열)
- 고양이 속도에 Gemini 활성 세션 수 포함 (기존 Claude liveCount에 합산)
- Gemini live process 감지 (`ProcessDetector` 확장)
- 클릭 시 iTerm2 탭 포커스 (cwd 매칭, 기존 ITermController 재사용)
- 포커스 실패 시 새 탭에서 `cd <cwd> && gemini` 실행

### Out

- Gemini 세션 resume by ID (Gemini CLI에 `-r` 상당 플래그 없음)
- Gemini 세션 custom name (Phase 2로 연기)
- Gemini 세션 태그 (Phase 2로 연기)
- Gemini 세션 idle 알림 (Phase 2로 연기)
- Claude 이외의 다른 AI 도구 (Codex 등) 연동

## 데이터 소스 & JSONL 포맷

경로: `~/.gemini/tmp/<project-dir>/chats/<session-file>.jsonl`

- `<project-dir>`: 워크스페이스 cwd의 마지막 경로 컴포넌트 (예: `clawde`, `backend`)
  - 예외: 해시형 디렉토리 이름도 존재 (`04a09a9d...`), 이 경우 session_context에서 cwd 파싱
- `<session-file>`: `session-YYYY-MM-DDTHH-MM-<uuid-short>.jsonl`

**실측 라인 구조:**

```
Line 1 (header):
{"sessionId":"UUID","projectHash":"...","startTime":"ISO8601","lastUpdated":"ISO8601","kind":"main"}

Line 2+ (events):
{"id":"...","timestamp":"ISO8601","type":"user","content":[{"text":"..."}]}
{"id":"...","timestamp":"ISO8601","type":"gemini","content":"<응답 텍스트>","tokens":{...},"model":"..."}
{"id":"...","timestamp":"ISO8601","type":"info","content":"..."}
{"$set":{"messages":[...],"lastUpdated":"..."}}   ← 구형 배치 포맷 (드물게 등장)
```

**추출 필드:**

| 필드 | 소스 |
|------|------|
| sessionId | Line 1 `sessionId` |
| startTime | Line 1 `startTime` |
| cwd | 첫 `type:"user"` 메시지의 `<session_context>` 텍스트에서 "Workspace Directories:\n  - <path>" 파싱; 실패 시 `<project-dir>`를 projectName으로만 사용 |
| title | `type:"user"`인 첫 비-session_context 메시지의 텍스트 (앞 200자) |
| lastActivity | 파일 mtime (Claude와 동일 기준) |
| workState | 마지막 이벤트 type: `"user"` → `.working`, `"gemini"` → `.responded`, 그 외 → `.working` |
| messageCount | `type:"user"` + `type:"gemini"` 이벤트 수 |

## AIKind 확장

`SessionInfo`에 `aiKind: AIKind` 필드 추가:

```swift
enum AIKind {
    case claude
    case gemini
}
```

기존 Claude 세션은 `aiKind: .claude`로 초기화. `ITermController.openNew`는 `aiKind`에 따라 명령어 분기.

## Gemini live process 감지

`ProcessDetector.liveGeminiCwds() -> Set<String>` 추가.

Gemini CLI는 Node.js 래퍼이므로 `comm` 필드가 `node`로 표시될 수 있어 `ps comm` 기반 탐지는 신뢰도가 낮음.
대신 `lsof`로 `~/.gemini/tmp` 경로를 열고 있는 프로세스를 추적:

```bash
lsof +D ~/.gemini/tmp -F pn 2>/dev/null | awk '/^p/{pid=$0} /^n.*\.jsonl/{print pid}' | sort -u
```

추출된 PID 목록 → 각 PID의 cwd를 `lsof -p <pid> -d cwd -Fn`으로 획득.

**사전 체크:** 앱 기동 시 `which gemini`로 CLI 설치 여부 확인.
미설치 시 `GeminiScanner` 스캔 건너뜀 (UI에서 Gemini 섹션 미표시).
설치된 경우 절대 경로를 캐시해 `openNew` 명령어에 사용 (GUI 앱의 PATH 미로드 방지).

`liveCwds()` + `liveGeminiCwds()` → `SessionStore.refresh()`에서 합산.

## UI / 동작

### 드롭다운 세션 행

```
[C] airuncat-dev       (active) [#]   ← Claude
[G] my-backend         (idle)   [#]   ← Gemini
```

- `[C]` / `[G]` 뱃지: 5pt capsule, monochrome (template image와 동일하게 시스템 틴팅)
- 기존 레이아웃(태그 버튼, 상태칩, 커스텀 이름)과 공존

### 고양이 속도

```swift
let liveCount = visibleClaudeSessions.count + visibleGeminiSessions.count
```

Gemini 활성 세션 수도 합산해 속도 계산.

### 클릭 동작 (ITermController)

`SessionInfo.aiKind`에 따라 `openNew` 명령어 분기:
- `.claude`: `cd '<cwd>' && claude -r <sessionId>` (기존)
- `.gemini`: `cd '<geminiPath>' <cwd> && gemini` — geminiPath는 `which gemini` 절대 경로 캐시 사용

Gemini는 resume by ID 미지원이므로 항상 새 세션 시작. 드롭다운 Gemini 세션 행에
`↩ 새 세션` 아이콘 또는 툴팁으로 동작 차이를 사용자에게 명시.

`focus(for:)` 로직은 cwd 기반이므로 aiKind 무관하게 동일하게 동작.

## 엣지케이스

| 상황 | 처리 |
|------|------|
| `<project-dir>`가 해시형 | session_context 파싱 실패 시 cwd="" + projectName=폴더명으로 fallback |
| `$set` 배치 포맷 라인 | 파싱 건너뜀 (미지원, 구형 포맷) |
| `type:"info"` 이벤트 | 무시 |
| mtime 동일 → 캐시 히트 | 기존 SessionScanner 캐시 전략 그대로 적용 |
| Gemini 세션 파일 > 4MB | head/tail 512KB 청크 (Claude와 동일) |
| 같은 cwd에 Claude + Gemini 동시 실행 | 둘 다 표시 (aiKind로 구분, 중복 제거 로직은 same-aiKind 내에서만) |
| Gemini 세션이 0개 | 드롭다운에서 숨김 (Claude 전용과 동일 UI) |
| live process 감지 타임아웃 | 기존 3초 타임아웃 적용 |
| 동일 cwd Gemini 세션 여러 개 | 최근 mtime 우선 표시 (Claude와 동일 정책) |
| 30일 이상 된 Gemini 세션 파일 | 스캔 건너뜀 (resting보다 오래됨, 노이즈 방지) |
| gemini CLI 미설치 | GeminiScanner 전체 스킵, UI에서 Gemini 섹션 미표시 |
| hash형 project-dir + session_context 파싱 실패 | cwd="" + projectName=폴더명으로 fallback; 클릭 시 cwd 빈값으로 openNew 못 함 → 행 클릭 비활성화 또는 경고 |

## 구현 파일

| 파일 | 변경 |
|------|------|
| `SessionScanner.swift` | `SessionInfo`에 `aiKind: AIKind` 추가; 기존 파싱 결과는 `.claude` |
| `GeminiScanner.swift` | 신규. `~/.gemini/tmp/*/chats/*.jsonl` 파싱 |
| `ProcessDetector.swift` | `liveGeminiCwds()` 추가 |
| `SessionStore.swift` | `refresh()`에 GeminiScanner 호출 + Gemini liveCwds 합산; `visibleSessions` 로직에 aiKind-aware 중복 제거 |
| `ITermController.swift` | `openNew`에 aiKind 분기 |
| `MenuContentView.swift` | 세션 행에 `[C]`/`[G]` 뱃지 추가 |

## 검증

1. `./build.sh` 그린
2. Gemini CLI로 임의 프로젝트에서 세션 시작 → 드롭다운에 `[G]` 뱃지로 표시 확인
3. Gemini 세션이 있을 때 고양이 속도 증가 확인
4. `[G]` 세션 클릭 → 해당 iTerm2 탭 포커스 (없으면 새 탭 + `gemini`)
5. Claude + Gemini 동시 실행 → 둘 다 표시, aiKind 뱃지 구분 확인
6. Gemini 세션만 있는 경우 / Claude만 있는 경우 각각 정상 동작 확인
7. 앱 재시작 후 Gemini 세션 목록 유지 확인 (mtime 캐시)
