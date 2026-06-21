import Foundation

enum MCPManager {

    // MARK: - Toggle (enabledMcpjsonServers)

    static func toggle(_ record: MCPRecord) -> String? {
        var settings = readJSON(at: MCPScanner.settingsLocalPath) ?? [:]
        var enabled = settings["enabledMcpjsonServers"] as? [String] ?? []
        if enabled.contains(record.id) {
            enabled.removeAll { $0 == record.id }
        } else {
            enabled.append(record.id)
        }
        settings["enabledMcpjsonServers"] = enabled
        return writeJSON(settings, to: MCPScanner.settingsLocalPath)
    }

    // MARK: - Create

    static func create(name: String, command: String, args: [String]) -> String? {
        // 1. Add to ~/.mcp.json
        var mcp = readJSON(at: MCPScanner.mcpJsonPath) ?? [:]
        var servers = mcp["mcpServers"] as? [String: Any] ?? [:]
        if servers[name] != nil { return "이미 존재하는 서버: \(name)" }

        var entry: [String: Any] = ["command": command]
        if !args.isEmpty { entry["args"] = args }
        servers[name] = entry
        mcp["mcpServers"] = servers
        if let err = writeJSON(mcp, to: MCPScanner.mcpJsonPath) { return err }

        // 2. Add to enabledMcpjsonServers
        var settings = readJSON(at: MCPScanner.settingsLocalPath) ?? [:]
        var enabled = settings["enabledMcpjsonServers"] as? [String] ?? []
        if !enabled.contains(name) { enabled.append(name) }
        settings["enabledMcpjsonServers"] = enabled
        if let err = writeJSON(settings, to: MCPScanner.settingsLocalPath) {
            return "서버 등록 완료, 활성화 실패 (수동 토글 필요): \(err)"
        }
        return nil
    }

    // MARK: - Delete

    static func delete(_ record: MCPRecord) -> String? {
        // 1. Remove from ~/.mcp.json
        guard var mcp = readJSON(at: MCPScanner.mcpJsonPath),
              var servers = mcp["mcpServers"] as? [String: Any]
        else { return "~/.mcp.json 읽기 실패" }
        servers.removeValue(forKey: record.id)
        mcp["mcpServers"] = servers
        if let err = writeJSON(mcp, to: MCPScanner.mcpJsonPath) { return err }

        // 2. Remove from enabledMcpjsonServers (best-effort)
        if var settings = readJSON(at: MCPScanner.settingsLocalPath),
           var enabled = settings["enabledMcpjsonServers"] as? [String] {
            enabled.removeAll { $0 == record.id }
            settings["enabledMcpjsonServers"] = enabled
            _ = writeJSON(settings, to: MCPScanner.settingsLocalPath)
        }
        return nil
    }

    // MARK: - Private

    static func readJSON(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @discardableResult
    static func writeJSON(_ dict: [String: Any], to path: String) -> String? {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys]
            )
            // Append trailing newline for clean diffs
            var out = data
            if let nl = "\n".data(using: .utf8) { out += nl }
            try out.write(to: URL(fileURLWithPath: path), options: .atomic)
            return nil
        } catch {
            return "파일 쓰기 실패: \(error.localizedDescription)"
        }
    }
}
