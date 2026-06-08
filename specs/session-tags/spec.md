# Spec: 세션 태그 수동 선택

## 목표

드롭다운 세션 목록에서 각 세션에 태그를 수동으로 붙이고,
태그 기준으로 세션을 필터링할 수 있게 한다.

## 범위

### In

- 각 세션 행 오른쪽에 태그 인디케이터 버튼 (태그 없으면 `○`, 있으면 `●`)
- 버튼 클릭 → NSPopover: 기존 태그 토글 + `×`로 삭제 + 새 태그 직접 입력
- 세션당 태그는 0개 이상 (멀티태그 허용)
- 태그 저장: `~/.airuncat/tags.json` (`{ sessionId(UUID): [tag, ...] }`)
  - sessionId는 `~/.claude/projects/*/<uuid>.jsonl` 파일명 stem (UUID, 안정적)
- 전체 태그 풀: `~/.airuncat/tag-pool.json` (인메모리 캐시, 변경 시에만 저장)
- 드롭다운 상단에 태그 필터 바 (스크롤 영역 바깥 고정)
  - 버튼: `[All]` `[Untagged]` + 태그별 버튼, 단일 선택
  - `All`: 모든 세션 표시
  - `Untagged`: 태그 없는 세션만 표시
  - 태그 버튼: 해당 태그를 가진 세션만 표시
- 기본 태그 프리셋: `work`, `personal`, `urgent`

### Out

- 다중 태그 AND 조건 필터 (Phase 2)
- 태그별 그룹 헤더 구분 (Phase 2)
- 태그 색상 지정 (Phase 2)
- 태그 rename (Phase 2)

## UI / 동작

```
┌─────────────────────────────────┐
│ [All] [Untagged] [work] [urgent]│  ← 필터 바 (고정, 스크롤 바깥)
├─────────────────────────────────┤
│ airuncat-dev   (idle) ●         │  ← 태그 있음
│ my-blog        (live) ○         │  ← 태그 없음
└─────────────────────────────────┘

● 또는 ○ 클릭 시 NSPopover:
┌──────────────────────┐
│ [work ×] [urgent ×]  │  ← 선택된 태그 (× 로 제거)
│ ─────────────────── │
│ [ ] personal         │
│ ─────────────────── │
│ + [new tag___] Enter │
└──────────────────────┘
```

- 태그 인디케이터: `●` (태그 있음) / `○` (없음) — 너비 최소화
- Popover는 `NSPopover`를 버튼의 anchorView 기준으로 수동 제어
  - MenuBarExtra 내부 SwiftUI `popover` 수식어 미사용 (macOS 버전별 동작 불안정)
  - 팝오버 열려있는 동안 SessionStore 타이머 갱신은 데이터만 업데이트, 팝오버 UI에 영향 없음
- 새 태그 입력 후 Return → tag-pool에 추가 + 현재 세션 자동 선택
- 팝오버 닫힘 → 즉시 파일 저장
- 필터 선택 중 새 세션 등장: 태그 없으면 `All`/`Untagged` 외에서 숨김

## 데이터 소스

```json
// ~/.airuncat/tags.json
{
  "f47ac10b-58cc-4372-a567-0e02b2c3d479": ["work", "urgent"],
  "550e8400-e29b-41d4-a716-446655440000": ["personal"]
}

// ~/.airuncat/tag-pool.json
["work", "personal", "urgent", "my-custom-tag"]
```

- 인메모리 캐시 유지, 변경(태그 토글/추가/삭제) 시에만 디스크 저장
- 파일 없으면 프리셋(`work`, `personal`, `urgent`)으로 초기화

## 엣지케이스

- sessionId UUID는 JSONL 파일명 기반 → 세션 재시작/터미널 재오픈에도 불변
- 세션 만료 후 tags.json에 남은 고아 항목: 무해, 방치
- 팝오버 `×`로 태그 제거 시 해당 태그를 가진 세션이 0개면 tag-pool에서도 삭제
- 소문자 정규화 (입력 시 `trim().lowercased()`)
- 동일 태그 중복 입력 방지
- tag-pool 10개 초과: 팝오버 내부 스크롤

## 검증

1. `./build.sh` 그린
2. 메뉴바 → 세션 행에 `○`/`●` 표시 확인
3. `○` 클릭 → NSPopover 열림, 태그 토글 → `tags.json` 기록 확인
4. 새 태그 입력(Return) → tag-pool.json 갱신 확인
5. 선택 태그를 가진 세션이 0개 될 때 tag-pool에서 자동 제거 확인
6. 필터 바 `[Untagged]` → 태그 없는 세션만 표시
7. 필터 바 태그 버튼 → 해당 세션만 표시
8. 앱 재시작 후 태그/필터 상태 유지 확인

## 구현 파일

- `TagStore.swift` (신규) — `@MainActor ObservableObject`, 인메모리 캐시, 파일 I/O
- `MenuContentView.swift` — 필터 바(고정) + 세션 행 인디케이터 + NSPopover 제어
- `SessionStore.swift` — `TagStore` 인스턴스 보유 및 환경 주입
