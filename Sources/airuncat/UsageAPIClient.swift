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
        guard var cred = readCredentials() else { return .failure(.noToken) }
        if isExpired(cred) {
            // lazy 리프레시(D2): 만료 시에만. 실패하면 기존과 동일하게 "재인증 필요"로 강등.
            guard let refreshed = await refreshCredentials(expired: cred) else {
                return .failure(.expired)
            }
            cred = refreshed
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

    private struct Credentials {
        let accessToken: String
        let expiresAtMs: Int?
        let refreshToken: String?
        let rawObject: [String: Any]   // claudeAiOauth 래퍼 보존 병합용(C2)
    }

    private static func isExpired(_ cred: Credentials) -> Bool {
        guard let exp = cred.expiresAtMs else { return false }
        return Double(exp) < Date().timeIntervalSince1970 * 1000
    }

    /// `security find-generic-password -w -s "Claude Code-credentials"`로 JSON blob을 읽어
    /// `claudeAiOauth.accessToken` / `expiresAt` / `refreshToken`을 추출한다.
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
        return Credentials(
            accessToken: token,
            expiresAtMs: oauth["expiresAt"] as? Int,
            refreshToken: oauth["refreshToken"] as? String,
            rawObject: obj
        )
    }

    // MARK: - Token refresh (R1, D2)

    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code 공개 client_id (OMC usage-api.ts와 동일).
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// 만료 토큰을 리프레시한다. 레이스 방어(D2):
    /// (1) 직전 재독 — Claude Code가 이미 갱신했으면 그 토큰 채택, 리프레시 중단.
    /// (2) 재기록 전 재독-비교 — 저장된 refreshToken이 바뀌었으면 내 결과 폐기.
    /// 최악의 경우도 nil 반환 → 기존 "재인증 필요" 표시와 동일(수용 위험).
    private static func refreshCredentials(expired: Credentials) async -> Credentials? {
        // (1) 리프레시 직전 재독: 그 사이 갱신됐으면 그대로 사용.
        if let fresh = readCredentials(), !isExpired(fresh) { return fresh }
        guard let rt = expired.refreshToken, !rt.isEmpty else { return nil }

        var req = URLRequest(url: refreshURL, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: rt),
            URLQueryItem(name: "client_id", value: oauthClientID),
        ]
        req.httpBody = (comps.percentEncodedQuery ?? "").data(using: .utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = obj["access_token"] as? String, !newAccess.isEmpty else { return nil }

        let newRefresh = (obj["refresh_token"] as? String) ?? rt   // 없으면 기존 유지
        let expiresAtMs: Int
        if let expIn = (obj["expires_in"] as? NSNumber)?.doubleValue {
            expiresAtMs = Int(Date().timeIntervalSince1970 * 1000 + expIn * 1000)
        } else if let expAt = (obj["expires_at"] as? NSNumber)?.intValue {
            expiresAtMs = expAt
        } else {
            expiresAtMs = Int(Date().timeIntervalSince1970 * 1000) + 3600_000
        }

        // (2) 재기록 전 재독-비교: refreshToken이 바뀌었으면 동시 갱신 → 내 쓰기 포기.
        if let current = readCredentials() {
            if let storedRT = current.refreshToken, storedRT != rt {
                return isExpired(current) ? nil : current
            }
        }
        writeBackKeychain(base: expired.rawObject,
                          accessToken: newAccess, refreshToken: newRefresh, expiresAtMs: expiresAtMs)

        return Credentials(accessToken: newAccess, expiresAtMs: expiresAtMs,
                           refreshToken: newRefresh, rawObject: expired.rawObject)
    }

    /// claudeAiOauth 래퍼 구조를 보존하며 토큰 필드만 병합해 Keychain에 재기록.
    /// 실패는 조용히(best-effort, C2) — 메모리 토큰으로 이번 fetch는 진행된다.
    private static func writeBackKeychain(base: [String: Any],
                                          accessToken: String, refreshToken: String, expiresAtMs: Int) {
        var merged = base
        var oauth = (merged["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = expiresAtMs
        merged["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let json = String(data: data, encoding: .utf8) else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["add-generic-password", "-U",
                          "-s", keychainService,
                          "-a", NSUserName(),
                          "-w", json]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
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
