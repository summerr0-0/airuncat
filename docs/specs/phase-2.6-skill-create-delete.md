---
title: "Phase 2.6 — 스킬 추가 & 삭제 spec"
date: 2026-06-13
status: complete
---

# 목표

Skills Manager(Phase 2)에서 누락된 스킬 생성/삭제를 GUI로 완성한다.
현재는 Obsidian에서 직접 파일을 만들어야 하고, 앱에서는 링크 관리만 가능하다.
이번 Phase로 스킬 전체 생명주기(생성 → 링크 관리 → 삭제)를 앱 안에서 처리한다.

# 범위

**In:**
- 스킬 생성: 이름 + 설명 + 초기 링크 대상 입력 → `SKILL_*.md` + symlink 자동 생성
- 스킬 삭제: 원본 파일 + 연결된 symlink 전부 제거 (확인 UI 포함)

**Out:**
- 스킬 내용(body) 편집 — Obsidian에서 직접 (클릭 시 열기 기능은 이미 있음)
- 스킬 이름 변경 — 파일 이름 변경 + 링크 재생성은 복잡도가 높아 별도 Phase
- frontmatter 항목 편집 UI (description 이외 필드)
- undo/redo

# 동작 / UI

## 스킬 추가 — 인라인 폼 (Skills 탭 하단)

`bottomBar`의 Refresh 버튼 좌측에 "+ 스킬 추가" 버튼을 배치한다.
클릭 시 스크롤뷰 하단에 인라인 폼 섹션이 열린다 (NSPopover 아님, 같은 패널 안).

```
──────────────────────────────────────
[이름:  ________________________]
[설명:  ________________________]
연결:  [C✓] [G✓]            ← 배지 스타일 토글 (기본 C+G 모두 체크)
[취소]                 [생성]  ← 생성은 accentColor 버튼
──────────────────────────────────────
```

**입력 유효성:**
- 이름: `[a-z0-9-]`만 허용, 1~40자 (소문자 영숫자+하이픈). 입력 시 실시간 변환:
  - 대소문자 → 소문자
  - 공백 → `-`
  - `_` 포함 허용 외 문자 → 제거 (삭제, 치환 안 함)
  - 선행/후행 하이픈, 연속 하이픈(`--`)은 생성 버튼 비활성화
- 이름 중복 체크 2단계:
  1. 메모리상 `skills` 배열의 id와 비교 (O(n))
  2. `Obsidian/06_AI_Config/SKILL_[NAME.toUpperCase().replace("-","_")].md` 실파일 존재 여부 확인
  → 둘 중 하나라도 충돌하면 생성 버튼 비활성화 + "이미 존재하는 스킬" 표시
- 설명: 선택, 200자 제한. 줄바꿈/콜론/따옴표는 frontmatter 저장 시 따옴표 감싸기 + 줄바꿈 → 공백으로 단순화

**생성 시 동작:**
1. 파일명 계산: `SKILL_[이름.uppercased().replacingOccurrences("-","_")].md`
2. Obsidian 경로에 파일 생성 (frontmatter는 전역 규칙 4필드 준수, `agent` 필드 금지):
   ```markdown
   ---
   title: "[이름]"
   description: "[설명, 빈 설명이면 빈 문자열]"
   date: YYYY-MM-DD
   tags: []
   status: active
   ---
   
   ```
   설명 저장 규칙: `"description: \"\(desc.replacingOccurrences("\n"," "))\""` (콜론/따옴표 포함 시 외부 따옴표로 래핑)
3. C 체크된 경우 `~/.claude/commands/[이름].md` symlink 생성. 실패 시 `claudeError` 표시.
4. G 체크된 경우 `~/.gemini/commands/[이름].toml` symlink 생성. 실패 시 `geminiError` 표시.
5. 파일 생성 성공 기준: `FileManager.fileExists(atPath:)` 재확인 후 폼 닫기 + reload()
6. C/G 부분 실패: 파일은 생성됨 → 폼 닫고 reload() 후 에러 배지가 스킬 행에 표시
7. 파일 생성 자체 실패: 폼 유지 + 인라인 에러 표시

## 스킬 삭제 — 2단계 확인 (SkillRow 내부)

`SkillRow` 호버 시 우측에 휴지통 버튼(`trash`) 표시.
1단계 클릭 → 행 내부에 빨간 확인 배너 등장:

