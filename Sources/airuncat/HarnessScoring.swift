import SwiftUI

// MARK: - Grade

/// Harness 성숙도 등급. 전체 점수(축 ratio 평균)에서 도출.
enum HarnessGrade: String {
    case a = "A", b = "B", c = "C", d = "D", f = "F"

    static func from(ratio: Double) -> HarnessGrade {
        switch ratio {
        case 0.85...:     return .a
        case 0.65..<0.85: return .b
        case 0.45..<0.65: return .c
        case 0.25..<0.45: return .d
        default:          return .f
        }
    }

    var color: Color {
        switch self {
        case .a: return .green
        case .b: return Color(red: 0.4, green: 0.8, blue: 0.2)
        case .c: return .yellow
        case .d: return .orange
        case .f: return .red
        }
    }

    /// 배지 배경 대비용 글자색 — 노랑은 흰 글씨가 안 보여 검정으로.
    var badgeTextColor: Color { self == .c ? .black : .white }
}

// MARK: - Models

struct ScoreItem: Identifiable {
    let id: String
    let label: String
    let passed: Bool
    let detail: String?     // "312 words", "rules 4" 등 (없으면 nil)
}

struct AxisResult: Identifiable {
    let id: String          // 축 이름 = 표시 제목
    let items: [ScoreItem]  // 채점 항목 (정적 판정 가능)
    let deferredCount: Int  // 심층 분석 필요 항목 수 (표시만)
    let showsMaturity: Bool // 단일 항목 축은 L 표기 생략

    var title: String { id }
    var pass: Int { items.filter(\.passed).count }
    var total: Int { items.count }
    var ratio: Double { total == 0 ? 0 : Double(pass) / Double(total) }

    /// L1/L2/L3 성숙도 (2항목 이상 축만).
    var maturity: String {
        guard showsMaturity else { return "" }
        switch ratio {
        case 0.65...:     return "L3"   // 3항목 중 2개(0.667) 이상
        case 0.34..<0.65: return "L2"
        case let r where r > 0: return "L1"
        default:          return "—"
        }
    }
}

struct HarnessScore {
    let axes: [AxisResult]

    /// 축 동등가중 — 각 축 ratio의 평균.
    var ratio: Double {
        axes.isEmpty ? 0 : axes.map(\.ratio).reduce(0, +) / Double(axes.count)
    }
    var grade: HarnessGrade { .from(ratio: ratio) }
    var percent: Int { Int((ratio * 100).rounded()) }
}

// MARK: - Scoring

/// 프로젝트-로컬 정적 신호만으로 5축 성숙도를 평가한다.
/// 전역 신호(전역 rule/MCP/orphan)와 행동 항목은 점수에서 제외.
enum HarnessScoring {
    static func evaluate(_ info: HarnessInfo) -> HarnessScore {
        let wc = info.claudeMdWordCount
        let projectRules = info.projectRuleCount
        let denyCount = info.permissions.filter { $0.kind == .deny }.count
        let hasDeny = denyCount > 0
        let postHook = info.hooks.contains { $0.enabled && $0.event == "PostToolUse" }
        let preHook  = info.hooks.contains { $0.enabled && $0.event == "PreToolUse" }
        let hasAutomation = info.projectSkillCount >= 1 || info.enabledHookCount >= 1

        // 축 1 — 준비 (Scaffolding)
        let prep = AxisResult(
            id: "준비",
            items: [
                ScoreItem(id: "prep-claudemd", label: "CLAUDE.md 존재",
                          passed: wc >= 20, detail: wc > 0 ? "\(wc) words" : nil),
                ScoreItem(id: "prep-rules", label: "프로젝트 규칙 분리",
                          passed: projectRules >= 1, detail: projectRules > 0 ? "rules \(projectRules)" : nil),
                ScoreItem(id: "prep-deny", label: "행동범위 제한",
                          passed: hasDeny, detail: hasDeny ? "deny \(denyCount)" : nil),
            ],
            deferredCount: 0, showsMaturity: true
        )

        // 축 2 — 맥락 (Context)
        let context = AxisResult(
            id: "맥락",
            items: [
                ScoreItem(id: "ctx-concise", label: "설정 간결",
                          passed: wc >= 20 && wc <= 1500, detail: wc > 1500 ? "\(wc) words (과다)" : nil),
                ScoreItem(id: "ctx-imports", label: "점진적 노출",
                          passed: info.claudeMdHasImports, detail: info.claudeMdHasImports ? "@import" : "@import 없음"),
                ScoreItem(id: "ctx-rules", label: "규칙으로 맥락 분리",
                          passed: projectRules >= 1, detail: nil),
            ],
            deferredCount: 0, showsMaturity: true
        )

        // 축 3 — 실행 (Orchestration) · 단일 항목
        let exec = AxisResult(
            id: "실행",
            items: [
                ScoreItem(id: "exec-skill", label: "커스텀 자동화",
                          passed: info.projectSkillCount >= 1,
                          detail: info.projectSkillCount > 0 ? "skill \(info.projectSkillCount)" : nil),
            ],
            deferredCount: 6, showsMaturity: false
        )

        // 축 4 — 검증 (Verification)
        let verify = AxisResult(
            id: "검증",
            items: [
                ScoreItem(id: "ver-post", label: "포맷터/린터/빌드",
                          passed: postHook, detail: postHook ? "PostToolUse" : nil),
                ScoreItem(id: "ver-pre", label: "위험 작업 차단",
                          passed: preHook, detail: preHook ? "PreToolUse" : nil),
            ],
            deferredCount: 4, showsMaturity: true
        )

        // 축 5 — 개선 (Compounding)
        let improve = AxisResult(
            id: "개선",
            items: [
                ScoreItem(id: "imp-auto", label: "반복 작업 자동화",
                          passed: hasAutomation, detail: nil),
                ScoreItem(id: "imp-clean", label: "정리됨",
                          passed: !info.hasDisabledHook, detail: info.hasDisabledHook ? "비활성 hook" : nil),
            ],
            deferredCount: 3, showsMaturity: true
        )

        return HarnessScore(axes: [prep, context, exec, verify, improve])
    }
}
