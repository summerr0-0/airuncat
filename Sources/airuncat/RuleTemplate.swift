import Foundation

/// rule 템플릿 라이브러리 (Phase 17a) — ProjectHookRecipe와 동형 패턴.
/// 원칙: 일반론 금지, 위반이 판별 가능한 구체 제약만. 본문은 스펙 전문 그대로.
struct RuleTemplate: Identifiable {
    let id: String                     // 파일명(<id>.md)
    let title: String
    let types: [ProjectType]?          // nil = 공통(모든 타입)
    private let bodyText: String       // {BUILD_CMD} 치환 지원

    func applicable(to detected: [ProjectType]) -> Bool {
        guard let types else { return true }
        return detected.contains { types.contains($0) }
    }

    /// 감지 타입에 맞춰 본문 완성({BUILD_CMD} 치환).
    func body(for detected: [ProjectType]) -> String {
        guard bodyText.contains("{BUILD_CMD}") else { return bodyText }
        let cmd: String
        if detected.contains(.swift) { cmd = "swift build" }
        else if detected.contains(.node) { cmd = "npm run build" }
        else if detected.contains(.rust) { cmd = "cargo build" }
        else if detected.contains(.go) { cmd = "go build ./..." }
        else { cmd = "빌드 명령" }
        return bodyText.replacingOccurrences(of: "{BUILD_CMD}", with: cmd)
    }

    static let catalog: [RuleTemplate] = [
        RuleTemplate(
            id: "no-secrets", title: "시크릿 하드코딩 금지", types: nil,
            bodyText: """
            # no-secrets

            - API 키·토큰·비밀번호·인증서를 소스 코드/커밋에 직접 넣지 않는다.
            - 비밀값은 .env 또는 환경변수로 참조하고, .env는 .gitignore에 있어야 한다.
            - 예시/문서에도 실제 값 대신 placeholder(YOUR_API_KEY)를 쓴다.
            - 실수로 커밋된 비밀값은 즉시 무효화(rotate)한다.
            """),
        RuleTemplate(
            id: "no-destructive-git", title: "파괴적 git 금지", types: nil,
            bodyText: """
            # no-destructive-git

            - 공유 브랜치에 git push --force 금지. 원격 브랜치를 임의로 삭제하지 않는다.
            - 커밋 유실을 부르는 git reset --hard 대신 revert 커밋으로 되돌린다(히스토리 보존).
            - rebase는 로컬 미공유 브랜치에서만.
            """),
        RuleTemplate(
            id: "no-new-dependencies", title: "무승인 의존성 금지", types: nil,
            bodyText: """
            # no-new-dependencies

            - 새 외부 의존성(패키지) 추가는 사용자 승인 없이는 금지.
            - 기존 유틸과 같은 역할의 헬퍼를 새로 만들지 않는다 — 있으면 기존 것을 확장한다.
            - 표준 라이브러리로 충분한 일에 의존성을 붙이지 않는다.
            """),
        RuleTemplate(
            id: "build-must-pass", title: "빌드 그린 유지", types: [.swift, .node, .rust, .go],
            bodyText: """
            # build-must-pass

            - 편집을 마친 시점에 빌드({BUILD_CMD})가 통과해야 한다.
            - 빌드 실패 상태로 다음 작업이나 커밋으로 넘어가지 않는다.
            - (build-on-edit 훅이 없을 때의 규율 — 훅이 켜져 있으면 훅 출력이 곧 검증이다.)
            """),
        RuleTemplate(
            id: "test-with-changes", title: "변경엔 테스트 동반", types: [.node, .python, .rust, .go],
            bodyText: """
            # test-with-changes

            - 구현(src) 변경 커밋에는 대응하는 테스트 변경/추가를 동반한다.
            - 테스트를 붙일 수 없는 변경(설정·문서·순수 이동 리팩터)은 커밋 메시지에 사유 한 줄을 남긴다.
            - 기존 테스트를 삭제하거나 스킵 처리해서 통과시키지 않는다.
            """),
        RuleTemplate(
            id: "swift-clt-only", title: "CLT 빌드만", types: [.swift],
            bodyText: """
            # swift-clt-only

            - 빌드는 swift build만 사용한다. xcodebuild/.xcodeproj/.xcworkspace 의존 금지.
            - 에셋 카탈로그(.xcassets) 등 풀 Xcode 전용 기능에 의존하지 않는다.
            """),
    ]
}
