import Foundation
import AppKit

// MARK: - Model

enum PaletteItemKind: String, Sendable { case skill, prompt }

struct PaletteItem: Identifiable, Sendable {
    let id: String
    let title: String
    let kind: PaletteItemKind
    let injectText: String   // skill: "/name\n", prompt: body
    var lastUsed: Date?
}

private struct HistoryEntry: Codable {
    let id: String
    let lastUsed: TimeInterval
}

// MARK: - ViewModel

@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { applyFilter() }
    }
    @Published var filtered: [PaletteItem] = []
    @Published var selectedIndex: Int = 0
    @Published var targetSession: SessionInfo? = nil

    private var allItems: [PaletteItem] = []
    private var history: [String: Date] = [:]

    static var historyPath: String { PathConstants.paletteHistory }

    // MARK: - Load (async, called on palette open)

    func load(sessions: [SessionInfo]) async {
        targetSession = detectTarget(sessions)
        history = loadHistory()

        let (skills, _) = await Task.detached(priority: .userInitiated) {
            SkillScanner.scan()
        }.value
        let prompts = await Task.detached(priority: .userInitiated) {
            PromptScanner.scan()
        }.value

        var items: [PaletteItem] = []
        for skill in skills {
            items.append(PaletteItem(
                id: skill.id,
                title: "/\(skill.id)",
                kind: .skill,
                injectText: "/\(skill.id)\n",
                lastUsed: history[skill.id]
            ))
        }
        for prompt in prompts {
            items.append(PaletteItem(
                id: prompt.id,
                title: prompt.title,
                kind: .prompt,
                injectText: prompt.body,
                lastUsed: history[prompt.id]
            ))
        }

        allItems = items
        query = ""
        applyFilter()
    }

    // MARK: - Navigation

    func moveUp() {
        guard !filtered.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveDown() {
        guard !filtered.isEmpty else { return }
        selectedIndex = min(filtered.count - 1, selectedIndex + 1)
    }

    // MARK: - Actions

    @discardableResult
    func inject() -> Bool {
        guard let item = selectedItem, let session = targetSession else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.injectText, forType: .string)
        let ok = ITermController.insertText(cwd: session.cwd)
        recordUsage(id: item.id)
        QuickPalette.shared.hide()
        return ok
    }

    func copyOnly() {
        guard let item = selectedItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.injectText, forType: .string)
        recordUsage(id: item.id)
        QuickPalette.shared.hide()
    }

    func close() {
        QuickPalette.shared.hide()
    }

    // MARK: - Filter

    private func applyFilter() {
        let q = query.trimmingCharacters(in: .whitespaces)

        // (item, relevanceScore) — prefix=2, contains=1, no-query=0
        let scored: [(PaletteItem, Int)]
        if q.isEmpty {
            scored = allItems.map { ($0, 0) }
        } else {
            let lower = q.lowercased()
            scored = allItems.compactMap { item -> (PaletteItem, Int)? in
                let t = item.title.lowercased()
                if t.hasPrefix(lower) { return (item, 2) }
                if t.contains(lower)  { return (item, 1) }
                return nil
            }
        }

        // Sort: relevance first, then recency, then alphabetical
        let result = scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            switch (a.0.lastUsed, b.0.lastUsed) {
            case let (.some(la), .some(lb)): return la > lb
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.0.title < b.0.title
            }
        }.map { $0.0 }

        filtered = result
        selectedIndex = 0
    }

    var selectedItem: PaletteItem? {
        guard selectedIndex < filtered.count else { return nil }
        return filtered[selectedIndex]
    }

    // MARK: - Target detection

    private func detectTarget(_ sessions: [SessionInfo]) -> SessionInfo? {
        let claude = sessions.filter { $0.aiKind == .claude }
        let active = claude.filter { $0.status == .active }.sorted { $0.lastActivity > $1.lastActivity }
        if let first = active.first { return first }
        let idle = claude.filter { $0.status == .idle }.sorted { $0.lastActivity > $1.lastActivity }
        return idle.first
    }

    // MARK: - History persistence

    private func loadHistory() -> [String: Date] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.historyPath)),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, Date(timeIntervalSince1970: $0.lastUsed)) })
    }

    private func recordUsage(id: String) {
        let now = Date()
        history[id] = now
        for i in allItems.indices where allItems[i].id == id {
            allItems[i].lastUsed = now
        }
        saveHistory()
    }

    private func saveHistory() {
        var entries = history.map { HistoryEntry(id: $0.key, lastUsed: $0.value.timeIntervalSince1970) }
        entries.sort { $0.lastUsed > $1.lastUsed }
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let url = URL(fileURLWithPath: Self.historyPath)
        let dir = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: url, options: .atomic)
    }
}
