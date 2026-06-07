# Spec: session-custom-name

## Meta
- **Created**: 2026-06-06
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-06-06

## Goal
메뉴바 드롭다운에서 각 Claude Code 세션에 사용자가 직접 커스텀 이름을 붙일 수 있도록 한다. 앱 재시작 후에도 이름이 유지되어야 한다.

## Non-goals
- AI가 자동 생성하는 `aiTitle` 로직 변경 (aiTitle은 커스텀 이름이 없을 때 fallback으로 유지)
- Gemini 세션 커스텀 이름 (Phase 4 범위)
- 태그 기능 (별도 스펙으로 분리)
- 이름 검색/필터 UI (이 스펙에서는 표시/편집만)

## Research
- `SessionInfo` 구조체: `sessionId: String` (UUID stem, stable key), `var title: String` (mutable) — `SessionScanner.swift:22-24`
- 세션 스캔 시 title 결정 순서: `aiTitle` → `firstInstruction` → `projectName` — `SessionScanner.swift:116-117`
- 현재 title 표시: `Text(session.title)` in `SessionRow` — `MenuContentView.swift:92`
- 기존 영속 레이어 없음 (UserDefaults/JSON 미사용) — 신규 구현 필요
- `sessionId` = JSONL 파일명 stem (UUID): `SessionScanner.swift:151`
- `SessionStore` 단일 인스턴스, 3초마다 갱신: `AiruncatApp.swift:6`, `SessionStore.swift:15`
- 번들 ID: `com.jeongilin.airuncat` — `Info.plist:10` (Application Support 경로 결정 시 사용)
- `FileManager.default.homeDirectoryForCurrentUser` 접근 패턴 있음 — `SessionScanner.swift:38-47`

## Confirmed Goal
Claude Code 세션마다 사용자가 직접 이름을 편집할 수 있다. 커스텀 이름이 있으면 드롭다운 제목 자리에 aiTitle 대신 표시된다. 이름은 로컬 파일(JSON 또는 plist)에 세션 ID 키로 영속 저장된다. 앱 재시작·세션 재개 후에도 이름이 유지된다.

## Decisions

### D1: 편집 진입 — 인라인 더블클릭 (폴백: hover 편집 버튼)
- **Status**: resolved
- **Rationale**: 세션 행의 타이틀 영역을 더블클릭 → SwiftUI TextField 전환. 우클릭 메뉴는 드롭다운 내 이벤트 복잡, 별도 버튼은 hover 로직 추가 필요. **리스크**: MenuBarExtra `.window` 내 List row에서 `onTapGesture(count:2)`가 row 기본 탭 제스처와 충돌해 신뢰성이 떨어질 수 있다. **폴백**: 개발 중 검증 실패 시 row 오른쪽 끝 hover 연필 아이콘(`onHover` + 버튼)으로 전환. 양쪽 모두 TextField가 title 자리에 인라인 노출.

### D2: 타이틀 표시 우선순위 — `customName` → `aiTitle` → `firstInstruction` → sessionId prefix
- **Status**: resolved
- **Rationale**: D1에서 파생. 커스텀 이름 있으면 최우선. 없으면 기존 fallback 체인(`SessionScanner.swift:116-117`) 유지. `MenuContentView.swift:92`의 `Text(session.title)` 대신 `Text(session.customName ?? session.title)` 패턴 사용.

### D3: 이름 초기화 — 빈 문자열 저장 시 aiTitle로 자동 복원
- **Status**: resolved
- **Rationale**: 명시적 "삭제" 버튼 없이 필드를 비운 채 Enter하면 customName 엔트리를 제거(또는 nil로)하고 aiTitle fallback 사용. 별도 삭제 액션을 추가하는 것보다 단순.

### D4: 파일 오류 처리 — 빈 사전으로 시작
- **Status**: resolved
- **Rationale**: custom-names.json이 없거나 손상됐으면 빈 `[String: String]`으로 초기화. 앱이 중단되지 않고 커스텀 이름만 유실. 디렉토리(`~/.airuncat/`) 미존재 시 첫 저장 때 mkdir -p.

### D5: 저장 위치 — `~/.airuncat/custom-names.json`
- **Status**: resolved
- **Rationale**: UserDefaults는 마이그레이션/백업이 불편. Application Support는 경로가 길고 복잡. `~/.airuncat/`는 airuncat 전용 홈 폴더로 추후 다른 설정 파일 확장이 용이. 이미 `~/.claude/` 패턴과 일관성 있음.

