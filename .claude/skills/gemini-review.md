# /gemini-review

Gemini CLI로 2차 교차검증. Claude가 만든 기획서/코드 diff를 Gemini가 독립적으로 검토하고
Claude가 양쪽 의견을 종합한다. 워크플로우(`docs/workflow.md`)의 2단계(스펙)와 6단계(diff)에서 사용.

작성(authoring)과 리뷰(review)를 다른 모델로 분리해 맹점을 줄이는 것이 목적.

## When
- 스펙(`docs/specs/<feature>.md`) 작성 직후 (2단계)
- 구현 완료 후 PR 직전 (6단계)

## How
통로는 `omc ask gemini` (결과는 `.omc/artifacts/ask/`에 저장). 없으면 `gemini -p`로 대체.

### 1. 스펙 검증 (2단계)
```bash
omc ask gemini -p "다음 기획서를 시니어 리뷰어 관점에서 검토해줘.
누락된 요구사항, 모순, 숨은 리스크만 bullet로. 동의하는 부분은 생략.
맥락: Swift/SwiftUI 메뉴바 앱(airuncat), CLT 빌드.

$(cat docs/specs/<feature>.md)"
```

### 2. 코드 diff 검증 (6단계)
```bash
omc ask gemini -p "다음 Swift 변경을 코드리뷰해줘.
버그, 미처리 엣지케이스, 메모리/동시성, 불필요한 복잡성 관점에서만 지적:

$(git diff)"
```
git 초기화 전이면 `$(git diff)` 대신 변경된 파일 내용을 직접 붙인다.

## Output
Gemini 지적 → Claude가 각 항목을 수용/반박 정리 → 코드·스펙에 반영.
self-approve 금지: Claude가 자기 작업을 같은 패스에서 통과시키지 않는다.
