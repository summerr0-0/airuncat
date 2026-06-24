---
title: "코드 정리 스윕 (애매/하드코딩/목적불일치)"
date: 2026-06-24
status: active
---

# 목적

코드베이스를 반복 순회하며 **애매한 것 / 하드코딩된 것 / 목적에 안 맞는 것**을
찾아 수정하고 기록한다. 각 수정은 behavior-preserving을 원칙으로 하고 `swift build`
그린을 유지한다. 리스크 큰 변경은 자동 수정 대신 "백로그"에 남겨 사용자 판단을 받는다.

분류:
- **애매(ambiguous)** — 오해 부르는 네이밍, 불명확한 의도
- **하드코딩(hardcoded)** — 상수화/중앙화해야 할 매직값·경로·개인 키워드
- **목적불일치(off-purpose)** — 죽은 코드, 프로젝트 규칙/의도에 어긋나는 코드

---

## Iteration 1 — 2026-06-24

### 수정 완료 (build 그린 검증)

| # | 분류 | 위치 | 문제 | 수정 |
|---|------|------|------|------|
| 1 | 목적불일치+하드코딩 | `SessionScanner.swift` `SessionCategory`/`categorize()` | `SessionInfo.category`가 3곳에서 **설정만 되고 읽히는 곳이 전무**(죽은 코드). 내부 `learnKeys = ["obsidian","english","algorithm","interview","study/english"]`로 개인 키워드 하드코딩 | enum·필드·`categorize()`·`learnKeys` 전부 제거. 호출부 3곳(SessionScanner/GeminiScanner/NotificationManager) 정리 |
| 2 | 하드코딩 | `TagStore.swift` init | `homeDirectoryForCurrentUser.appendingPathComponent(".airuncat")` + `"tags.json"`/`"tag-pool.json"` 손수 조립 — `PathConstants` 우회 | `PathConstants.tags`/`.tagPool`/`.airuncatBase` 추가 후 사용 (경로 값 동일, 동작 보존) |
| 3 | 애매 | `SkillsView.swift` `obsidianMissing`/`missingObsidianNote` | 스킬 원본이 `~/.airuncat/skills`로 이전됐는데 식별자는 여전히 "Obsidian" 지칭(오해 유발). 실제 로직은 `SkillManager.skillsDir` 확인 | `skillsDirMissing`/`missingSkillsDirNote`로 리네임 (UI 텍스트는 이미 "Skills directory not found"로 정확) |

**근거 메모**
- #1: `grep`으로 `session.category` 읽기 0건 확인(프롬프트 쪽 `category`는 별개 String). 컴파일러가
  잔여 참조 없음을 확인(빌드 그린) → 죽은 코드 제거 안전.
- #2: 신규 `PathConstants` 값이 기존 하드코딩 경로와 문자열 동일 → 파일 위치 불변.

### 오탐(수정 안 함)
- `AiruncatApp.swift:17` `print("wrote \(out)")` — `--render-frames` 디버그 CLI 경로의 정상 출력(직후 `exit(0)`). 유지.
- `SkillManager`/`PromptManager`의 Obsidian 경로 하드코딩 — 일회성 마이그레이션 **소스 경로**라 의도된 것. 유지.

---

## 백로그 (다음 이터레이션 후보 — 자동 수정 보류, 검토 필요)

- **scan = 읽기인데 쓰기 부작용**: `SkillScanner.scan()`/`PromptScanner` 첫 줄 `migrateFromObsidianIfNeeded()`.
  점수/목록 조회(읽기)가 파일 복사(쓰기)를 트리거. 마이그레이션을 앱 시작 1회로 옮기는 게 맞음(동작 변경 → 검토).
- **매직 넘버**: `SessionStatus`의 `90`/`30*60`(단일 출처, 문서 주석 있음 — 우선순위 낮음),
  `SessionScanner` 512KB/4MB, `GeminiScanner` `48*3600`, `ProcessDetector` `3.0`s. 산재 여부 재확인 후 필요 시 명명상수화.
- **force-unwrap / try!** 감사 — 크래시 위험 지점 점검.
- **UI 매직 디멘션**: 팝오버 width 280, maxHeight 480/360 등 뷰별 상이 — 공통 상수 검토.

---

## 원칙
- 한 이터레이션 = 작은 배치 + `swift build` 그린 + 이 문서 갱신.
- behavior-preserving만 자동 수정. 동작 바뀌는 건 백로그 → 사용자 승인.
