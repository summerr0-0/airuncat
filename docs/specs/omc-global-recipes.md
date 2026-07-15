# OMC 대응 글로벌 레시피 2종 — 전역 위험 명령 가드 · 완료 검증 넛지

## Goal

OMC(oh-my-claudecode) hooks.json 대조에서 나온 공백 중 **쓸 만한 것만** airuncat
글로벌 레시피로 추가한다 (사용자 지시: "쓸수 있는건 다 처리해줘", 2026-07-14).

## 채택/기각 판단

| OMC 훅 | 판단 | 이유 |
|--------|------|------|
| pre-tool-enforcer | ✅ `global-bash-guard` | 프로젝트 가드는 프로젝트별 설치 필요 — 전역판 가치 있음 |
| verify-deliverables | ✅ `completion-verifier` | "됐다"고 할 때 실제 검증 여부 확인 — 가장 가치 큼 |
| permission-handler | ❌ | 자동 승인은 위험, 자동 거부는 가드와 중복 |
| keyword-detector / skill-injector | ❌ | Claude Code 네이티브 스킬 매칭이 커버 |
| project-memory | ❌ | 네이티브 자동 메모리가 커버 |
| wiki | ❌ | 니치, 유지비 > 효용 |

## 설계

### global-bash-guard (PreToolUse, matcher: Bash)
공백 정규화 후 패턴 매칭 → `permissionDecision: deny`:
- `rm` + recursive + force + 대상이 루트/홈 자체 (`/`, `/*`, `~`, `$HOME`)
- main/master 강제 푸시 (`--force`·`-f`, `--force-with-lease`는 허용)
- `mkfs`, `dd`/리다이렉션/`tee` → `/dev/disk|rdisk|sd` (따옴표 감싼 경로 포함)
- `chmod -R 777 /`, `find / -delete`, 포크밤
**베스트에포트 트립와이어** — 우회 가능, 보안 경계 아님 (프로젝트 가드와 동일 철학).

### completion-verifier (Stop)
transcript tail 512KB에서 마지막 유저 턴 이후 이벤트를 수집:
- 코드 편집(Edit/Write/NotebookEdit, 문서 확장자 제외)이 있고,
- 마지막 편집 **이후** 검증성 Bash(swift build/test, npm test, pytest 등 힌트 목록)가 없으면
→ `decision: block` + 이유로 한 번 되물음.
가드레일: `stop_hook_active`면 무조건 통과(루프 방지), 유저 턴 경계를 못 찾으면
보수적 통과(agy 리뷰 #3), 세션당 2회 상한(`hook-state/sessions/<id>/verifier.json`).

## 검증 (헤드리스, 전부 통과)

- 가드 13 시나리오: 루트/홈 rm 변형 3, 정상 rm 2, 강제푸시 2, dd/tee/따옴표 3, find/-delete, swift build, tee 로그
- 검증 넛지 9 시나리오: 미검증 block, 검증 후 pass, 문서만 pass, stop_hook_active pass,
  2회 상한(1·2 block → 3 pass), 편집 후 미검증 block, 유저 경계 없음 pass
- 실전 오탐 사례: 가드가 리뷰어의 "rm -rf /" **언급 명령**까지 차단 — 트립와이어 특성으로 수용
  (거부 사유가 Claude에 전달되므로 우회 재작성 가능)

## 리뷰

agy(Antigravity) 교차리뷰 6건 중 2건 수용(#3 턴 경계, #6 tee·따옴표 우회),
4건 기각(transcript 스키마 오인, env 크기·파일핸들은 기존 패턴과 동일/무해, with-lease 혼용 플래그는 차단이 맞음).
