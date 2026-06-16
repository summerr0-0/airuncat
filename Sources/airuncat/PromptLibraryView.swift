import SwiftUI
import AppKit

struct PromptLibraryView: View {
    @ObservedObject var store: SessionStore
    @State private var prompts: [PromptRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var initialLoaded = false
    @State private var insertError: String? = nil
    @State private var insertErrorTask: Task<Void, Never>? = nil
    @State private var repairErrors: [String] = []
    @State private var scanID = UUID()

    // Create form
    @State private var showCreateForm = false
    @State private var createId = ""
    @State private var createTitle = ""
    @State private var createCategory = ""
    @State private var createBody = ""
    @State private var createPinned = false
    @State private var createError: String? = nil

    private var insertTarget: SessionInfo? {
        store.visibleSessions.first { $0.status != .resting }
    }

    private var filtered: [PromptRecord] {
        guard !searchText.isEmpty else { return prompts }
        let q = searchText.lowercased()
        return prompts.filter { p in
            p.title.lowercased().contains(q)
                || p.tags.contains { $0.lowercased().contains(q) }
                || p.category.lowercased().contains(q)
        }
    }

    private var pinned: [PromptRecord] { filtered.filter(\.pinned) }
    private var unpinned: [PromptRecord] { filtered.filter { !$0.pinned } }
    private var categories: [String] {
        var seen = Set<String>()
        return unpinned.compactMap { p in
            seen.insert(p.category).inserted ? p.category : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                loadingView
            } else {
                if let target = insertTarget {
                    insertHeader(target)
                    Divider()
                }
                if !repairErrors.isEmpty {
                    repairErrorsBanner
                    Divider()
                }
                if let err = insertError {
                    errorBanner(err)
                    Divider()
                }
                if prompts.isEmpty && !showCreateForm {
                    emptyState
                } else {
                    searchBar
                    Divider()
                    if filtered.isEmpty && !showCreateForm {
                        noResultsView
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if !pinned.isEmpty { pinnedSection }
                                ForEach(categories, id: \.self) { categorySection($0) }
                                if showCreateForm { createFormSection }
                            }
                        }
                        .frame(maxHeight: 360)
                    }
                }
            }
            Divider()
            bottomBar
        }
        .task(id: scanID) {
            if !initialLoaded { isLoading = true }
            prompts = await Task.detached(priority: .background) {
                PromptScanner.scan()
            }.value
            isLoading = false
            initialLoaded = true
        }
        .onAppear { scanID = UUID() }
        .onChange(of: searchText) { _ in insertError = nil }
    }

    // MARK: - Static Views

    private var loadingView: some View {
        Text("스캔 중...")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("프롬프트 없음")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("+ 추가로 새 프롬프트를 만들거나\nFinder로 파일을 직접 추가하세요")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
    }

    private var noResultsView: some View {
        Text("검색 결과 없음")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
    }

    private var repairErrorsBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(repairErrors, id: \.self) { err in
                    Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(2)
                }
            }
            Spacer()
            Button(action: { repairErrors = [] }) {
                Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Search prompts...", text: $searchText)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("pinned")
            ForEach(pinned) { p in
                PromptRow(prompt: p, insertTarget: insertTarget,
                          onInsertError: { showInsertError($0) },
                          onDelete: { deletePrompt(p) },
                          onTogglePin: { togglePin(p) })
            }
        }
    }

    private func categorySection(_ category: String) -> some View {
        let items = unpinned.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 0) {
            if !pinned.isEmpty || category != categories.first {
                Divider().opacity(0.4).padding(.top, 4)
            }
            sectionHeader(category)
            ForEach(items) { p in
                PromptRow(prompt: p, insertTarget: insertTarget,
                          onInsertError: { showInsertError($0) },
                          onDelete: { deletePrompt(p) },
                          onTogglePin: { togglePin(p) })
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func insertHeader(_ target: SessionInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("Insert to:")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(target.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button(action: openInFinder) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .help("~/.airuncat/prompts/ 열기")

            Divider().frame(height: 14)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { showCreateForm.toggle() }
                if !showCreateForm { resetCreateForm() }
            }) {
                Text(showCreateForm ? "취소" : "+ 추가")
                    .font(.system(size: 11))
                    .foregroundColor(showCreateForm ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Spacer()

            Button(action: { scanID = UUID() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .help("새로고침")
        }
    }

    // MARK: - Create Form

    @ViewBuilder
    private var createFormSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("ID")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    TextField("kebab-case (예: my-prompt)", text: $createId)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                        .onChange(of: createId) { val in sanitizeId(val) }
                }
                HStack(spacing: 6) {
                    Text("제목")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    TextField("표시 이름", text: $createTitle)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                }
                HStack(spacing: 6) {
                    Text("카테고리")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    TextField("dev, workflow...", text: $createCategory)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                }
                HStack(spacing: 6) {
                    Text("내용")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    TextField("프롬프트 본문 (긴 내용은 Finder에서 편집)", text: $createBody)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                }
                HStack(spacing: 8) {
                    Spacer().frame(width: 50)
                    Toggle(isOn: $createPinned) {
                        Text("핀").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    if let err = createError {
                        Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(1)
                    }
                    Button("생성") { Task { await performCreate() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isValidId(createId) && !isDuplicateId(createId) ? .accentColor : .secondary)
                        .disabled(!isValidId(createId) || isDuplicateId(createId))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func openInFinder() {
        try? FileManager.default.createDirectory(atPath: PromptManager.promptsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: PromptManager.promptsDir))
    }

    private func sanitizeId(_ val: String) {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let s = val.lowercased().unicodeScalars.compactMap { c -> Character? in
            if allowed.contains(c) { return Character(c) }
            if c == " " || c == "_" || c == "-" { return Character("-") }
            return nil
        }
        let sanitized = String(s).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if sanitized != val { createId = sanitized }
    }

    private func isValidId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 40 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for scalar in id.unicodeScalars {
            if !allowed.contains(scalar) { return false }
        }
        if id.hasPrefix("-") || id.hasSuffix("-") { return false }
        if id.contains("--") { return false }
        return true
    }

    private func isDuplicateId(_ id: String) -> Bool {
        if prompts.contains(where: { $0.id == id }) { return true }
        let path = (PromptManager.promptsDir as NSString).appendingPathComponent("\(id).md")
        return FileManager.default.fileExists(atPath: path)
    }

    @MainActor
    private func performCreate() async {
        createError = nil
        let id = createId
        let title = createTitle.isEmpty ? id : createTitle
        let category = createCategory
        let body = createBody
        let pinned = createPinned

        let error = await Task.detached(priority: .userInitiated) {
            PromptManager.createPrompt(id: id, title: title, category: category, body: body, pinned: pinned)
        }.value

        if let err = error { createError = err; return }
        resetCreateForm()
        scanID = UUID()
    }

    private func resetCreateForm() {
        createId = ""; createTitle = ""; createCategory = ""; createBody = ""
        createPinned = false; createError = nil
        showCreateForm = false
    }

    private func deletePrompt(_ prompt: PromptRecord) {
        let err = PromptManager.deletePrompt(prompt)
        if err == nil { prompts.removeAll { $0.id == prompt.id } }
        scanID = UUID()
        if let e = err { repairErrors.append(e) }
    }

    private func togglePin(_ prompt: PromptRecord) {
        let err = PromptManager.togglePin(prompt)
        if err == nil {
            if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
                prompts[idx].pinned.toggle()
            }
        } else if let e = err {
            repairErrors.append(e)
            scanID = UUID()
        }
    }

    private func showInsertError(_ message: String) {
        insertError = message
        insertErrorTask?.cancel()
        insertErrorTask = Task {
            try? await Task.sleep(for: .seconds(3))
            insertError = nil
        }
    }
}

// MARK: - Prompt Row

private struct PromptRow: View {
    let prompt: PromptRecord
    let insertTarget: SessionInfo?
    let onInsertError: (String) -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    @State private var copied = false
    @State private var copyTask: Task<Void, Never>? = nil
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if prompt.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.accentColor.opacity(0.6))
                        .rotationEffect(.degrees(45))
                }
                Text(prompt.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering || copied {
                    HStack(spacing: 4) {
                        if let target = insertTarget {
                            Button(action: { doInsert(to: target) }) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Insert into \(target.title)")
                        }
                        Button(action: doCopy) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(copied ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                        Button(action: onTogglePin) {
                            Image(systemName: prompt.pinned ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .foregroundColor(prompt.pinned ? .accentColor.opacity(0.7) : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(prompt.pinned ? "핀 해제" : "핀")
                        Button(action: { confirmingDelete = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("삭제")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }

            if confirmingDelete {
                HStack(spacing: 8) {
                    Button("취소") { confirmingDelete = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("파일을 영구 삭제합니다")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Spacer()
                    Button("삭제") { onDelete() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.06))
            }
        }
    }

    private func doCopy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.body, forType: .string)
        copied = true
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(for: .seconds(1))
            copied = false
        }
    }

    private func doInsert(to session: SessionInfo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.body, forType: .string)
        if !ITermController.insertText(cwd: session.cwd) {
            onInsertError("삽입 실패 — iTerm 자동화/접근성 권한 확인")
        }
    }
}
