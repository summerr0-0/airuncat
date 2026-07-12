import SwiftUI

// MARK: - Phase 16: 하네스 세팅 마법사

/// 낮은 등급(F~C) 프로젝트를 한 흐름으로 끌어올리는 단계식 마법사.
/// 진단 → 제안(미리보기) → 사용자 확인 → 적용을 단계마다 반복 — 자동으로 켜지는 것 없음.
/// 훅 켜기는 명령 전문을 본 단계에서 [추가+켜기]를 명시 선택했을 때만(리뷰어 승인 산술: 켜면 B).
struct HarnessWizardView: View {
    @Binding var info: HarnessInfo
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        case claudeMd = 0, rules, denies, hooks, summary
        var title: String {
            switch self {
            case .claudeMd: return "CLAUDE.md"
            case .rules:    return "rules"
            case .denies:   return "permissions"
            case .hooks:    return "hook 레시피"
            case .summary:  return "요약"
            }
        }
    }

    @State private var step: Step = .claudeMd
    @State private var appliedCount = 0
    @State private var skippedCount = 0
    @State private var stepError: String? = nil
    @State private var startGrade: HarnessGrade? = nil
    @State private var startPercent = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if step != .summary {
                stepBody
                controls
            } else {
                summaryBody
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            startGrade = info.score.grade
            startPercent = info.score.percent
            advancePastSatisfied()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("세팅 마법사")
                .font(.system(size: 10, weight: .semibold))
            if step != .summary {
                Text("(\(step.rawValue + 1)/4)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i <= step.rawValue ? AiruncatDesign.aiColor(.claude) : Color.secondary.opacity(0.25))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            Spacer()
            Button("닫기") { onDone() }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 단계 상태 판정 (3상태: 충족/막힘/실행가능)

    private enum StepStatus { case satisfied(String), blocked(String), actionable }

    private func status(of s: Step) -> StepStatus {
        switch s {
        case .claudeMd:
            if info.claudeMdWordCount >= 20 { return .satisfied("CLAUDE.md 충족 (\(info.claudeMdWordCount) words)") }
            if info.claudeMdWordCount > 0 {
                return .blocked("CLAUDE.md가 존재하나 짧음(\(info.claudeMdWordCount) words) — 덮어쓰지 않음, 수동 보강 필요")
            }
            return .actionable
        case .rules:
            return info.projectRuleCount >= 1
                ? .satisfied("프로젝트 rule \(info.projectRuleCount)개") : .actionable
        case .denies:
            let denies = info.permissions.filter { $0.kind == .deny }.count
            return denies >= 1 ? .satisfied("deny \(denies)개") : .actionable
        case .hooks:
            let post = info.hooks.contains { $0.enabled && $0.event == "PostToolUse" }
            let pre  = info.hooks.contains { $0.enabled && $0.event == "PreToolUse" }
            return (post && pre) ? .satisfied("활성 Pre/PostToolUse hook 존재") : .actionable
        case .summary:
            return .actionable
        }
    }

    /// 현재 단계가 충족/막힘이면 자동으로 다음 단계로(스킵 카운트).
    private func advancePastSatisfied() {
        while step != .summary {
            if case .actionable = status(of: step) { return }
            skippedCount += 1
            step = Step(rawValue: step.rawValue + 1) ?? .summary
        }
    }

    private func advance() {
        stepError = nil
        step = Step(rawValue: step.rawValue + 1) ?? .summary
        advancePastSatisfied()
    }

    // MARK: - 단계 본문

    @ViewBuilder
    private var stepBody: some View {
        switch status(of: step) {
        case .satisfied(let msg), .blocked(let msg):
            Text(msg).font(.system(size: 9)).foregroundColor(.secondary)
        case .actionable:
            VStack(alignment: .leading, spacing: 4) {
                Text(stepDescription)
                    .font(.system(size: 10, weight: .medium))
                preview(stepPreview)
                if let err = stepError {
                    Text(err).font(.system(size: 9)).foregroundColor(.red)
                }
                if step == .hooks {
                    Text("[추가+켜기] = 위 명령을 검토했고 즉시 활성 / [추가만] = 비활성으로 두고 나중에 토글")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
    }

    private var stepDescription: String {
        switch step {
        case .claudeMd: return "CLAUDE.md가 없습니다 — 시작 템플릿을 생성합니다"
        case .rules:    return "프로젝트 규칙이 없습니다 — 시작 rule(.claude/rules/)을 생성합니다"
        case .denies:   return "deny 권한이 없습니다 — 민감파일 읽기 차단을 추가합니다"
        case .hooks:    return "검증 훅이 없습니다 — 레시피 2개(빌드·민감파일 차단)를 추가합니다"
        case .summary:  return ""
        }
    }

    private var stepPreview: String {
        switch step {
        case .claudeMd:
            return HarnessSetup.claudeMdTemplate(
                projectName: (info.projectPath as NSString).lastPathComponent)
        case .rules:
            return "# project-conventions\n\n여기에 AI에게 강제할 제약이나 동작을 기술한다."
        case .denies:
            return "deny:\n  Read(./.env)\n  Read(./.env.*)\n  Read(./**/*.pem)\n  Read(./secrets/**)"
        case .hooks:
            let types = ProjectTypeDetector.detect(cwd: info.projectPath)
            let build = ProjectHookRecipe.catalog.first { $0.id == "build-on-edit" }
            let guardR = ProjectHookRecipe.catalog.first { $0.id == "block-sensitive" }
            let buildCmd = build?.command(for: types) ?? "(이 타입엔 빌드 레시피 없음)"
            let guardCmd = guardR?.command(for: types) ?? ""
            return "1. 편집 후 빌드 (PostToolUse)\n\(buildCmd)\n\n2. 민감파일 차단 (PreToolUse)\n\(guardCmd)"
        case .summary:
            return ""
        }
    }

    private func preview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .frame(maxHeight: 110)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - 컨트롤

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("건너뛰기") { skippedCount += 1; advance() }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            if case .actionable = status(of: step) {
                if step == .hooks {
                    Button("추가만") { applyHooks(enable: false) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.accentColor)
                    Button("추가+켜기") { applyHooks(enable: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AiruncatDesign.aiColor(.claude))
                } else {
                    Button("적용") { applyCurrent() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AiruncatDesign.aiColor(.claude))
                }
            } else {
                Button("다음") { advance() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - 적용 (반환 이질성 어댑터: String? / HarnessInfo.writeError, "이미 존재"=성공-스킵)

    private func applyCurrent() {
        switch step {
        case .claudeMd:
            finish(errorString: HarnessSetup.createClaudeMd(cwd: info.projectPath))
        case .rules:
            finish(errorString: HarnessSetup.createStarterRule(cwd: info.projectPath))
        case .denies:
            let result = HarnessSetup.addSensitiveDenies(in: info)
            finish(errorString: normalize(result.writeError), updated: result)
        case .hooks, .summary:
            break
        }
    }

    /// 레시피 2개(build-on-edit + block-sensitive) 추가, enable이면 검토-완료로 보고 즉시 토글.
    private func applyHooks(enable: Bool) {
        let types = ProjectTypeDetector.detect(cwd: info.projectPath)
        var current = info
        var firstError: String? = nil

        for id in ["build-on-edit", "block-sensitive"] {
            guard let recipe = ProjectHookRecipe.catalog.first(where: { $0.id == id }),
                  let command = recipe.command(for: types) else { continue }
            let result = HarnessManager.addDisabledHookTemplate(
                event: recipe.event, matcher: recipe.matcher, command: command, in: current)
            if let err = normalize(result.writeError) { firstError = firstError ?? err; continue }
            current = result
            if enable {
                let hookId = HarnessScanner.hookHash(event: recipe.event, matcher: recipe.matcher, command: command)
                if let entry = current.hooks.first(where: { $0.id == hookId && !$0.enabled }) {
                    let toggled = HarnessManager.toggle(hook: entry, in: current)
                    if normalize(toggled.writeError) == nil { current = toggled }
                }
            }
        }
        finish(errorString: firstError, updated: current)
    }

    /// "이미 존재"는 성공-스킵(HarnessSetup.applyAll 관례).
    private func normalize(_ err: String?) -> String? {
        guard let err, !err.isEmpty else { return nil }
        return err == HarnessManager.alreadyExistsMarker ? nil : err
    }

    private func finish(errorString: String?, updated: HarnessInfo? = nil) {
        if let updated { info = updated }
        // 파일 생성형 단계(CLAUDE.md/rule)는 rescan으로 반영.
        if let rescanned = HarnessScanner.scan(cwd: info.projectPath) { info = rescanned }
        if let errorString {
            stepError = errorString   // 인라인 오류 — 재시도/건너뛰기 가능
        } else {
            appliedCount += 1
            advance()
        }
    }

    // MARK: - 요약

    private var summaryBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            let score = info.score
            HStack(spacing: 6) {
                Text("적용 \(appliedCount) · 건너뜀 \(skippedCount)")
                    .font(.system(size: 10))
                Spacer()
            }
            HStack(spacing: 6) {
                Text("등급")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(startGrade?.rawValue ?? "?")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text("(\(startPercent)%)").font(.system(size: 9)).foregroundColor(.secondary)
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.secondary)
                Text(score.grade.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AiruncatDesign.aiColor(.claude))
                Text("(\(score.percent)%)").font(.system(size: 9)).foregroundColor(.secondary)
            }
            Button("완료") { onDone() }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AiruncatDesign.aiColor(.claude))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
