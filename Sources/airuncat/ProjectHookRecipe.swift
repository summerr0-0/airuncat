import Foundation

// MARK: - Project type detection

/// 프로젝트 타입 — 레시피 명령을 타입에 맞게 채우기 위한 감지 (Phase 15).
enum ProjectType: String, CaseIterable {
    case swift, node, python, rust, go, generic

    var label: String {
        switch self {
        case .swift: return "Swift"; case .node: return "Node"
        case .python: return "Python"; case .rust: return "Rust"
        case .go: return "Go"; case .generic: return "일반"
        }
    }
}

enum ProjectTypeDetector {
    /// cwd의 마커 파일로 타입 감지(모노레포 대비 복수 반환, 없으면 [.generic]).
    static func detect(cwd: String) -> [ProjectType] {
        let fm = FileManager.default
        func has(_ f: String) -> Bool { fm.fileExists(atPath: (cwd as NSString).appendingPathComponent(f)) }
        var types: [ProjectType] = []
        if has("Package.swift") { types.append(.swift) }
        if has("package.json") { types.append(.node) }
        if has("pyproject.toml") || has("requirements.txt") || has("setup.py") { types.append(.python) }
        if has("Cargo.toml") { types.append(.rust) }
        if has("go.mod") { types.append(.go) }
        return types.isEmpty ? [.generic] : types
    }
}

// MARK: - Recipe catalog

/// 프로젝트 훅 레시피 (Phase 15): 프로젝트 settings.json에 **비활성**으로 추가되는
/// 큐레이팅 명령. 글로벌 스크립트 레시피(HookRecipe)와 별개 계열 — 이름 주의.
struct ProjectHookRecipe: Identifiable {
    enum Category: String {
        case build = "빌드", format = "포맷", lint = "린트", guardRule = "차단"
    }

    let id: String
    let title: String
    let description: String
    let category: Category
    let event: String          // "PostToolUse" | "PreToolUse"
    let matcher: String        // "Edit|Write" | "Bash"
    let commands: [ProjectType: String]   // 타입별 명령(없으면 해당 타입 미지원)

    /// 감지된 타입들 중 첫 매칭 명령, 없으면 generic, 그것도 없으면 nil(미지원).
    func command(for types: [ProjectType]) -> String? {
        for t in types where commands[t] != nil { return commands[t] }
        return commands[.generic]
    }

    // MARK: 공용 스니펫

    /// 훅 stdin JSON에서 tool_input 필드를 추출하는 셸 전문(단일 인용 안전).
    /// 주의: 훅 입력은 stdin으로 온다 — $TOOL_INPUT 같은 env는 인터페이스가 아님.
    private static func extract(_ field: String) -> String {
        "INPUT=$(cat); V=$(printf '%s' \"$INPUT\" | /usr/bin/python3 -c 'import json,sys; print((json.load(sys.stdin).get(\"tool_input\") or {}).get(\"\(field)\") or \"\")' 2>/dev/null)"
    }

    /// PreToolUse 차단 응답(JSON, exit 0) — 공식 프로토콜(permissionDecision: deny).
    private static func deny(_ reason: String) -> String {
        "printf '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"\(reason): %s\"}}' \"$V\""
    }

    // MARK: 카탈로그

    static let catalog: [ProjectHookRecipe] = [
        ProjectHookRecipe(
            id: "build-on-edit",
            title: "편집 후 빌드",
            description: "소스 편집 시 빌드를 돌려 오류를 즉시 노출",
            category: .build,
            event: "PostToolUse", matcher: "Edit|Write",
            commands: [
                .swift: "\(extract("file_path")); if [[ \"$V\" == *.swift ]]; then swift build 2>&1 | tail -20; fi",
                .node:  "\(extract("file_path")); if [[ \"$V\" == *.ts || \"$V\" == *.tsx || \"$V\" == *.js ]]; then npm run build 2>&1 | tail -20; fi",
                .rust:  "\(extract("file_path")); if [[ \"$V\" == *.rs ]]; then cargo build 2>&1 | tail -20; fi",
                .go:    "\(extract("file_path")); if [[ \"$V\" == *.go ]]; then go build ./... 2>&1 | tail -20; fi",
            ]
        ),
        ProjectHookRecipe(
            id: "format-on-edit",
            title: "저장 시 포맷",
            description: "편집된 파일을 포맷터로 자동 정리",
            category: .format,
            event: "PostToolUse", matcher: "Edit|Write",
            commands: [
                .swift:  "\(extract("file_path")); if [[ \"$V\" == *.swift ]]; then swift format -i \"$V\" 2>/dev/null; fi",
                .node:   "\(extract("file_path")); if [[ -n \"$V\" ]]; then npx prettier --write \"$V\" 2>/dev/null; fi",
                .python: "\(extract("file_path")); if [[ \"$V\" == *.py ]]; then black \"$V\" 2>/dev/null; fi",
                .rust:   "cargo fmt 2>/dev/null",
                .go:     "\(extract("file_path")); if [[ \"$V\" == *.go ]]; then gofmt -w \"$V\" 2>/dev/null; fi",
            ]
        ),
        ProjectHookRecipe(
            id: "lint-on-edit",
            title: "편집 후 린트",
            description: "편집된 파일에 린터를 돌려 품질 문제를 조기 발견",
            category: .lint,
            event: "PostToolUse", matcher: "Edit|Write",
            commands: [
                .swift:  "\(extract("file_path")); if [[ \"$V\" == *.swift ]]; then swiftlint lint \"$V\" 2>/dev/null | tail -10; fi",
                .node:   "\(extract("file_path")); if [[ -n \"$V\" ]]; then npx eslint \"$V\" 2>/dev/null | tail -10; fi",
                .python: "\(extract("file_path")); if [[ \"$V\" == *.py ]]; then ruff check \"$V\" 2>/dev/null | tail -10; fi",
            ]
        ),
        ProjectHookRecipe(
            id: "block-sensitive",
            title: "민감파일 편집 차단",
            description: ".env·시크릿·키 파일 편집을 차단 (permissionDecision: deny)",
            category: .guardRule,
            event: "PreToolUse", matcher: "Edit|Write",
            commands: [
                .generic: "\(extract("file_path")); case \"$V\" in *.env|*.env.*|*secret*|*credential*|*id_rsa*|*.pem) \(deny("민감 파일 차단"));; esac"
            ]
        ),
        ProjectHookRecipe(
            id: "block-dangerous-bash",
            title: "위험 bash 차단",
            description: "rm -rf / 등 파괴적 명령을 차단 (permissionDecision: deny)",
            category: .guardRule,
            event: "PreToolUse", matcher: "Bash",
            commands: [
                .generic: "\(extract("command")); case \"$V\" in *'rm -rf /'*|*'rm -rf ~'*|*'rm -rf $HOME'*|*'mkfs'*|*'> /dev/sd'*|*'chmod -R 777 /'*) \(deny("위험 명령 차단"));; esac"
            ]
        ),
    ]
}
