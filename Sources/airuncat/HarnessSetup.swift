import Foundation

/// Phase 14: Harness Score의 ✗ 항목을 클릭 한 번으로 보완하는 자동 세팅.
/// 기존 생성기(RuleManager.create, HarnessManager.addPermission/addDisabledHookTemplate)를
/// 묶고, 비파괴(부재 시에만 생성)·비실행(hook은 비활성 템플릿) 원칙을 지킨다.
enum HarnessSetup {

    /// 공유 CLAUDE.md 시작 템플릿. ClaudeMdPopoverView도 이걸 호출(중복 제거).
    /// 토큰 ≥ 20을 충족해 생성 직후 prep-claudemd/설정 간결을 통과시키되, 본문은 사용자가 채울 가이드.
    static func claudeMdTemplate(projectName: String) -> String {
        """
        # \(projectName)

        ## 역할
        이 프로젝트가 무엇인지 한 줄로 적는다. (TODO)

        ## 구조
        주요 디렉토리와 파일의 역할을 적는다. (TODO)

        ## 규칙
        반복 지시·컨벤션을 적는다. 길어지면 .claude/rules/ 로 분리한다. (TODO)
        """
    }

    /// 프로젝트 루트 CLAUDE.md 생성 (부재 시에만). 반환: 에러 문자열 or nil.
    static func createClaudeMd(cwd: String) -> String? {
        let path = (cwd as NSString).appendingPathComponent("CLAUDE.md")
        guard !FileManager.default.fileExists(atPath: path) else {
            return "CLAUDE.md가 이미 존재합니다"
        }
        let name = (cwd as NSString).lastPathComponent
        do {
            try claudeMdTemplate(projectName: name)
                .write(toFile: path, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "CLAUDE.md 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 프로젝트 시작 rule 생성 (RuleManager 위임). 반환: 에러 문자열 or nil.
    static func createStarterRule(cwd: String) -> String? {
        RuleManager.create(name: "project-conventions", scope: .project, projectCwd: cwd)
    }

    /// 민감파일 deny 권한 일괄 추가. 이미 있는 패턴은 스킵. settings.json 부재도 처리.
    static func addSensitiveDenies(in info: HarnessInfo) -> HarnessInfo {
        let patterns = ["Read(./.env)", "Read(./.env.*)", "Read(./**/*.pem)", "Read(./secrets/**)"]
        return applyAll(patterns, in: info) { pattern, current in
            HarnessManager.addPermission(pattern: pattern, kind: .deny, in: current)
        }
    }

    /// Pre/PostToolUse 참고 hook을 비활성(_disabledHooks)으로 1회 추가.
    /// 명령은 주석 플레이스홀더(켜도 no-op) — 사용자가 채우고 토글로 켠다.
    static func addHookTemplates(in info: HarnessInfo) -> HarnessInfo {
        let templates: [(event: String, matcher: String, command: String)] = [
            ("PostToolUse", "Edit|Write", "# TODO: 편집 후 포맷터/빌드 실행 (예: swift build)"),
            ("PreToolUse",  "Edit|Write", "# TODO: 민감/빌드 산출물 편집 차단 (비제로 종료로 block)"),
        ]
        return applyAll(templates, in: info) { t, current in
            HarnessManager.addDisabledHookTemplate(
                event: t.event, matcher: t.matcher, command: t.command, in: current)
        }
    }

    // MARK: - Helper

    /// 항목들을 순차 적용하며 info를 체인. "이미 존재"는 정상(스킵)으로 보고 계속,
    /// 그 외 쓰기 실패면 직전까지 반영분을 유지한 채 에러를 담아 중단(부분 성공 정직 노출).
    private static func applyAll<T>(_ items: [T], in info: HarnessInfo,
                                    _ apply: (T, HarnessInfo) -> HarnessInfo) -> HarnessInfo {
        var current = info
        for item in items {
            let updated = apply(item, current)
            if let err = updated.writeError, !err.contains(HarnessManager.alreadyExistsMarker) {
                current.writeError = err
                return current
            }
            current = updated
            current.writeError = nil
        }
        return current
    }
}