```
  deep-review   C✓ G–
  "Deep code review"
  ─────────────────────────────────
  [취소]   파일 및 링크를 모두 삭제합니다   [삭제]
```

2단계 "삭제" 클릭 → 실제 삭제 수행 후 목록에서 즉시 제거.

**삭제 순서 (항상 1→2→3 순서 진행, 중간 실패해도 다음 단계 시도):**
1. Claude symlink 제거 (`skills[idx].claudeLinkPath`)
   - `removeIfSymlink()` 재사용: symlink만 제거, 실파일이면 **건너뛰고 경고만** (기존 보호 철학 유지)
2. Gemini symlink 제거 — **두 확장자 모두 시도**:
   - `<name>.toml` → `removeIfSymlink()`
   - `<name>.md` (레거시) → `removeIfSymlink()`
3. Obsidian 원본 파일 제거 (`skills[idx].obsidianPath`)
   - `FileManager.removeItem(atPath:)` (휴지통 이동 아님)
4. 3단계 모두 완료 시 → `skills.removeAll { $0.id == skill.id }` + `orphans` 갱신 + reload()
5. 1·2 실패해도 3 진행. 3 실패 시 인라인 에러 표시 (스킬 행 유지)

**안전 장치:**
- 1·2의 실파일 보호: `removeIfSymlink()` 그대로 — 실파일이면 에러 문자열 반환, 스킬 행에 경고 표시하나 삭제는 계속 진행
- 원본 파일 삭제가 성공해야 목록에서 제거 (링크만 실패는 허용)
- 삭제 후 반드시 `reload()` 호출 → 잔여 orphan 재탐지

# 데이터 소스 / 의존

| 소스 | 역할 |
|------|------|
| `SkillScanner.obsidianBase` | 생성 대상 디렉토리 |
| `SkillScanner.claudeCommandsDir` | Claude symlink 위치 |
| `SkillScanner.geminiCommandsDir` | Gemini symlink 위치 |
| `SkillToggler.enable/disable` | symlink 생성/제거 재사용 |
| `SkillToggler.createSkill(name:description:link:)` | 새 추가 함수 |
| `SkillToggler.deleteSkill(_ skill:)` | 새 삭제 함수 |

# 신규/수정 파일

| 파일 | 변경 |
|------|------|
| `SkillToggler.swift` | `createSkill`, `deleteSkill` 추가 |
| `SkillsView.swift` | 추가 폼 UI, 삭제 확인 UI (SkillRow 확장) |

새 파일 없음.

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 이름 중복 | 메모리 + 디스크 2단계 체크, 생성 버튼 비활성화 |
| Obsidian 디렉토리 없음 | `createDirectory(withIntermediateDirectories: true)`로 자동 생성 |
| symlink 생성 실패 | 파일은 생성됨, 에러 표시 + reload 후 상태 반영 |
| 원본 파일이 심볼릭 링크인 경우 | 없지만, `removeItem` 은 symlink도 안전하게 제거 (타겟 보존) |
| 빈 이름 제출 | 생성 버튼 비활성화 |
| 삭제 중 symlink 없음 | lstat 실패 → skip (에러 없음) |
| 삭제 중 symlink가 실파일 | 건너뛰고 경고만, 파일 삭제는 계속 진행 |
| 삭제 중 Gemini `.toml` + `.md` 둘 다 있음 | 둘 다 개별 시도 |
| 삭제 중 원본 파일 없음 | 에러 표시, 목록에서 제거 |
| 삭제 후 orphan 잔존 | reload() 후 Orphan Links 섹션에 재표시 |

# 검증 방법

1. `swift build` 통과
2. "+ 스킬 추가" → 이름 `test-skill`, 설명 `테스트`, C+G 체크 → [생성]
   - `~/Obsidian/document/06_AI_Config/SKILL_TEST_SKILL.md` 생성 확인
   - `~/.claude/commands/test-skill.md` symlink 확인
   - `~/.gemini/commands/test-skill.toml` symlink 확인
   - Skills 목록에 즉시 표시
3. 생성한 스킬 호버 → 휴지통 → 확인 → [삭제]
   - 파일 + 양쪽 symlink 모두 제거 확인
   - 목록에서 즉시 사라짐
4. 중복 이름 입력 → 생성 버튼 비활성화 확인
5. C만 체크 후 생성 → Claude 링크만 생성, Gemini 미연결 상태 확인
