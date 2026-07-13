---
title: "Phase 17a — rule 템플릿 라이브러리"
date: 2026-07-12
status: active
---

# 목표

Harness의 rule 생성을 빈 껍데기(`createStarterRule` — "여기에 제약을 기술한다" 한 줄)에서
**큐레이팅된 템플릿 선택**으로 진화시킨다. Phase 15 레시피(훅)와 동형의 패턴을 rules에 적용:
고르고 → 내용 보고 → 추가. `direction.md` 로드맵 17+의 "rule 템플릿 라이브러리".

# 설계 원칙

1. **Phase 15와 동형** — `ProjectHookRecipe` 카탈로그 패턴 그대로: 정적 카탈로그 + 미리보기 + 적용.
2. **일반론이 아닌 강제 가능한 제약만** — "코드를 잘 짜라"류 금지. 각 템플릿은
   위반이 판별 가능한 구체 제약(이 repo의 rules가 모범: read-only-sessions 등).
3. **타입 인식** — `ProjectTypeDetector` 재사용, 타입별 템플릿 + 공통 템플릿.

# 카탈로그 (초기 6종)

| id | 제목 | 타입 | 내용 요지 |
|----|------|------|----------|
| no-secrets | 시크릿 하드코딩 금지 | 공통 |
| no-destructive-git | 파괴적 git 금지 | 공통 |
| no-new-dependencies | 무승인 의존성 금지 | 공통 | ← prefer-existing-patterns를 결과 기반으로 교체(리뷰어: 프로세스 강제는 판별 불가) |
| build-must-pass | 빌드 그린 유지 | swift/node/rust/go |
| test-with-changes | 변경엔 테스트 동반 | node/python/rust/go |
| swift-clt-only | CLT 빌드만 | swift |

파일명 = `<id>.md`, `.claude/rules/`에 생성. **frontmatter 없음**(plain md — readSummary 호환,
rules-injector는 frontmatter 없는 룰을 전역 주입으로 취급하므로 정확). 점수 영향: 준비/맥락 축
rule 항목만(prep-rules/ctx-rules — createStarterRule과 동일).

## 템플릿 본문 전문 (원칙 2의 실체 — 구현은 이 텍스트 그대로)

**no-secrets**
```
# no-secrets
- API 키·토큰·비밀번호·인증서를 소스 코드/커밋에 직접 넣지 않는다.
- 비밀값은 .env 또는 환경변수로 참조하고, .env는 .gitignore에 있어야 한다.
- 예시/문서에도 실제 값 대신 placeholder(YOUR_API_KEY)를 쓴다.
- 실수로 커밋된 비밀값은 즉시 무효화(rotate)한다.
```

**no-destructive-git**
```
# no-destructive-git
- 공유 브랜치에 git push --force 금지. 원격 브랜치를 임의로 삭제하지 않는다.
- 커밋 유실을 부르는 git reset --hard 대신 revert 커밋으로 되돌린다(히스토리 보존).
- rebase는 로컬 미공유 브랜치에서만.
```

**no-new-dependencies**
```
# no-new-dependencies
- 새 외부 의존성(패키지) 추가는 사용자 승인 없이는 금지.
- 기존 유틸과 같은 역할의 헬퍼를 새로 만들지 않는다 — 있으면 기존 것을 확장한다.
- 표준 라이브러리로 충분한 일에 의존성을 붙이지 않는다.
```

**build-must-pass** ({BUILD_CMD}는 감지 타입 명령으로 치환: swift build / npm run build / cargo build / go build ./...)
```
# build-must-pass
- 편집을 마친 시점에 빌드({BUILD_CMD})가 통과해야 한다.
- 빌드 실패 상태로 다음 작업이나 커밋으로 넘어가지 않는다.
- (build-on-edit 훅이 없을 때의 규율 — 훅이 켜져 있으면 훅 출력이 곧 검증이다.)
```

**test-with-changes**
```
# test-with-changes
- 구현(src) 변경 커밋에는 대응하는 테스트 변경/추가를 동반한다.
- 테스트를 붙일 수 없는 변경(설정·문서·순수 이동 리팩터)은 커밋 메시지에 사유 한 줄을 남긴다.
- 기존 테스트를 삭제하거나 스킵 처리해서 통과시키지 않는다.
```

**swift-clt-only**
```
# swift-clt-only
- 빌드는 swift build만 사용한다. xcodebuild/.xcodeproj/.xcworkspace 의존 금지.
- 에셋 카탈로그(.xcassets) 등 풀 Xcode 전용 기능에 의존하지 않는다.
```

# 범위

**In:**
- `RuleTemplate.swift`(신규): `RuleTemplate` 구조체 + `catalog` — id/제목/설명/대상 타입/본문.
  `applicable(to types:) -> Bool`.
- `HarnessPopoverView` rules 섹션 헤더에 "+ 템플릿" 진입점(Phase 15 "+ 레시피"와 동일 패턴)
  → 펼침 목록: 제목·본문 미리보기·[추가]. 이미 동명 파일 존재 시 "이미 존재" 회색.
- 추가 = `RuleManager.create(name:scope:projectCwd:body:)` — **body 파라미터 추가**(리뷰어 권고:
  별도 writer는 디렉토리 생성/존재 검사/원자 쓰기 중복. 기본값 nil=기존 placeholder 유지,
  createStarterRule 무변경). 기존 파일 있으면 거부(덮어쓰기 금지).
- 오류는 Phase 15와 동형으로 **상단 errorBanner**(errors 배열). "+ 새 Rule" 폼은 그대로 공존.
- 생성 후 rescan → rules 섹션에 등장.

**Out:**
- 마법사(Phase 16) 2단계 교체 — 후속에서 마법사가 이 카탈로그를 쓰도록 통합 가능(지금은 병행).
- 사용자 커스텀 템플릿 저작/저장.
- 글로벌 rules(~/.claude/rules) 대상 — 프로젝트 스코프만.

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| 동명 rule 존재 | [추가] 비활성 + "이미 존재" 표시 |
| .claude/rules 부재 | 디렉토리 생성 후 파일 생성(RuleManager 관례) |
| 타입 비대상 템플릿 | 목록에서 회색 + "이 타입엔 해당 없음" |
| 쓰기 실패 | 행 인라인 오류 |

# 변경 파일

| 파일 | 변경 |
|------|------|
| `RuleTemplate.swift`(신규) | 카탈로그 + write(to:) |
| `HarnessPopoverView.swift` | rules 섹션 "+ 템플릿" 피커 |

# 검증

1. `swift build` 그린 + 재실행.
2. 더미 프로젝트: "+ 템플릿" → no-secrets 추가 → `.claude/rules/no-secrets.md` 생성·내용 일치
   → rules 섹션 등장 → 재추가 시 "이미 존재". (헤드리스: write(to:) 직접 검증)
3. 이 repo(swift): 기존 파일은 clt-build-only.md라 **파일명 충돌 없음 → swift-clt-only는
   추가 가능 상태가 정상**. 의미적 중복 감지는 범위 밖(파일명 기준만).
4. python 더미: build-must-pass가 "해당 없음" 회색.

# Next Action
- [x] Claude 리뷰어 패스 — NEEDS_FIX 반영(body 파라미터·본문 전문 명기·결과 기반 교체·frontmatter 없음·errorBanner 동형)
- [x] 사용자 승인 — 루프 사전 전체 승인
