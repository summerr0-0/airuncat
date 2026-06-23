import Foundation

// MARK: - Model

struct MCPRecord: Identifiable {
    let id: String           // server name
    let command: String
    let args: [String]
    let env: [String: String]
    var enabled: Bool        // present in enabledMcpjsonServers
    let sourcePath: String   // ~/.mcp.json
}

// MARK: - Scanner

enum MCPScanner {
    static var mcpJsonPath: String { PathConstants.mcpJson }
    static var settingsLocalPath: String { PathConstants.claudeSettingsLocal }

    static func scan() -> [MCPRecord] {
        let enabled = enabledNames()
        return parseServers(at: mcpJsonPath, enabledNames: enabled)
    }

    // MARK: - Helpers

    static func enabledNames() -> Set<String> {
        guard let data = FileManager.default.contents(atPath: settingsLocalPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["enabledMcpjsonServers"] as? [String]
        else { return [] }
        return Set(arr)
    }

    static func parseServers(at path: String, enabledNames: Set<String>) -> [MCPRecord] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any]
        else { return [] }

        return servers.compactMap { name, value -> MCPRecord? in
            guard let cfg = value as? [String: Any] else { return nil }
            let command = cfg["command"] as? String ?? ""
            let args = cfg["args"] as? [String] ?? []
            let env = cfg["env"] as? [String: String] ?? [:]
            return MCPRecord(
                id: name,
                command: command,
                args: args,
                env: env,
                enabled: enabledNames.contains(name),
                sourcePath: path
            )
        }
        .sorted { $0.id < $1.id }
    }
}
