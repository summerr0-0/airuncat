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

## Iteration 2 — 2026-06-24

### 수정 완료 (build 그린 검증)

| # | 분류 | 위치 | 문제 | 수정 |
|---|------|------|------|------|
| 4 | 목적불일치 | `SkillScanner.scan` / `PromptScanner.scan` | 읽기 함수가 첫 줄에서 `migrateFromObsidianIfNeeded()`(파일 복사=쓰기)를 트리거. read-only 의도와 충돌 | 마이그레이션을 `AiruncatApp.init`로 1회 hoist, 두 scan은 순수 읽기로 |

**근거 메모**
- 두 마이그레이션 모두 `guard !fileExists(dir)`로 가드된 **일회성 no-op** → 시작 시 1회 호출과
  end-state 동일. init은 모든 scan보다 먼저 실행되므로 순서 안전. 빌드 그린.

### 오탐(수정 안 함)
- **force-unwrap 3건** (`MenuContentView` SF Symbol `tag`/`tag.fill`, `ApplicationController`
  설정 URL) — 전부 항상 성공하는 상수 대상. 가드로 바꾸면 노이즈만 증가. 안전, 유지.
- `try!` / `as!` — 0건.

---

## 백로그 (다음 이터레이션 후보 — 자동 수정 보류, 검토 필요)

- **매직 넘버**: `SessionStatus`의 `90`/`30*60`(단일 출처, 문서 주석 있음 — 우선순위 낮음),
  `SessionScanner` 512KB/4MB, `GeminiScanner` `48*3600`(이미 named), `ProcessDetector` `3.0`s(이미 default param).
  대부분 단일 출처/명명됨 → 실익 낮음. 산재된 것만 선별.
- **UI 매직 디멘션**: 팝오버 width 280, maxHeight 480/360 등 뷰별 상이 — 공통 상수 검토.
- **"이미 존재" 등 한국어 에러 문자열 매칭** (Phase 14 `applyAll`는 마커 상수화 완료) — 다른 곳에
  문자열 비교로 흐름 제어하는 데가 있는지 점검.

---

## Iteration 3 — 2026-06-24 (dry, 스윕 마무리)

### 결과: 고가치 발견 없음
스캔 항목별:
- **하드코딩 로직 문자열**(버전/모델/제어용): 없음.
- **문자열 동등비교 기반 제어흐름**: 없음 (Phase 14 `applyAll` 마커는 이미 상수화).
- **UI 디멘션**: 팝오버별 width(Harness 280 / ClaudeMd 300 / Menu 320)·maxHeight는
  콘텐츠에 맞춘 **의도적 차이**지 중복 매직값이 아님. 공유 상수화는 미관 변경·시각 검증 필요라
  실익 대비 리스크 → 미수정.
- **매직 넘버**(잔여): 대부분 단일 출처 + 문서 주석 or 이미 named/default param. 산재 중복 없음.

dry 이터레이션 → 스윕 종료. (loop-until-dry: 1회 dry면 마무리)

---

## 스윕 총괄

| 이터 | 수정 | 핵심 |
|------|------|------|
| 1 | 3건 | 죽은 코드+개인키워드 하드코딩 제거(SessionCategory), TagStore 경로 중앙화, SkillsView 오해 네이밍 |
| 2 | 1건 | 스캐너 쓰기 부작용 제거(마이그레이션 → 시작 1회), force-unwrap/try! 감사(클린) |
| 3 | 0건 | dry — 고가치 발견 없음, 종료 |

총 4건 수정(전부 behavior-preserving, build 그린). 동작 바뀌는 항목은 자동 수정 안 함.
재개가 필요하면 새 영역(예: 동시성/Sendable 감사, 테스트 커버리지) 지정해 다시 `/loop`.

---

## 원칙
- 한 이터레이션 = 작은 배치 + `swift build` 그린 + 이 문서 갱신.
- behavior-preserving만 자동 수정. 동작 바뀌는 건 백로그 → 사용자 승인.
- dry 이터레이션(고가치 발견 0)이면 churn 방지 위해 종료.
