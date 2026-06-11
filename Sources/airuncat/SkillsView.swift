import SwiftUI

// MARK: - Skills View

struct SkillsView: View {
    @State private var skills: [SkillRecord] = []
    @State private var orphans: [OrphanLink] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var repairErrors: [String] = []
    @State private var obsidianMissing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            if obsidianMissing {
                missingObsidianNote
            } else if isLoading {
                loadingRow
            } else if skills.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSkills) { skill in
                            SkillRow(
                                skill: skill,
                                onToggle: { toggle($0, for: $1) }
                            )
                            Divider().opacity(0.4)
                        }
                        if !orphans.isEmpty {
                            orphanSection
                        }
                        if !repairErrors.isEmpty {
                            errorBanner
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            Divider()
            bottomBar
        }
        .task { await reload() }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Search skills", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var loadingRow: some View {
        Text("Scanning…")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    private var emptyState: some View {
        Text("No skills found in Obsidian/06_AI_Config")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    private var missingObsidianNote: some View {
        VStack(spacing: 4) {
            Text("Obsidian vault not found")
                .font(.system(size: 12, weight: .medium))
            Text(SkillScanner.obsidianBase)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    private var orphanSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Orphan Links")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(orphans) { orphan in
                OrphanRow(orphan: orphan, onDelete: { deleteOrphan(orphan) })
                Divider().opacity(0.4)
            }
        }
    }

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(repairErrors, id: \.self) { err in
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
    }

    private var bottomBar: some View {
        HStack {
            let brokenCount = skills.filter {
                $0.claudeState == .broken || $0.geminiState == .broken
            }.count
            let unlinkedGemini = skills.filter { $0.geminiState == .unlinked }.count

            if brokenCount > 0 {
                Button("수리 (\(brokenCount))") { repairAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            } else if unlinkedGemini > 0 {
                Text("Gemini 미연결 \(unlinkedGemini)개")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Refresh") {
                Task { await reload() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Computed

    private var filteredSkills: [SkillRecord] {
        guard !searchText.isEmpty else { return skills }
        let q = searchText.lowercased()
        return skills.filter { $0.id.contains(q) || $0.description.lowercased().contains(q) }
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        isLoading = true
        let (s, o) = await Task.detached(priority: .userInitiated) {
            SkillScanner.scan()
        }.value
        obsidianMissing = s.isEmpty && !FileManager.default.fileExists(atPath: SkillScanner.obsidianBase)
        skills = s
        orphans = o
        repairErrors = []
        isLoading = false
    }

    private func toggle(_ skill: SkillRecord, for ai: AI) {
        guard let idx = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        let current = ai == .claude ? skill.claudeState : skill.geminiState
        let error: String?
        if current == .linked {
            error = SkillToggler.disable(skill, for: ai)
        } else {
            error = SkillToggler.enable(skill, for: ai)
        }
        if let err = error {
            if ai == .claude { skills[idx].claudeError = err }
            else             { skills[idx].geminiError = err }
        } else {
            // Re-check state from disk
            let claudeState = SkillScanner.linkState(at: skills[idx].claudeLinkPath)
            let newGeminiLink = SkillScanner.geminiLinkPath(for: skills[idx].id)
            let geminiState = SkillScanner.linkState(at: newGeminiLink)
            skills[idx].claudeState = claudeState
            skills[idx].geminiState = geminiState
            skills[idx].geminiLinkPath = newGeminiLink
            if ai == .claude { skills[idx].claudeError = nil }
            else             { skills[idx].geminiError = nil }
        }
    }

    private func repairAll() {
        let errors = SkillToggler.repairAll(skills)
        repairErrors = errors.map { "\($0.name): \($0.error)" }
        // Refresh states
        for idx in skills.indices {
            skills[idx].claudeState = SkillScanner.linkState(at: skills[idx].claudeLinkPath)
            let newLink = SkillScanner.geminiLinkPath(for: skills[idx].id)
            skills[idx].geminiState = SkillScanner.linkState(at: newLink)
            skills[idx].geminiLinkPath = newLink
        }
    }

    private func deleteOrphan(_ orphan: OrphanLink) {
        if let err = SkillToggler.deleteOrphan(orphan) {
            repairErrors.append(err)
        } else {
            orphans.removeAll { $0.id == orphan.id }
        }
    }
}

// MARK: - Skill Row

private struct SkillRow: View {
    let skill: SkillRecord
    let onToggle: (SkillRecord, AI) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.id)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                // Inline errors
                if let err = skill.claudeError ?? skill.geminiError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                LinkBadge("C", state: skill.claudeState) { onToggle(skill, .claude) }
                LinkBadge("G", state: skill.geminiState) { onToggle(skill, .gemini) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: skill.obsidianPath))
        }
        .help("Obsidian에서 열기: \(skill.obsidianPath)")
    }
}

// MARK: - Link Badge

private struct LinkBadge: View {
    let label: String
    let state: LinkState
    let action: () -> Void

    init(_ label: String, state: LinkState, action: @escaping () -> Void) {
        self.label = label
        self.state = state
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                Text(stateGlyph)
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(badgeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundColor(badgeForeground)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var stateGlyph: String {
        switch state {
        case .linked:   return "✓"
        case .broken:   return "⚠"
        case .unlinked: return "–"
        }
    }

    private var badgeBackground: Color {
        switch state {
        case .linked:   return Color.green.opacity(0.18)
        case .broken:   return Color.red.opacity(0.18)
        case .unlinked: return Color.primary.opacity(0.07)
        }
    }

    private var badgeForeground: Color {
        switch state {
        case .linked:   return .green
        case .broken:   return .red
        case .unlinked: return .secondary
        }
    }

    private var helpText: String {
        switch state {
        case .linked:   return "\(label) 연결됨 — 클릭으로 해제"
        case .broken:   return "\(label) 링크 깨짐 — 클릭으로 수리"
        case .unlinked: return "\(label) 미연결 — 클릭으로 연결"
        }
    }
}

// MARK: - Orphan Row

private struct OrphanRow: View {
    let orphan: OrphanLink
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(orphan.kind == .claude ? "C" : "G")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 3).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(orphan.id)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.7))
                Text(orphan.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if hovering {
                Button("삭제") { onDelete() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovering ? Color.orange.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
