import Foundation

// MARK: - Models

/// Anthropic 공식 사용량 API(`/api/oauth/usage`) 응답의 요점.
/// utilization/resets_at = 서버가 계산한 실제 값(근사 아님).
struct UsageSnapshot: Equatable {
    let fiveHourPercent: Double
    let fiveHourResetsAt: Date?
    let weeklyPercent: Double?
    let weeklyResetsAt: Date?
}

enum UsageFetchError: Error, Equatable {
    case noToken        // Keychain에서 자격증명 못 읽음
    case expired        // 토큰 만료 → Claude Code 재사용 시 갱신됨
    case http(Int)      // 401 등
    case network        // 오프라인/타임아웃
    case parse          // 응답 파싱 실패

    var hint: String {
        switch self {
        case .noToken:  return "Claude 자격증명 없음"
        case .expired:  return "재인증 필요"
        case .http(401): return "재인증 필요"
        case .http(let c): return "API \(c)"
        case .network:  return "오프라인"
        case .parse:    return "응답 오류"
        }
    }
}

// MARK: - Client

/// Claude Code의 OAuth 토큰(macOS Keychain)으로 Anthropic 사용량 API를 호출한다.
/// claude-hud / oh-my-claudecode(usage-api.ts)와 같은 방식.
enum UsageAPIClient {

    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async -> Result<UsageSnapshot, UsageFetchError> {
        guard let cred = readCredentials() else { return .failure(.noToken) }
        if let exp = cred.expiresAtMs, Double(exp) < Date().timeIntervalSince1970 * 1000 {
            return .failure(.expired)
        }

        var req = URLRequest(url: usageURL, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Bearer \(cred.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure(.network) }
            guard http.statusCode == 200 else { return .failure(.http(http.statusCode)) }
            guard let snap = parse(data) else { return .failure(.parse) }
            return .success(snap)
        } catch {
            return .failure(.network)
        }
    }

    // MARK: - Credentials (Keychain)

    private struct Credentials { let accessToken: String; let expiresAtMs: Int? }

    /// `security find-generic-password -w -s "Claude Code-credentials"`로 JSON blob을 읽어
    /// `claudeAiOauth.accessToken` / `expiresAt`를 추출한다.
    private static func readCredentials() -> Credentials? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-w", "-s", keychainService]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let exp = oauth["expiresAt"] as? Int
        return Credentials(accessToken: token, expiresAtMs: exp)
    }

    // MARK: - Response parse

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static func parseDate(_ s: Any?) -> Date? {
        guard let str = s as? String else { return nil }
        return iso.date(from: str) ?? isoPlain.date(from: str)
    }

    private static func parse(_ data: Data) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let five = obj["five_hour"] as? [String: Any],
              let fivePct = (five["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let seven = obj["seven_day"] as? [String: Any]
        let weekPct = (seven?["utilization"] as? NSNumber)?.doubleValue
        return UsageSnapshot(
            fiveHourPercent: fivePct,
            fiveHourResetsAt: parseDate(five["resets_at"]),
            weeklyPercent: weekPct,
            weeklyResetsAt: parseDate(seven?["resets_at"])
        )
    }
}
