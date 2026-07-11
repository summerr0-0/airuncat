import SwiftUI

/// airuncat 디자인 토큰. 색 정체성을 한곳에 모아 여러 뷰가 같은 언어를 쓰게 한다.
/// (지금 실제로 쓰이는 것만 둔다 — 미사용 토큰 추가 금지)
enum AiruncatDesign {

    // MARK: - AI 종류 색 (Claude vs Gemini 즉시 구분)

    static func aiColor(_ kind: AIKind) -> Color {
        switch kind {
        case .claude: return Color(red: 0.55, green: 0.40, blue: 0.95)  // 보라
        case .gemini: return Color(red: 0.20, green: 0.65, blue: 0.70)  // 청록
        }
    }

    // MARK: - 통합 상태 색/라벨

    static func statusColor(_ s: SessionDisplayStatus) -> Color {
        switch s {
        case .waiting: return .orange                      // 응답 대기 — 가장 눈에 띄게
        case .working: return .green
        case .idle:    return Color.secondary
        case .resting: return Color.secondary.opacity(0.4)
        }
    }

    static func statusLabel(_ s: SessionDisplayStatus) -> String {
        switch s {
        case .waiting: return "응답 대기"
        case .working: return "working"
        case .idle:    return "idle"
        case .resting: return "resting"
        }
    }

    // MARK: - Memory 타입 색 (Memory 팝오버 타입 그룹)

    static func memoryTypeColor(_ type: MemoryType) -> Color {
        switch type {
        case .user:      return .blue
        case .feedback:  return .orange
        case .project:   return .green
        case .reference: return .purple
        case .unknown:   return .secondary
        }
    }
}
