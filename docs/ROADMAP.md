# airuncat Roadmap

메뉴바에 사는 작은 고양이가 병렬로 도는 모든 AI 작업(Claude Code + Gemini CLI)을 한눈에
관제하고, 클릭하면 그 세션으로 이동하며, 프롬프트/스킬을 한 곳에서 관리하는 통합 도구.

- 컨셉: AI가 바쁠수록 고양이가 빨리 뛰고, 다 쉬면 앉아서 존다 (RunCat 영감)

## 현재 상태 (v0.1)

- Swift / SwiftUI MenuBarExtra 앱, Command Line Tools만으로 빌드 (`build.sh`)
- 세션 모니터: `~/.claude/projects/*/*.jsonl` 파싱 -> 제목/프로젝트/지금 하는 일/경과시간
- 애니메이션 고양이: 활성 세션 수에 따라 질주 속도 변화, 유휴 시 수면
- 클릭 -> 세션 이동: iTerm2 탭 포커스 (cwd 매칭), 없으면 새 탭에서 `claude -r`
  - 메커니즘 검증 완료. 남은 것: iTerm 자동화 권한 1회 허용 후 최종 클릭 확인
- 하네스 일습 완비 (CLAUDE.md, AGENTS.md, rules, skills, settings.json, docs)

## 핵심 기둥 (Pillars)

1. Session Monitor — 병렬 AI 작업 실시간 관제 (Claude + Gemini)
2. Skills Manager — `SKILL_*.md` <-> `~/.claude/commands`, `~/.gemini/commands` 링크 관리, 중복/고아 탐지, on/off
3. Prompt Library — 재사용 프롬프트 저장/분류/빠른 삽입
4. Unified Control — Claude / Gemini 양쪽 통합 뷰 및 동기화

## 개발 워크플로우

상세 기획 -> Gemini 검토 -> 승인 -> 개발 -> 리뷰 -> Gemini 리뷰 -> 문서 완료 -> PR
(상세: `docs/workflow.md`. 작성/리뷰 분리, self-approve 금지, 승인 전 개발 금지.)

## Phases

### Phase 0 — Session Monitor MVP [완료]
- [x] 고양이 렌더러 (벡터, 질주/수면, 템플릿 이미지)
- [x] JSONL 세션 스캐너 + mtime 캐시
- [x] 메뉴바 드롭다운 세션 목록 UI
- [x] `.app` 번들 빌드 스크립트 + 자체 서명 인증서(권한 영속)

### Phase 1 — 세션 이동 / 모니터 고도화
- [x] 클릭 -> iTerm2 탭 포커스 (cwd 매칭) + 없으면 새 탭 resume
- [ ] 세션이 끊어져도(종료돼도) 목록에서 안 사라지는 문제 수정 — 실제 살아있는 세션만 표시/active 처리, 종료된 건 제거하거나 명확히 구분
- [ ] iTerm 자동화 권한 허용 후 최종 동작 확인
- [ ] 로그인 자동 시작 (LaunchAgent)
- [ ] Gemini CLI 세션 소스 연동 (`~/.gemini/tmp/<hash>/chats/*.jsonl`)
- [ ] 멈춤/완료 알림, 고양이 미세 튜닝
- [ ] 세션별 커스텀 이름 붙이기 (사용자 직접 편집)
- [ ] 세션 태그 수동 선택 (사용자가 직접 태그 할당/관리)

### Phase 2 — Skills Manager
- [ ] `06_AI_Config/SKILL_*.md` 스캔 + claude/gemini 링크 상태 매핑
- [ ] 깨진 링크/중복/고아 탐지, on/off 토글
- [ ] 새 스킬 생성 시 양쪽 자동 링크

### Phase 3 — Prompt Library
- [ ] 저장소 설계(md frontmatter), 카테고리/태그/검색, 빠른 삽입

### Phase 4 — Claude / Gemini 통합
- [ ] 통합 세션 타임라인, 스킬 동기화 상태판, 사용량 집계

## Next Action
- [ ] iTerm2에 "airuncat이 제어" 자동화 권한 1회 허용 -> 클릭 시 탭 포커스 최종 확인
- [ ] 앞으로 AI 세션을 iTerm2에서 운용 시작 (Warp 대신)
- [ ] `git init` + GitHub 레포 `airuncat` 연결 (`github.com/summerr0-0/airuncat`) (PR 단계 전제)
- [ ] Phase 2(스킬 매니저) "상세 기획"부터 워크플로우 1단계로 시작

## 주요 결정 / 기술 메모
- 형태: macOS 메뉴바 앱 (SwiftUI MenuBarExtra, `LSUIElement`)
- 빌드: Swift 6.3 + SwiftPM + CLT (풀 Xcode 불필요)
- 고양이: 벡터 드로잉 + 템플릿 이미지 (다크/라이트 자동)
- 데이터: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, mtime로 활성 판정
- 세션 이동: Warp는 AppleScript 미지원 -> 탭 포커스 불가 -> iTerm2로 전환
- 권한 영속: ad-hoc 서명은 재빌드마다 TCC 권한이 풀림 -> 자체 서명 인증서 `airuncat Self-Signed`로 사인
- 참고: ai-monitor(hyunho058)는 모니터링 전용, Gemini 로그 경로만 차용
