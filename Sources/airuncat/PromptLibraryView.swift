import SwiftUI
import AppKit

struct PromptLibraryView: View {
    @ObservedObject var store: SessionStore
    @State private var prompts: [PromptRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var insertError: String? = nil
    @State private var insertErrorTask: Task<Void, Never>? = nil
    @State private var scanID = UUID()

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
            } else if prompts.isEmpty {
                emptyState
            } else {
                if let target = insertTarget {
                    insertHeader(target)
                    Divider()
                }
                if let err = insertError {
                    errorBanner(err)
                    Divider()
                }
                searchBar
                Divider()
                if filtered.isEmpty {
                    noResultsView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !pinned.isEmpty { pinnedSection }
                            ForEach(categories, id: \.self) { categorySection($0) }
                        }
                    }
                    .frame(maxHeight: 360)
                }
            }
        }
        .task(id: scanID) {
            isLoading = true
            prompts = await Task.detached(priority: .background) {
                PromptScanner.scan()
            }.value
            isLoading = false
        }
        .onAppear { scanID = UUID() }
        .onChange(of: searchText) { _ in
            insertError = nil
        }
    }

    // MARK: - Subviews

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
            Text("~/Obsidian/document/07_Prompts/\nPROMPT_*.md 파일을 추가하세요")
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
                PromptRow(prompt: p, insertTarget: insertTarget) { err in
                    showInsertError(err)
                }
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
                PromptRow(prompt: p, insertTarget: insertTarget) { err in
                    showInsertError(err)
                }
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

    @State private var copied = false
    @State private var copyTask: Task<Void, Never>? = nil
    @State private var hovering = false

    var body: some View {
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
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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
