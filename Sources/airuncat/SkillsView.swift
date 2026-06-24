import SwiftUI

// MARK: - Skills View

struct SkillsView: View {
    var projectCwd: String? = nil
    @State private var skills: [SkillRecord] = []
    @State private var orphans: [OrphanLink] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var repairErrors: [String] = []
    @State private var skillsDirMissing = false

    // Create form state
    @State private var showCreateForm = false
    @State private var createName = ""
    @State private var createDescription = ""
    @State private var createClaude = true
    @State private var createGemini = true
    @State private var createError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            if skillsDirMissing {
                missingSkillsDirNote
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
                                onToggle: { toggle($0, for: $1) },
                                onDelete: { deleteSkill(skill) }
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
            if showCreateForm {
                Divider()
                createFormSection
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
        Text("No skills found in ~/.airuncat/skills")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    private var missingSkillsDirNote: some View {
        VStack(spacing: 4) {
            Text("Skills directory not found")
                .font(.system(size: 12, weight: .medium))
            Text(SkillManager.skillsDir)
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
            Button(showCreateForm ? "취소" : "+ 추가") {
                if showCreateForm {
                    resetCreateForm()
                } else {
                    showCreateForm = true
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(showCreateForm ? .secondary : .accentColor)
            Button("Refresh") {
                Task { await reload() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.accentColor)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Create Form

    @ViewBuilder
    private var createFormSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name
            HStack(spacing: 8) {
                Text("이름")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                TextField("my-skill", text: $createName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: createName) {
                        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
                        let s = createName.lowercased().unicodeScalars.compactMap { c -> Character? in
                            if allowed.contains(c) { return Character(c) }
                            if c == " " || c == "_" { return "-" }
                            if c == "-" { return "-" }
                            return nil
                        }
                        let sanitized = String(s).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                        if sanitized != createName { createName = sanitized }
                    }
            }
            // Description
            HStack(spacing: 8) {
                Text("설명")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                TextField("선택", text: $createDescription)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            // Link toggles
            HStack(spacing: 8) {
                Text("연결")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                FormLinkToggle("C", isOn: $createClaude)
                FormLinkToggle("G", isOn: $createGemini)
                Spacer()
            }
            // Error
            if let err = createError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.leading, 40)
            }
            // Buttons
            HStack {
                Spacer()
                let canCreate = isValidName(createName) && !isDuplicateName(createName)
                Button("생성") { Task { await performCreate() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canCreate ? .accentColor : Color.secondary.opacity(0.5))
                    .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
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
        let cwd = projectCwd
        let (s, o) = await Task.detached(priority: .userInitiated) {
            SkillScanner.scan(projectCwd: cwd)
        }.value
        skillsDirMissing = s.isEmpty && !FileManager.default.fileExists(atPath: SkillManager.skillsDir)
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

    // MARK: - Create / Delete Actions

    private func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 40 else { return false }
        guard name.range(of: "^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$",
                         options: .regularExpression) != nil else { return false }
        return !name.contains("--")
    }

    private func isDuplicateName(_ name: String) -> Bool {
        if skills.contains(where: { $0.id == name }) { return true }
        // Normalize all SKILL_*.md stems to kebab for comparison (handles both _ and - variants)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: SkillManager.skillsDir)
        else { return false }
        return items.contains { file in
            guard file.hasPrefix("SKILL_"), file.hasSuffix(".md") else { return false }
            let stem = String(file.dropFirst("SKILL_".count).dropLast(".md".count))
            return stem.lowercased().replacingOccurrences(of: "_", with: "-") == name
        }
    }

    private func resetCreateForm() {
        showCreateForm = false
        createName = ""
        createDescription = ""
        createClaude = true
        createGemini = true
        createError = nil
    }

    @MainActor
    private func performCreate() async {
        createError = nil
        // Capture @State values before entering detached task (Swift 6: @State is MainActor-isolated)
        let name = createName
        let desc = createDescription
        let lc = createClaude
        let lg = createGemini
        let (record, fileError) = await Task.detached(priority: .userInitiated) {
            SkillToggler.createSkill(name: name, description: desc, linkClaude: lc, linkGemini: lg)
        }.value

        if let err = fileError {
            createError = err
            return
        }
        // Capture link errors before resetting form (resetCreateForm clears createError)
        var linkErr: String? = nil
        if let rec = record, (rec.claudeError != nil || rec.geminiError != nil) {
            linkErr = [rec.claudeError, rec.geminiError].compactMap { $0 }.joined(separator: " / ")
        }
        resetCreateForm()
        await reload()
        // Show link errors in the persistent error banner (visible after form is closed)
        if let err = linkErr {
            repairErrors.append("링크 오류: \(err)")
        }
    }

    private func deleteSkill(_ skill: SkillRecord) {
        let result = SkillToggler.deleteSkill(skill)
        if result.fileError == nil {
            skills.removeAll { $0.id == skill.id }
        }
        Task {
            await reload()  // reload() resets repairErrors; append warnings AFTER
            if let err = result.fileError {
                repairErrors.append(err)
            }
            if !result.warnings.isEmpty {
                repairErrors.append(contentsOf: result.warnings)
            }
        }
    }
}

// MARK: - Skill Row

private struct SkillRow: View {
    let skill: SkillRecord
    let onToggle: (SkillRecord, AI) -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
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
                    if let err = skill.claudeError ?? skill.geminiError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    // Scope badge
                    Text(skill.scope == .project ? "P" : "G")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(skill.scope == .project ? .orange : .secondary)
                        .help(skill.scope == .project ? "프로젝트 로컬 (.claude/commands/)" : "글로벌 (~/.airuncat/skills/)")

                    if skill.scope == .global {
                        LinkBadge("C", state: skill.claudeState) { onToggle(skill, .claude) }
                        LinkBadge("G", state: skill.geminiState) { onToggle(skill, .gemini) }
                        if hovering && !confirmingDelete {
                            Button {
                                confirmingDelete = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("스킬 삭제")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hovering && !confirmingDelete ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                if !confirmingDelete {
                    NSWorkspace.shared.open(URL(fileURLWithPath: skill.sourcePath))
                }
            }
            .help("파인더에서 열기: \(skill.sourcePath)")

            if confirmingDelete && skill.scope == .global {
                Divider().opacity(0.4)
                HStack(spacing: 0) {
                    Button("취소") { confirmingDelete = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("파일 및 링크를 모두 삭제합니다")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                    Spacer()
                    Button("삭제") {
                        confirmingDelete = false
                        onDelete()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.05))
            }
        }
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

// MARK: - Form Link Toggle

private struct FormLinkToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