### D6: 대상 범위 — 목록에 표시되는 모든 세션
- **Status**: resolved
- **Rationale**: active/idle/resting 상태 무관하게 드롭다운에 나타나는 모든 세션에 이름 붙이기 가능.

### D7: 고아 엔트리 — 삭제하지 않고 유지
- **Status**: resolved
- **Rationale**: JSONL이 삭제돼도 커스텀 이름 엔트리는 남겨둔다. 세션이 다시 나타나면 이름이 복원됨. 자동 정리는 별도 복잡성을 추가하고 실익이 적다.

### D8: 매핑 키 — sessionId (UUID stem) (assumed)
- **Status**: assumed
- **Rationale**: `SessionInfo.sessionId`는 JSONL 파일명 stem(UUID)으로 `claude -r`에도 쓰이는 안정적 식별자. 파일 경로(`id`)는 프로젝트 이동 시 변경될 수 있어 UUID가 더 안정적.

### D9: 중복 이름 — 허용 (assumed)
- **Status**: assumed
- **Rationale**: 커스텀 이름은 식별자가 아닌 라벨. 동일 이름이 여러 세션에 있어도 sessionId로 구분되므로 문제없음.

### D10: 이름 표시 — 드롭다운 폭 내 단일 행 tail truncation
- **Status**: resolved
- **Rationale**: 길이 제한 없이 TextField에서 자유 입력. 표시 시 `.lineLimit(1).truncationMode(.tail)` 적용. 메뉴 폭을 벗어나는 이름은 "..." 말줄임. 폭 확장 없음.

### D12: 편집 상태 격리 — 행별 독립 @State (draftName + isEditing)
- **Status**: resolved
- **Rationale**: SessionStore 3초 갱신이 발생해도 편집 내용을 보호하기 위해, `SessionRow` 컴포넌트 내부에 `@State var isEditing = false`, `@State var draftName = ""` 을 유지한다. 편집 진입 시 `draftName = session.customName ?? session.title`로 초기화 후 TextField에 바인딩. 이후 SessionStore가 `sessions`를 교체해도 `draftName`은 row-local @State이므로 영향받지 않는다. 스캔 타이머 일시 중단보다 단순하고 SwiftUI 패턴에 부합.

### D11: 창 dismiss 시 동작 — 현재 TextField 내용 저장
- **Status**: resolved
- **Rationale**: MenuBarExtra .window는 click-outside로 닫힌다. 편집 중 dismiss 시 TextField 내용을 저장(= `onSubmit`과 동일 처리). 취소(Escape)는 명시적으로 처리. 표준 macOS 패턴: NSTextField는 `resignFirstResponder` 시 자동 commit하는 것과 유사.

## Constraints
- 편집 중 SessionStore의 3초 갱신이 행을 재렌더링해 TextField 포커스/내용을 날려선 안 된다. (편집 중 해당 세션의 title 업데이트를 억제하거나 별도 @State로 격리)
- 편집 중 MenuBarExtra .window가 닫힐 때 편집 내용은 자동 저장 (D11)
- `~/.claude/projects/**/*.jsonl` 쓰기 금지 (read-only-sessions.md rule 준수)
- 빌드는 `swift build` 또는 `./build.sh`만 (clt-build-only.md rule 준수)

## Known Gaps
(none)

## Requirements

### R0: 세션에 커스텀 이름을 붙이고 앱 재시작 후에도 유지한다

#### R0.1: 커스텀 이름 있는 세션은 드롭다운에서 해당 이름으로 표시된다
- **Given**: sessionId "abc"에 커스텀 이름 "내 작업"이 저장되어 있고 앱이 실행 중
- **When**: 메뉴바 드롭다운을 연다
- **Then**: 해당 세션 행에 aiTitle 대신 "내 작업"이 표시된다

#### R0.2: 앱 재시작 후에도 커스텀 이름이 유지된다
- **Given**: sessionId "abc"에 커스텀 이름 "내 작업"이 저장된 상태에서 앱을 종료 후 재시작
- **When**: 드롭다운을 연다
- **Then**: "내 작업"이 그대로 표시된다

---

### R1: 편집 UI — 세션 행에서 인라인 TextField로 이름 편집에 진입한다 (D1, D12)

