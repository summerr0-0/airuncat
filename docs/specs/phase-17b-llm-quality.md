---
title: "Phase 17b — LLM 내용 품질 진단"
date: 2026-07-12
status: active
---

# 목표

Harness Score(정적 신호)가 못 보는 것 — **CLAUDE.md/rules의 내용 품질**(모호함·모순·
플레이스홀더 방치) — 을 LLM으로 진단한다. `/check-harness`의 context-quality-reviewer
축을 airuncat 버튼으로. `direction.md` 로드맵 17b.

# 비용 원칙 (이 스펙의 헌법)

1. **수동 트리거만** — Harness 팝오버의 "LLM 진단" 버튼 클릭 시 **1회** 실행.
   tick/스캔/자동 재실행 절대 없음. 실행 전 버튼에 "토큰 사용" 명시.
2. **입력 최소화** — CLAUDE.md + 프로젝트 rules만 전송(각 4KB 캡, 세션/코드 미전송).
3. **캐시** — 결과를 입력 해시와 함께 `~/.airuncat/quality-cache.json`에 저장.
   입력이 같으면 재클릭해도 캐시 표시(재실행은 별도 "다시 진단" 버튼).

# 실행 방식 (리뷰어 실검증 반영)

- `claude -p <prompt> --output-format json --model haiku` 자식 프로세스.
  래퍼 JSON의 `result` 필드에 모델 텍스트(+`session_id`, `total_cost_usd`).
- **바이너리 발견**: 메뉴바 앱은 셸 PATH 미상속 + 이 머신은 nvm 경로에만 존재 →
  `/bin/zsh -lc 'command -v claude'` 1회 실행해 절대경로 캐시, 이후 `Process`가
  **argv로 직접 exec**(프롬프트를 셸로 보간하지 않음 — UsageAPIClient 무셸 관례).
- **`--bare`**: 프로젝트 CLAUDE.md/rules/hooks/MCP 로딩 생략 — 없으면 입력 토큰이
  사실상 2배(컨텍스트+프롬프트 중복)이고 MCP 스폰·훅 발화 부작용. 플래그 실재는
  구현 시 `claude --help`로 확인(버전 의존), 없으면 중립 cwd만으로 완화.
- **재귀 완화**: 실행 cwd = `~/.airuncat`(중립) — 진단 세션 JSONL이 실제 프로젝트
  행과 충돌하지 않음. 추가로 SessionScanner가 cwd == airuncatBase 세션을 숨김
  (자기 진단이 고양이를 달리게 하지 않게).
- **2층 파싱**: 래퍼 JSON → `result` 추출 → ``` 펜스 제거 → 내부 JSON 파싱.
  (`--json-schema`/structured_output이 설치 버전에 있으면 우선 채택 — help로 확인)
- **상태는 뷰 밖에**: 진단 실행/결과는 `QualityScanner`의 @MainActor 싱글턴 상태 +
  캐시 파일에 존재 — 팝오버(.transient)가 닫혀도 재오픈 시 "진단 중"/결과 복원.
- 타임아웃 60s. 실패는 인라인 오류(재시도 버튼). 캐시 해시에 프롬프트 버전+모델 포함.

# 프롬프트 (고정)

```
다음은 한 프로젝트의 CLAUDE.md와 rules다. 아래 4가지만 JSON으로 평가하라:
{"placeholders": [TODO/빈 껍데기로 방치된 부분], "contradictions": [서로 모순되는 지시],
 "vague": [강제 불가능하게 모호한 지시], "score": 0-10}
각 배열 항목은 한 줄 한국어. 없으면 빈 배열. JSON만 출력.
--- CLAUDE.md ---
<본문>
--- rules ---
<본문들>
```

# UI

- Harness 팝오버 점수 섹션 아래 "LLM 진단" 행:
  - 미실행: [진단 실행 (토큰 사용)] 버튼
  - 실행 중: 스피너 "진단 중… (최대 60s)"
  - 완료: `품질 7/10 · 플레이스홀더 2 · 모순 0 · 모호 1` 요약 + 펼치면 항목 목록
  - 캐시된 결과엔 "이전 결과" 배지 + [다시 진단]
- 진단 결과는 Harness Score에 **반영하지 않음**(정적 점수와 분리 — LLM 출력은 참고 정보).

# 범위

**In:**
- `QualityScanner.swift`(신규): 입력 수집(캡 포함)·해시·프롬프트 조립·`claude -p` 실행·
  JSON 파싱·캐시 IO.
- `HarnessPopoverView`: LLM 진단 행(3상태 + 결과 펼침).
- `--quality <dir>` 헤드리스 검증 CLI.

**Out:**
- 자동 실행 일체 / Score 반영 / 수정 자동 적용(진단만) / 글로벌 CLAUDE.md 진단.

# 엣지케이스

| 케이스 | 처리 |
|--------|------|
| claude CLI 부재 | 버튼 비활성 + "Claude Code CLI 필요" |
| JSON 파싱 실패 | 원문 일부와 함께 오류 표시, 캐시 안 함 |
| CLAUDE.md 부재 | 버튼 비활성 + "진단할 CLAUDE.md 없음" |
| 60s 초과 | 프로세스 종료 + 타임아웃 오류 |
| 입력 4KB 초과 | 앞부분 캡 + "(일부만 진단)" 표시 |

# 변경 파일

| 파일 | 변경 |
|------|------|
| `QualityScanner.swift`(신규) | 수집·실행·파싱·캐시 |
| `HarnessPopoverView.swift` | 진단 행 |

# 검증

1. `swift build` 그린.
2. `--quality <이 repo>` 헤드리스: 실제 1회 실행 → JSON 파싱·요약 출력 확인(토큰 소비 1회 명시).
3. 같은 입력 재실행 → 캐시 히트(프로세스 미실행) 확인.
4. claude CLI 경로 부재 시뮬 → 명확한 오류.

# 구현 중 발견 (기록)
- 래퍼 JSON에 `is_error: true` + `result`에 사람용 메시지(미인증/권한) → **is_error를 먼저
  확인**해 그대로 표면화(안 그러면 "Not logged in"을 내부 JSON으로 파싱하려다 혼란 오류).
- 검증 상태: 래퍼 파싱·is_error 경로·타임아웃·바이너리 발견·캐시 왕복 **통과**. 단
  **이 개발 환경의 headless claude가 미인증**이라 happy-path(내부 JSON 파싱)는 실증 불가 —
  로그인된 실제 머신에서 동작. 파싱 로직은 단순(2층)이라 리뷰로 갈음.

# Next Action
- [x] Claude 리뷰어 패스 — NEEDS_FIX 5건 반영(바이너리 발견·--bare·재귀 완화·2층 파싱·뷰 밖 상태)
- [x] 사용자 승인 — 루프 사전 전체 승인(비용은 수동-1회-캐시 설계로 통제)
