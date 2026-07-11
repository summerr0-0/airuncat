import Foundation

@MainActor
final class TagStore: ObservableObject {
    @Published private(set) var sessionTags: [String: [String]] = [:]
    @Published private(set) var tagPool: [String] = []

    private static let presets = ["work", "personal", "urgent"]

    private let tagsURL: URL
    private let poolURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        tagsURL = URL(fileURLWithPath: PathConstants.tags)
        poolURL = URL(fileURLWithPath: PathConstants.tagPool)
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: PathConstants.airuncatBase),
            withIntermediateDirectories: true)
        load()
    }

    func tags(for id: String) -> [String] { sessionTags[id] ?? [] }

    func addTag(_ tag: String, to id: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return }
        var list = sessionTags[id] ?? []
        guard !list.contains(t) else { return }
        list.append(t)
        sessionTags[id] = list
        if !tagPool.contains(t) { tagPool.append(t) }
        scheduleSave()
    }

    func renameTag(_ old: String, to new: String) {
        let t = new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, t != old, !tagPool.contains(t) else { return }
        if let idx = tagPool.firstIndex(of: old) { tagPool[idx] = t }
        for (id, tags) in sessionTags where tags.contains(old) {
            sessionTags[id] = tags.map { $0 == old ? t : $0 }
        }
        scheduleSave()
    }

    func removeTag(_ tag: String, from id: String) {
        var list = sessionTags[id] ?? []
        list.removeAll { $0 == tag }
        sessionTags[id] = list.isEmpty ? nil : list
        prunePool()
        scheduleSave()
    }

    private func prunePool() {
        let used = Set(sessionTags.values.flatMap { $0 })
        let presetSet = Set(Self.presets)
        tagPool = tagPool.filter { used.contains($0) || presetSet.contains($0) }
    }

    private func load() {
        if let d = try? Data(contentsOf: tagsURL),
           let v = try? JSONDecoder().decode([String: [String]].self, from: d) {
            sessionTags = v
        }
        if let d = try? Data(contentsOf: poolURL),
           let v = try? JSONDecoder().decode([String].self, from: d) {
            tagPool = v
        } else {
            // First run — seed with presets
            tagPool = Self.presets
        }
        // Do NOT force-reinsert presets: respects user renames of preset tags
    }

    // Debounced: coalesces rapid tag changes into one write
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                self?.save()
            } catch {}
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(sessionTags) { try? d.write(to: tagsURL, options: .atomic) }
        if let d = try? JSONEncoder().encode(tagPool) { try? d.write(to: poolURL, options: .atomic) }
    }
}