#### R1.1: 타이틀 영역 더블클릭으로 편집 모드 진입
- **Given**: 드롭다운이 열려 있고 세션 행이 표시된 상태
- **When**: 세션 행의 타이틀 영역을 더블클릭한다
- **Then**: 타이틀 Text가 draftName을 바인딩한 TextField로 교체되고 커서가 활성화된다

#### R1.2: (폴백) hover 연필 아이콘 클릭으로 편집 모드 진입
- **Given**: `onTapGesture(count:2)`가 MenuBarExtra 환경에서 신뢰성 문제가 확인된 경우
- **When**: 세션 행에 마우스를 올리면 나타나는 연필 아이콘을 클릭한다
- **Then**: 타이틀 TextField가 활성화되고 draftName에 현재 표시 이름이 채워진다

#### R1.3: 편집 중 SessionStore 3초 갱신이 draftName에 영향을 주지 않는다
- **Given**: 사용자가 TextField에 새 이름을 입력하는 중에 SessionStore 갱신이 발생
- **When**: `SessionStore.sessions` 배열이 교체된다
- **Then**: SessionRow의 `@State var draftName`은 변경되지 않고 입력 중이던 내용이 그대로 유지된다

---

### R2: 이름 표시 — 커스텀 이름 우선, 없으면 aiTitle fallback, 단일 행 truncation (D2, D10)

#### R2.1: 커스텀 이름이 있으면 title 자리에 우선 표시
- **Given**: sessionId에 customName이 존재
- **When**: SessionRow가 렌더링된다
- **Then**: `Text(session.customName ?? session.title)`에 의해 customName이 표시된다

#### R2.2: 커스텀 이름이 없으면 aiTitle(또는 firstInstruction) fallback 표시
- **Given**: sessionId에 customName이 없음 (nil 또는 미저장)
- **When**: SessionRow가 렌더링된다
- **Then**: 기존 `session.title` (aiTitle → firstInstruction → projectName 체인)이 표시된다

#### R2.3: 긴 이름은 드롭다운 폭 내 단일 행 말줄임으로 표시
- **Given**: 커스텀 이름이 드롭다운 폭을 초과
- **When**: SessionRow가 렌더링된다
- **Then**: 이름이 한 줄로 표시되며 끝이 "..."로 truncate된다. 창 폭은 확장되지 않는다

---

### R3: 편집 저장/취소 — Enter·dismiss·Escape 세 경로의 동작 (D3, D11)

#### R3.1: Enter(onSubmit)로 커스텀 이름 저장
- **Given**: TextField에 "작업 이름"이 입력된 편집 상태
- **When**: Enter 키를 누른다
- **Then**: customName이 "작업 이름"으로 저장되고, 편집 모드 종료, 드롭다운에 새 이름 표시

#### R3.2: Escape로 편집 취소, 이전 이름 복원
- **Given**: TextField에 임시 문자열을 입력 중인 편집 상태
- **When**: Escape 키를 누른다
- **Then**: draftName이 편집 진입 이전 값으로 복원되고 편집 모드 종료. 저장되지 않는다

#### R3.3: 빈 문자열 저장 시 커스텀 이름 삭제 → aiTitle 복원
- **Given**: sessionId에 커스텀 이름 "작업 이름"이 저장된 상태에서 편집 진입
- **When**: TextField 내용을 모두 지우고 Enter를 누른다
- **Then**: customName 엔트리가 제거(nil)되고 세션은 aiTitle을 표시한다

#### R3.4: 창 dismiss 시 TextField 내용 자동 저장
- **Given**: 편집 중 사용자가 드롭다운 밖을 클릭해 MenuBarExtra 창이 닫힌다
- **When**: 창이 dismiss된다
- **Then**: draftName 현재 내용이 저장되고 다음 창 열기 시 해당 이름이 표시된다

---

### R4: 영속 저장 — `~/.airuncat/custom-names.json` 읽기·쓰기 (D4, D5, D8)

#### R4.1: 커스텀 이름 저장 시 JSON 파일에 쓰기
- **Given**: sessionId "abc"에 이름 "내 작업"이 확정된 상태
- **When**: 저장 액션이 트리거된다 (R3.1 / R3.4)
- **Then**: `~/.airuncat/custom-names.json`에 `{"abc": "내 작업", ...}` 형식으로 기록된다. 디렉토리가 없으면 생성 후 쓴다

