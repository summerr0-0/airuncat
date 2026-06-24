import Foundation

/// Central registry of all filesystem paths used by airuncat.
/// Replaces ad-hoc NSHomeDirectory() + appendingPathComponent() calls scattered
/// across individual scanners and managers.
enum PathConstants {
    private static let home = NSHomeDirectory() as NSString
    private static func p(_ rel: String) -> String { home.appendingPathComponent(rel) }

    // MARK: - Claude Code

    static var claudeProjects:      String { p(".claude/projects") }
    static var claudeCommands:      String { p(".claude/commands") }
    static var claudeRules:         String { p(".claude/rules") }
    static var claudeSettings:      String { p(".claude/settings.json") }
    static var claudeSettingsLocal: String { p(".claude/settings.local.json") }
    static var globalClaudeMd:      String { p(".claude/CLAUDE.md") }
    static var mcpJson:             String { p(".mcp.json") }

    // MARK: - Gemini CLI

    static var geminiCommands:      String { p(".gemini/commands") }
    static var geminiTmp:           String { p(".gemini/tmp") }

    // MARK: - airuncat

    static var airuncatBase:        String { p(".airuncat") }
    static var skills:              String { p(".airuncat/skills") }
    static var prompts:             String { p(".airuncat/prompts") }
    static var statsCache:          String { p(".airuncat/stats-cache.json") }
    static var paletteHistory:      String { p(".airuncat/palette-history.json") }
    static var customNames:         String { p(".airuncat/custom-names.json") }
    static var tags:                String { p(".airuncat/tags.json") }
    static var tagPool:             String { p(".airuncat/tag-pool.json") }
}
