import SwiftUI

// MARK: - Skills View

private struct SkillSection: Identifiable {
    let id: String
    let title: String
    let items: [SkillRecord]
}

struct SkillsView: View {
    var projectCwds: [String] = []
    @State private var skills: [SkillRecord] = []
    @State private var orphans: [OrphanLink] = []
    @State private var searchText = ""
    @State private var collapsed: Set<String> = []   // 접힌 섹션 id
    @State private var isLoading = true
    @State private var repairErrors: [String] = []

    // Create form state
    @State private var showCreateForm = false
    @State private var createName = ""
    @State private var createDescription = ""
    @State private var createGemini = true
    @State private var createError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            if isLoading {
                loadingRow
            } else if skills.isEmpty && orphans.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(skillSections) { section in
                            sectionHeader(section)
                            if !collapsed.contains(section.id) {
                                ForEach(section.items) { skill in
                                    SkillRow(
                                        skill: skill,
                                        onToggleGemini: { toggleGemini($0) },
                                        onDelete: { deleteSkill(skill) }
                                    )
                                    Divider().opacity(0.4)
                                }
                            }
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
        .task(id: projectCwds) { await reload() }
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
        Text("No skills found in ~/.claude/skills")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
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
            let brokenCount = skills.filter { $0.geminiState == .broken }.count
            let unlinkedGemini = skills.filter {
                $0.scope == .native && $0.geminiState == .unlinked
            }.count

            if brokenCount > 0 {
                Button("수리 (\(brokenCount))") { repairAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            } else if unlinkedGemini > 0 {
                Text("Gemini 미복제 \(unlinkedGemini)개")
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
            // Gemini replication toggle — Claude는 항상 활성이라 선택지가 없다
            HStack(spacing: 8) {
                Text("복제")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                FormLinkToggle("G", isOn: $createGemini)
                Text(createGemini ? "Antigravity(Gemini)에도 복제" : "Claude 전용")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
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

    /// 스코프별 섹션. 글로벌(네이티브, 출처별) → 프로젝트(폴더별).
    private var skillSections: [SkillSection] {
        let items = filteredSkills
        var out: [SkillSection] = []
        // 글로벌: 로컬 실체는 "글로벌", symlink 출처는 "글로벌 · <repo>".
        out.append(contentsOf: groupedSections(items.filter { $0.scope == .native },
                                               idPrefix: "global", titlePrefix: "글로벌", fallback: "로컬"))
        out.append(contentsOf: groupedSections(items.filter { $0.scope == .project },
                                               idPrefix: "project", titlePrefix: "프로젝트", fallback: "프로젝트"))
        return out
    }

    /// scope가 같은 레코드들을 group(출처/프로젝트)별 섹션으로 나눈다(등장 순서 유지).
    private func groupedSections(_ items: [SkillRecord], idPrefix: String,
                                 titlePrefix: String, fallback: String) -> [SkillSection] {
        var seen = Set<String>(), groups: [String] = []
        for s in items { let g = s.group ?? fallback; if seen.insert(g).inserted { groups.append(g) } }
        return groups.map { g in
            let title = (idPrefix == "global" && g == "로컬") ? titlePrefix : "\(titlePrefix) · \(g)"
            return SkillSection(id: "\(idPrefix)-\(g)", title: title,
                                items: items.filter { ($0.group ?? fallback) == g })
        }
    }

    private func sectionHeader(_ section: SkillSection) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 9)
                Text(section.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("\(section.items.count)")
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        isLoading = true
        let cwds = projectCwds
        let (s, o) = await Task.detached(priority: .userInitiated) {
            SkillScanner.scan(projectCwds: cwds)
        }.value
        skills = s
        orphans = o
        repairErrors = []
        isLoading = false
    }

    private func toggleGemini(_ skill: SkillRecord) {
        guard let idx = skills.firstIndex(where: { $0.id == skill.id && $0.scope == .native }) else { return }
        let error: String?
        if skill.geminiState == .linked {
            error = SkillToggler.disableGemini(skill)
        } else {
            error = SkillToggler.enableGemini(skill)
        }
        if let err = error {
            skills[idx].geminiError = err
        } else {
            // Re-check state from disk
            let newLink = SkillScanner.geminiLinkPath(for: skills[idx].id)
            skills[idx].geminiState = SkillScanner.linkState(at: newLink)
            skills[idx].geminiLinkPath = newLink
            skills[idx].geminiError = nil
        }
    }

    private func repairAll() {
        let errors = SkillToggler.repairAll(skills)
        repairErrors = errors.map { "\($0.name): \($0.error)" }
        // Refresh states
        for idx in skills.indices where skills[idx].scope == .native {
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
        if skills.contains(where: { $0.id == name && $0.scope == .native }) { return true }
        let dir = (PathConstants.claudeSkills as NSString).appendingPathComponent(name)
        var st = stat()
        return lstat(dir, &st) == 0   // 깨진 symlink도 자리 차지 — fileExists는 놓친다
    }

    private func resetCreateForm() {
        showCreateForm = false
        createName = ""
        createDescription = ""
        createGemini = true
        createError = nil
    }

    @MainActor
    private func performCreate() async {
        createError = nil
        // Capture @State values before entering detached task (Swift 6: @State is MainActor-isolated)
        let name = createName
        let desc = createDescription
        let lg = createGemini
        let (record, fileError) = await Task.detached(priority: .userInitiated) {
            SkillToggler.createSkill(name: name, description: desc, linkGemini: lg)
        }.value

        if let err = fileError {
            createError = err
            return
        }
        // Capture link errors before resetting form (resetCreateForm clears createError)
        var linkErr: String? = nil
        if let rec = record, let ge = rec.geminiError {
            linkErr = ge
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
            skills.removeAll { $0.id == skill.id && $0.scope == .native }
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
    let onToggleGemini: (SkillRecord) -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var confirmingDelete = false

    private var canManage: Bool { skill.scope == .native }

    /// 스킬 디렉토리가 외부 repo로의 symlink인지 (삭제 시 링크만 해제됨).
    private var isLinkedDir: Bool {
        let dir = (skill.sourcePath as NSString).deletingLastPathComponent
        var st = stat()
        return lstat(dir, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

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
                    if let err = skill.geminiError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    if skill.scope == .project {
                        Text("P")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                            .help("프로젝트 로컬 (.claude/commands · skills)")
                    }

                    if canManage {
                        LinkBadge("G", state: skill.geminiState) { onToggleGemini(skill) }
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

            if confirmingDelete && canManage {
                Divider().opacity(0.4)
                HStack(spacing: 0) {
                    Button("취소") { confirmingDelete = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(isLinkedDir ? "외부 연결 링크만 해제됩니다 (원본 보존)"
                                     : "스킬 폴더 전체와 Gemini 링크를 삭제합니다")
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
                // 글자색 = AI 정체성(Gemini 청록), 글리프·배경 = 링크 상태
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AiruncatDesign.aiColor(.gemini))
                Text(stateGlyph)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(badgeForeground)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(badgeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
        case .linked:   return "Antigravity(Gemini)에 복제됨 — 클릭으로 해제"
        case .broken:   return "Antigravity(Gemini) 링크 깨짐 — 클릭으로 수리"
        case .unlinked: return "Antigravity(Gemini) 미복제 — 클릭으로 복제"
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
                .background(Color.orange.opacity(0.15))   // 고아 링크 경고 맥락
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .foregroundColor(AiruncatDesign.aiColor(orphan.kind == .claude ? .claude : .gemini))

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
                .background(isOn ? AiruncatDesign.aiColor(.gemini).opacity(0.18) : Color.primary.opacity(0.07))
                .foregroundColor(isOn ? AiruncatDesign.aiColor(.gemini) : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