#### R4.2: 앱 시작 시 JSON 파일 로드
- **Given**: `~/.airuncat/custom-names.json`에 `{"abc": "내 작업"}`이 저장된 상태
- **When**: SessionStore가 초기화된다
- **Then**: customNames 딕셔너리에 `["abc": "내 작업"]`이 로드되어 세션 표시에 즉시 반영된다

#### R4.3: 파일 없거나 JSON 파싱 실패 시 빈 사전으로 초기화
- **Given**: `~/.airuncat/custom-names.json`이 존재하지 않거나 손상됨
- **When**: SessionStore가 초기화된다
- **Then**: customNames는 `[:]`로 초기화되고 앱은 정상 동작. 커스텀 이름 없이 aiTitle이 표시된다

---

### R5: 범위 및 고아 엔트리 (D6, D7)

#### R5.1: 모든 상태의 세션에 이름 붙이기 가능
- **Given**: resting 상태(30분 이상 비활성)인 세션이 목록에 표시됨
- **When**: 해당 세션 행에서 편집을 진입한다
- **Then**: TextField가 활성화되고 이름 편집이 가능하다

#### R5.2: 이름 붙인 세션의 JSONL이 삭제돼도 커스텀 이름 엔트리는 파일에 유지
- **Given**: sessionId "abc"에 커스텀 이름이 저장된 상태에서 JSONL 파일이 삭제됨
- **When**: 앱이 재시작되거나 스캔이 실행된다
- **Then**: `~/.airuncat/custom-names.json`의 "abc" 엔트리는 그대로 유지된다

#### R5.3: 고아 엔트리의 세션이 다시 나타나면 커스텀 이름 자동 복원
- **Given**: sessionId "abc"의 JSONL이 삭제됐다가 다시 생성됨. custom-names.json에 "abc" 엔트리 존재
- **When**: SessionStore 스캔이 실행된다
- **Then**: 해당 세션의 customName이 자동으로 적용되어 저장된 이름이 표시된다

## Tasks

### T1: CustomNameStore 구현 — JSON 읽기·쓰기 영속 레이어 [infra]
- **Fulfills**: R4.1, R4.2, R4.3
- **Depends on**: (none)
- **Files**: `Sources/airuncat/CustomNameStore.swift` (신규)
- `~/.airuncat/` 디렉토리 자동 생성, `custom-names.json` 읽기/쓰기
- 파싱 실패(파일 없음, 손상) 시 `[:]` fallback

### T2: SessionInfo + SessionStore에 customName 통합 [vertical]
- **Fulfills**: R0.2, R2.1, R2.2, R5.2, R5.3
- **Depends on**: T1
- **Files**: `Sources/airuncat/SessionScanner.swift`, `Sources/airuncat/SessionStore.swift`
- `SessionInfo`에 `var customName: String?` 추가
- `SessionStore`에 CustomNameStore 연동 + `setCustomName(sessionId:name:)` 메서드
- 스캔 시 customNames 딕셔너리에서 각 세션의 customName 주입

### T3: SessionRow 편집 UI 전체 구현 [vertical]
- **Fulfills**: R0.1, R1.1, R1.2, R1.3, R2.3, R3.1, R3.2, R3.3, R3.4, R5.1
- **Depends on**: T2
- **Files**: `Sources/airuncat/MenuContentView.swift`
- `@State var isEditing`, `@State var draftName` 추가
- 더블클릭 `onTapGesture(count:2)` 진입 구현; 검증 실패 시 hover 연필 아이콘으로 교체
- Enter(onSubmit): `SessionStore.setCustomName` 호출 + `isEditing = false`
- Escape: `draftName` 복원 + `isEditing = false`
- 창 dismiss: draftName 현재 내용 저장 (`onDisappear` 또는 `.onChange(of: isPresented)`)
- 표시: `.lineLimit(1).truncationMode(.tail)`

## External Dependencies

### Pre-work
- (none)

### Post-work
- T3 완료 후 `/run-clawde` 로 앱 재시작, 실제 드롭다운에서 더블클릭 동작 수동 확인
- `onTapGesture(count:2)` 신뢰성 검증: 실패 시 T3에서 hover 버튼 폴백으로 즉시 전환
- `swift build` 그린 확인 (빌드 훅 자동 실행)
