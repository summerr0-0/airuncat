# Clawde Development Workflow

모든 기능/Phase는 아래 8단계를 순서대로 거친다. 작성(authoring)과 리뷰(review)는
항상 분리하고, 같은 패스에서 self-approve 하지 않는다.

| # | 단계 | 하는 일 | 산출물 | 게이트 |
|---|------|--------|--------|--------|
| 1 | 상세 기획 | 기능/Phase 스펙 작성 | `docs/specs/<feature>.md` | - |
| 2 | Gemini 검토 | 스펙을 Gemini가 교차검토 | `.omc/artifacts/ask/*.md` | - |
| 3 | 승인 | 사용자가 스펙 검토·승인 | (사용자 OK) | **승인 전 개발 금지** |
| 4 | 개발 | 스펙대로 구현 | `Sources/*`, 빌드 그린 | `swift build` 통과 |
| 5 | 리뷰 | Claude가 diff 자체 코드리뷰 | 리뷰 노트 + 반영 | 지적사항 반영 |
| 6 | Gemini 리뷰 | diff를 Gemini가 교차검토 | `.omc/artifacts/ask/*.md` | 지적사항 반영 |
| 7 | 문서 완료 | CLAUDE.md / docs / 로드맵 갱신 | 갱신된 문서 | - |
| 8 | PR | 브랜치 푸시 + PR 생성 | PR | 1~7 완료 |

## 단계별 메모

1. **상세 기획** — `docs/specs/<feature>.md`에 목표, 범위(in/out), UI/동작, 데이터 소스,
   엣지케이스, 검증 방법을 적는다. 막연하면 `/specify`나 `/deep-interview`로 구체화.
2. **Gemini 검토** — `/gemini-review`로 스펙의 누락/모순/리스크를 받는다. Claude가 종합.
3. **승인** — 사용자가 스펙을 보고 OK. 여기서 막히면 1~2로 되돌아간다. 이 게이트 전엔 코드 작성 안 함.
4. **개발** — 스펙 범위만 구현. 빌드 훅(`swift build`)이 그린이어야 한다. UI 변경은 `/run-clawde`로 실제 확인, 고양이 변경은 `/render-cat`.
5. **리뷰** — Claude가 diff를 버그/엣지케이스/단순화 관점으로 리뷰하고 반영. (`/code-review` 사용 가능)
6. **Gemini 리뷰** — `/gemini-review`로 diff 교차검토. 작성자(Claude)와 다른 모델이 보게 해 맹점 제거.
7. **문서 완료** — 바뀐 동작을 CLAUDE.md / docs / Obsidian 로드맵에 반영. Next Action 갱신.
8. **PR** — `git`이 전제 (현재 미초기화 → `git init` + GitHub 레포 필요). PR 본문에 스펙·리뷰 요약 링크.

## 원칙
- 3단계(승인) 없이 4단계로 넘어가지 않는다 — 하드 게이트.
- 2·6단계 Gemini는 반드시 별도 패스. Claude가 자기 결과를 자기 패스에서 승인 금지.
- 한 번에 하나의 feature/Phase만 이 파이프라인을 탄다.
